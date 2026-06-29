#!/usr/bin/env ruby
# frozen_string_literal: true

# Validate device JSON files for schema compliance
# Usage:
#   ruby tools/validate_devices.rb [--root PATH] [--fix]
#
# Validates:
#   - Required fields: schemaVersion, implementationVersion, title, displayName, receives, transmits
#   - schemaVersion must be "0.1.1"
#   - device object must contain displayName, manufacturer, model, version
#   - Correct key names (controlChangeCommands, not "controls" or "controlChangeMessages")
#   - Valid CC entry structure (including duplicate controlChangeNumber rejection)
#   - x_pc custom extension format (incl. bankSelectMode: none, CC0, CC0_CC32)
#   - x_midiTrs values (TYPE_A, TYPE_B, TYPE_TS, BOTH)
#   - x_variants / x_mandatory CC extensions (constraint shape, ops, gating cc, name length, discrete bounds)
#   - Strict "x_" whitelist: any unknown x_-prefixed key is an error
#   - receives/transmits values match MIDI RTC JSON schema
#
# With --fix:
#   - Removes CONTROL_CHANGE and SYSEX from receives/transmits
#   - Replaces NOTE_ON/NOTE_OFF with NOTE_NUMBER
#   - Replaces AFTERTOUCH with CHANNEL_PRESSURE

require "json"
require "optparse"
require "pathname"

options = {
  root: Pathname.new(__dir__).join("..").expand_path.to_s,
  fix: false
}

OptionParser.new do |opts|
  opts.banner = "Usage: #{$0} [options]"
  opts.on("--root PATH", "Repo root (default: parent of tools/)") { |v| options[:root] = v }
  opts.on("--fix", "Attempt to fix common issues (renames keys)") { options[:fix] = true }
end.parse!

root = Pathname.new(options[:root]).expand_path
devices_dir = root.join("devices")
abort "ERR: devices directory not found: #{devices_dir}" unless devices_dir.exist?

# Known incorrect key names that should be controlChangeCommands
CC_KEY_ALIASES = %w[controls controlChangeMessages].freeze
CORRECT_CC_KEY = "controlChangeCommands"

# Required top-level fields
REQUIRED_FIELDS = %w[schemaVersion implementationVersion title displayName receives transmits].freeze

EXPECTED_SCHEMA_VERSION = "0.1.1"

# Required fields within the device sub-object
REQUIRED_DEVICE_FIELDS = %w[displayName manufacturer model version].freeze

# Valid values for receives/transmits (from MIDI RTC JSON schema)
VALID_MESSAGE_TYPES = %w[
  NOTE_NUMBER
  PROGRAM_CHANGE
  VELOCITY_NOTE_ON
  VELOCITY_NOTE_OFF
  CHANNEL_PRESSURE
  POLY_PRESSURE
  PITCH_BEND
  CLOCK
  TRANSPORT_START
  TRANSPORT_STOP
  TRANSPORT_CONTINUE
].freeze

# Message types to remove entirely
REMOVE_MESSAGE_TYPES = %w[
  CONTROL_CHANGE
  SYSEX
].freeze

# Message type replacements (old => new)
MESSAGE_TYPE_REPLACEMENTS = {
  "NOTE_ON" => "NOTE_NUMBER",
  "NOTE_OFF" => "NOTE_NUMBER",
  "AFTERTOUCH" => "CHANNEL_PRESSURE"
}.freeze

# Valid values for x_midiTrs extension
VALID_TRS_TYPES = %w[TYPE_A TYPE_B TYPE_TS BOTH].freeze

# Valid values for the x_pc.bankSelectMode extension (matches firmware assets_parser.c)
VALID_BANK_SELECT_MODES = %w[none CC0 CC0_CC32].freeze

# Whitelist of allowed "x_" extension keys. Any "x_"-prefixed key not on the
# appropriate list is an error (catches typos like x_midiTrsType and hallucinated
# keys like x_programChangeMessages). See web/schemas/storm-summoner-extensions.schema.json.
ALLOWED_TOP_LEVEL_X_KEYS = %w[x_pc x_midiTrs x_midiChannel].freeze
ALLOWED_CC_X_KEYS = %w[x_variants x_mandatory x_noop].freeze

# Valid comparison operators for x_variants constraints
VALID_VARIANT_OPS = %w[< <= > >= == !=].freeze

# Maximum display length for CC / variant names (small device screen)
MAX_NAME_LENGTH = 14

class DeviceValidator
  attr_reader :path, :json, :errors, :warnings, :fixed

  def initialize(path)
    @path = path
    @errors = []
    @warnings = []
    @fixed = false
    @json = nil
  end

  def validate
    begin
      content = File.read(@path, encoding: "bom|utf-8")
      comment_lines = detect_json_comments(content)
      if comment_lines.any?
        @errors << "JSON contains // or /* */ comments at line(s) #{comment_lines.join(', ')}; " \
                   "standard JSON disallows comments and the on-device cJSON parser will reject the file"
        return false
      end
      @json = JSON.parse(content)
    rescue JSON::ParserError => e
      @errors << "Invalid JSON: #{e.message}"
      return false
    end

    validate_required_fields
    validate_metadata
    validate_device_object
    validate_cc_key_name
    validate_cc_entries
    validate_x_pc
    validate_x_midi_trs
    validate_top_level_x_keys
    validate_receives_transmits_values

    @errors.empty?
  end

  def fix!
    return false unless @json

    changed = false

    # Fix incorrect CC key names
    CC_KEY_ALIASES.each do |alias_key|
      if @json.key?(alias_key) && !@json.key?(CORRECT_CC_KEY)
        @json[CORRECT_CC_KEY] = @json.delete(alias_key)
        changed = true
      end
    end

    # Ensure receives exists (even if empty)
    unless @json.key?("receives")
      @json["receives"] = []
      changed = true
    end

    # Ensure transmits exists (even if empty)
    unless @json.key?("transmits")
      @json["transmits"] = []
      changed = true
    end

    # Fix message types in receives and transmits
    %w[receives transmits].each do |field|
      values = @json[field]
      next unless values.is_a?(Array)

      new_values = []
      values.each do |v|
        if REMOVE_MESSAGE_TYPES.include?(v)
          # Skip - remove this value
          changed = true
        elsif MESSAGE_TYPE_REPLACEMENTS.key?(v)
          # Replace with correct value
          new_values << MESSAGE_TYPE_REPLACEMENTS[v]
          changed = true
        else
          new_values << v
        end
      end

      # Deduplicate (e.g., NOTE_ON and NOTE_OFF both become NOTE_NUMBER)
      new_values.uniq!
      @json[field] = new_values
    end

    if changed
      # Reorder keys for consistency
      ordered = reorder_keys(@json)
      json_str = JSON.pretty_generate(ordered, indent: "  ")
      json_str = json_str.gsub(/\r\n/, "\n")
      # Write without BOM, UTF-8
      File.write(@path, json_str + "\n", encoding: "utf-8")
      @fixed = true
    end

    changed
  end

  private

  # Scan for // line comments and /* */ block comments while tracking string
  # context, so // inside a JSON string value is not flagged. Returns the list
  # of 1-based line numbers where comments begin.
  def detect_json_comments(content)
    lines = []
    in_string = false
    in_block = false
    block_start_line = nil
    line = 1
    i = 0
    len = content.length
    while i < len
      c = content[i]
      nxt = content[i + 1]
      if c == "\n"
        line += 1
        i += 1
        next
      end
      if in_block
        if c == "*" && nxt == "/"
          in_block = false
          i += 2
          next
        end
        i += 1
        next
      end
      if in_string
        if c == "\\" && nxt
          i += 2
          next
        end
        in_string = false if c == '"'
        i += 1
        next
      end
      if c == '"'
        in_string = true
        i += 1
        next
      end
      if c == "/" && nxt == "/"
        lines << line
        # Skip to end of line to avoid double-counting
        nl = content.index("\n", i)
        break unless nl
        i = nl
        next
      end
      if c == "/" && nxt == "*"
        lines << line
        in_block = true
        block_start_line = line
        i += 2
        next
      end
      i += 1
    end
    lines << block_start_line if in_block && block_start_line && !lines.include?(block_start_line)
    lines.uniq
  end

  def validate_required_fields
    REQUIRED_FIELDS.each do |field|
      unless @json.key?(field)
        @errors << "Missing required field: #{field}"
      end
    end
  end

  def validate_metadata
    version = @json["schemaVersion"]
    if version && version != EXPECTED_SCHEMA_VERSION
      @errors << "schemaVersion is '#{version}', expected '#{EXPECTED_SCHEMA_VERSION}'"
    end
  end

  def validate_device_object
    device = @json["device"]
    unless device
      @errors << "Missing required field: device"
      return
    end

    unless device.is_a?(Hash)
      @errors << "device must be an object"
      return
    end

    REQUIRED_DEVICE_FIELDS.each do |field|
      unless device.key?(field)
        @errors << "device: missing required field '#{field}'"
      end
    end
  end

  def validate_cc_key_name
    CC_KEY_ALIASES.each do |alias_key|
      if @json.key?(alias_key)
        @errors << "Invalid key '#{alias_key}' should be '#{CORRECT_CC_KEY}'"
      end
    end
  end

  def validate_cc_entries
    cc_entries = @json[CORRECT_CC_KEY] || @json["controls"] || @json["controlChangeMessages"] || []
    return if cc_entries.empty?

    # All defined CC numbers, used to validate x_variants gating references.
    defined_cc_numbers = cc_entries.filter_map { |e| e["controlChangeNumber"] if e.is_a?(Hash) }
    seen_cc_numbers = {}

    cc_entries.each_with_index do |entry, idx|
      unless entry.is_a?(Hash)
        @errors << "CC entry #{idx}: not an object"
        next
      end

      unless entry.key?("controlChangeNumber")
        @errors << "CC entry #{idx}: missing controlChangeNumber"
      end

      cc_num = entry["controlChangeNumber"]
      if cc_num && (cc_num < 0 || cc_num > 127)
        @errors << "CC entry #{idx}: controlChangeNumber #{cc_num} out of range (0-127)"
      end

      if cc_num
        if seen_cc_numbers.key?(cc_num)
          @errors << "CC entry #{idx}: duplicate controlChangeNumber #{cc_num} " \
                     "(first defined at entry #{seen_cc_numbers[cc_num]}); use x_variants for mode-dependent behavior"
        else
          seen_cc_numbers[cc_num] = idx
        end
      end

      unless entry.key?("name")
        @warnings << "CC entry #{idx} (CC#{cc_num}): missing name"
      end

      if entry.key?("valueRange")
        validate_value_range(entry["valueRange"], idx, cc_num)
      end

      validate_cc_x_keys(entry, idx, cc_num)
      validate_x_variants(entry["x_variants"], idx, cc_num, defined_cc_numbers) if entry.key?("x_variants")
      validate_x_mandatory(entry["x_mandatory"], idx, cc_num) if entry.key?("x_mandatory")
      validate_x_noop(entry["x_noop"], idx, cc_num) if entry.key?("x_noop")
    end
  end

  # Reject any "x_"-prefixed key on a CC entry that is not whitelisted.
  def validate_cc_x_keys(entry, idx, cc_num)
    entry.each_key do |key|
      next unless key.is_a?(String) && key.start_with?("x_")
      next if ALLOWED_CC_X_KEYS.include?(key)

      @errors << "CC entry #{idx} (CC#{cc_num}): unknown extension key '#{key}' " \
                 "(allowed on CC entries: #{ALLOWED_CC_X_KEYS.join(', ')})"
    end
  end

  def validate_x_variants(variants, idx, cc_num, defined_cc_numbers)
    unless variants.is_a?(Array)
      @errors << "CC entry #{idx} (CC#{cc_num}): x_variants must be an array"
      return
    end

    if variants.empty?
      @errors << "CC entry #{idx} (CC#{cc_num}): x_variants must not be empty"
      return
    end

    variants.each_with_index do |variant, vidx|
      unless variant.is_a?(Hash)
        @errors << "CC entry #{idx} (CC#{cc_num}): x_variants[#{vidx}] must be an object"
        next
      end

      constraint = variant["constraint"]
      if constraint.nil?
        @errors << "CC entry #{idx} (CC#{cc_num}): x_variants[#{vidx}] missing constraint"
      else
        validate_variant_constraint(constraint, idx, cc_num, vidx, defined_cc_numbers)
      end

      name = variant["name"]
      if name && name.length > MAX_NAME_LENGTH
        @errors << "CC entry #{idx} (CC#{cc_num}): x_variants[#{vidx}] name '#{name}' " \
                   "exceeds #{MAX_NAME_LENGTH} characters"
      end

      if variant.key?("valueRange")
        validate_value_range(variant["valueRange"], idx, cc_num)
        validate_discrete_bounds(variant["valueRange"], idx, cc_num, vidx)
      end

      noop = variant["x_noop"]
      if !noop.nil? && noop != true && noop != false
        @errors << "CC entry #{idx} (CC#{cc_num}): x_variants[#{vidx}] x_noop must be a boolean"
      end

      variant.each_key do |key|
        next if %w[constraint name additionalInfo valueRange x_noop].include?(key)
        @errors << "CC entry #{idx} (CC#{cc_num}): x_variants[#{vidx}] has unknown key '#{key}'"
      end
    end
  end

  def validate_variant_constraint(constraint, idx, cc_num, vidx, defined_cc_numbers)
    unless constraint.is_a?(Hash)
      @errors << "CC entry #{idx} (CC#{cc_num}): x_variants[#{vidx}] constraint must be an object"
      return
    end

    gating_cc = constraint["cc"]
    op = constraint["op"]
    value = constraint["value"]

    if gating_cc.nil? || !gating_cc.is_a?(Integer) || gating_cc < 0 || gating_cc > 127
      @errors << "CC entry #{idx} (CC#{cc_num}): x_variants[#{vidx}] constraint.cc must be an integer 0-127"
    elsif !defined_cc_numbers.include?(gating_cc)
      @errors << "CC entry #{idx} (CC#{cc_num}): x_variants[#{vidx}] constraint.cc #{gating_cc} " \
                 "is not a defined controlChangeNumber"
    end

    unless VALID_VARIANT_OPS.include?(op)
      @errors << "CC entry #{idx} (CC#{cc_num}): x_variants[#{vidx}] constraint.op '#{op}' " \
                 "must be one of: #{VALID_VARIANT_OPS.join(', ')}"
    end

    if value.nil? || !value.is_a?(Integer) || value < 0 || value > 127
      @errors << "CC entry #{idx} (CC#{cc_num}): x_variants[#{vidx}] constraint.value must be an integer 0-127"
    end
  end

  # Ensure every discreteValues entry falls within the variant's min/max.
  def validate_discrete_bounds(range, idx, cc_num, vidx)
    return unless range.is_a?(Hash)
    dvs = range["discreteValues"]
    return unless dvs.is_a?(Array)

    min = range["min"]
    max = range["max"]
    return unless min.is_a?(Integer) && max.is_a?(Integer)

    dvs.each do |dv|
      next unless dv.is_a?(Hash) && dv["value"].is_a?(Integer)
      v = dv["value"]
      if v < min || v > max
        @errors << "CC entry #{idx} (CC#{cc_num}): x_variants[#{vidx}] discreteValue #{v} " \
                   "outside range #{min}-#{max}"
      end
    end
  end

  def validate_x_mandatory(value, idx, cc_num)
    unless value == true || value == false
      @errors << "CC entry #{idx} (CC#{cc_num}): x_mandatory must be a boolean"
    end
  end

  def validate_x_noop(value, idx, cc_num)
    unless value == true || value == false
      @errors << "CC entry #{idx} (CC#{cc_num}): x_noop must be a boolean"
    end
  end

  # Reject any top-level "x_"-prefixed key that is not whitelisted.
  def validate_top_level_x_keys
    @json.each_key do |key|
      next unless key.is_a?(String) && key.start_with?("x_")
      next if ALLOWED_TOP_LEVEL_X_KEYS.include?(key)

      @errors << "Unknown top-level extension key '#{key}' " \
                 "(allowed: #{ALLOWED_TOP_LEVEL_X_KEYS.join(', ')})"
    end
  end

  def validate_value_range(range, idx, cc_num)
    return unless range.is_a?(Hash)

    if range.key?("min") && range.key?("max")
      min = range["min"]
      max = range["max"]
      if min > max
        @errors << "CC entry #{idx} (CC#{cc_num}): min (#{min}) > max (#{max})"
      end
    end

    if range.key?("discreteValues")
      dvs = range["discreteValues"]
      unless dvs.is_a?(Array)
        @errors << "CC entry #{idx} (CC#{cc_num}): discreteValues must be an array"
      end
    end
  end

  def validate_x_pc
    x_pc = @json["x_pc"]
    return unless x_pc

    unless x_pc.is_a?(Hash)
      @errors << "x_pc must be an object"
      return
    end

    unless x_pc.key?("indexBase")
      @warnings << "x_pc: missing indexBase (should be 0 or 1)"
    end

    unless x_pc.key?("count")
      @warnings << "x_pc: missing count"
    end

    if x_pc.key?("bankSelectMode")
      unless VALID_BANK_SELECT_MODES.include?(x_pc["bankSelectMode"])
        @errors << "x_pc: invalid bankSelectMode value '#{x_pc["bankSelectMode"]}' " \
                   "(must be one of: #{VALID_BANK_SELECT_MODES.join(', ')})"
      end
    end
  end

  def validate_x_midi_trs
    trs = @json["x_midiTrs"]
    return unless trs

    unless VALID_TRS_TYPES.include?(trs)
      @errors << "x_midiTrs: invalid value '#{trs}' (must be one of: #{VALID_TRS_TYPES.join(', ')})"
    end
  end

  def validate_receives_transmits_values
    %w[receives transmits].each do |field|
      values = @json[field]
      next unless values.is_a?(Array)

      values.each do |v|
        if REMOVE_MESSAGE_TYPES.include?(v)
          @errors << "#{field}: '#{v}' should be removed"
        elsif MESSAGE_TYPE_REPLACEMENTS.key?(v)
          @errors << "#{field}: '#{v}' should be '#{MESSAGE_TYPE_REPLACEMENTS[v]}'"
        elsif !VALID_MESSAGE_TYPES.include?(v)
          @errors << "#{field}: invalid message type '#{v}'"
        end
      end
    end
  end

  def reorder_keys(hash)
    # Preferred key order for readability
    order = %w[
      $schema schemaVersion implementationVersion
      title displayName
      device
      receives transmits
      controlChangeCommands nrpnCommands
      x_pc x_midiTrs x_midiChannel
    ]

    ordered = {}
    order.each do |key|
      ordered[key] = hash[key] if hash.key?(key)
    end
    hash.each do |key, value|
      ordered[key] = value unless ordered.key?(key)
    end
    ordered
  end
end

# Main execution
files = Dir.glob(devices_dir.join("**/*.json").to_s).sort
total_errors = 0
total_warnings = 0
fixed_count = 0

files.each do |fp|
  rel = Pathname.new(fp).relative_path_from(root).to_s
  validator = DeviceValidator.new(fp)

  valid = validator.validate

  if options[:fix] && !valid
    if validator.fix!
      fixed_count += 1
      puts "FIXED: #{rel}"
      # Re-validate after fix
      validator = DeviceValidator.new(fp)
      valid = validator.validate
    end
  end

  unless valid
    puts "ERROR: #{rel}"
    validator.errors.each { |e| puts "  - #{e}" }
    total_errors += validator.errors.size
  end

  if validator.warnings.any?
    puts "WARN: #{rel}" if valid
    validator.warnings.each { |w| puts "  - #{w}" }
    total_warnings += validator.warnings.size
  end
end

puts
puts "=" * 60
puts "Validated #{files.size} device files"
puts "  Errors:   #{total_errors}"
puts "  Warnings: #{total_warnings}"
puts "  Fixed:    #{fixed_count}" if options[:fix]
puts

if total_errors > 0
  exit 1
else
  puts "All files passed validation."
  exit 0
end
