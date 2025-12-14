#!/usr/bin/env ruby
# frozen_string_literal: true

# Validate device JSON files for schema compliance
# Usage:
#   ruby tools/validate_devices.rb [--root PATH] [--fix]
#
# Validates:
#   - Required fields: receives, transmits
#   - Correct key names (controlChangeCommands, not "controls" or "controlChangeMessages")
#   - Valid CC entry structure
#   - x_pc custom extension format

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
REQUIRED_FIELDS = %w[receives transmits].freeze

# Valid values for receives/transmits
VALID_MESSAGE_TYPES = %w[
  PROGRAM_CHANGE
  CONTROL_CHANGE
  CLOCK
  NOTE_ON
  NOTE_OFF
  PITCH_BEND
  AFTERTOUCH
  CHANNEL_PRESSURE
  SYSEX
].freeze

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
      @json = JSON.parse(File.read(@path))
    rescue JSON::ParserError => e
      @errors << "Invalid JSON: #{e.message}"
      return false
    end

    validate_required_fields
    validate_cc_key_name
    validate_cc_entries
    validate_x_pc
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

    if changed
      # Reorder keys for consistency
      ordered = reorder_keys(@json)
      json_str = JSON.pretty_generate(ordered, indent: "  ")
      json_str = json_str.gsub(/\r\n/, "\n")
      File.write(@path, json_str + "\n")
      @fixed = true
    end

    changed
  end

  private

  def validate_required_fields
    REQUIRED_FIELDS.each do |field|
      unless @json.key?(field)
        @errors << "Missing required field: #{field}"
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

      unless entry.key?("name")
        @warnings << "CC entry #{idx} (CC#{cc_num}): missing name"
      end

      if entry.key?("valueRange")
        validate_value_range(entry["valueRange"], idx, cc_num)
      end
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

    if x_pc.key?("bankSelect")
      valid_bank = %w[none cc0 cc32 cc0+cc32].include?(x_pc["bankSelect"])
      unless valid_bank
        @errors << "x_pc: invalid bankSelect value '#{x_pc["bankSelect"]}'"
      end
    end
  end

  def validate_receives_transmits_values
    %w[receives transmits].each do |field|
      values = @json[field]
      next unless values.is_a?(Array)

      values.each do |v|
        unless VALID_MESSAGE_TYPES.include?(v)
          @warnings << "#{field}: unknown message type '#{v}'"
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
      x_programChangeMessages x_pc x_midiTrs x_midiChannel
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
