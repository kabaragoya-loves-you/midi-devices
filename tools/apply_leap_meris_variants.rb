#!/usr/bin/env ruby
# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Probably not what you're looking for.
#
# The product is the JSON files in devices/ — firmware and the scene editor read
# those directly. This script was a one-off bulk-authoring aid for a handful of
# Leap and Meris X pedals; you do not need to run it to use or build the project.
# Edit the JSON if something is wrong. Only run this if you're deliberately
# regenerating variants from the matrices below (and accept that it overwrites
# hand-edited variant sections on those files).
# ---------------------------------------------------------------------------

# Apply x_variants to Alexander Leap (banded Sound Mode) and Meris X (type-gated param slots).
# Usage: ruby tools/apply_leap_meris_variants.rb [--dry-run]

require "json"
require "optparse"
require "pathname"

options = { dry_run: false }
OptionParser.new do |opts|
  opts.on("--dry-run", "Print summary without writing") { options[:dry_run] = true }
end.parse!

root = Pathname.new(__dir__).join("..").expand_path

def build_banded_variants(gate_cc, band_mins, names)
  base = names[0]
  variants = []
  resolve = lambda do |val|
    variants.each { |v| return v[:name] if val >= v[:threshold] }
    base
  end
  (1...names.length).reverse_each do |i|
    threshold = band_mins[i]
    name = names[i]
    prev = resolve.call(threshold - 1)
    next if name == prev
    variants << { threshold: threshold, name: name }
  end
  variants.sort_by! { |v| -v[:threshold] }
  variants = variants.group_by { |v| v[:name] }.map { |_, group| group.min_by { |x| x[:threshold] } }
  variants.sort_by! { |v| -v[:threshold] }
  variants.reject! { |v| v[:name] == base }
  variants.map do |v|
    {
      "constraint" => { "cc" => gate_cc, "op" => ">=", "value" => v[:threshold] },
      "name" => v[:name]
    }
  end
end

def build_type_variants(gate_cc, type_mins, names_per_type, slot)
  labels = names_per_type.map { |row| row[slot] }
  base_noop = labels[0].nil?
  variants = []
  resolve = lambda do |val|
    variants.each { |v| return v[:name] if val >= v[:threshold] }
    base_noop ? nil : labels[0]
  end
  (1...labels.length).reverse_each do |i|
    threshold = type_mins[i]
    name = labels[i]
    next if name.nil?
    prev = resolve.call(threshold - 1)
    next if name == prev
    variants << { threshold: threshold, name: name }
  end
  variants.sort_by! { |v| -v[:threshold] }
  variants = variants.group_by { |v| v[:name] }.map { |_, group| group.min_by { |x| x[:threshold] } }
  variants.sort_by! { |v| -v[:threshold] }
  variants.reject! { |v| labels[0] && v[:name] == labels[0] }
  json_variants = variants.map do |v|
    {
      "constraint" => { "cc" => gate_cc, "op" => ">=", "value" => v[:threshold] },
      "name" => v[:name]
    }
  end
  [labels[0], base_noop, json_variants]
end

def patch_cc!(device, cc_num, name:, variants: nil, mandatory: false, noop: false)
  entry = device["controlChangeCommands"].find { |c| c["controlChangeNumber"] == cc_num }
  raise "CC#{cc_num} missing in #{device['displayName']}" unless entry
  entry["name"] = name
  entry.delete("additionalInfo") if entry["additionalInfo"]&.include?("depends on")
  if variants && !variants.empty?
    entry["x_variants"] = variants
  else
    entry.delete("x_variants")
  end
  if mandatory
    entry["x_mandatory"] = true
  else
    entry.delete("x_mandatory")
  end
  if noop
    entry["x_noop"] = true
  else
    entry.delete("x_noop")
  end
  entry
end

def apply_leap!(device, band_mins, mode_labels, knob_matrix, gate_cc: 53)
  band_mins.each_with_index do |min, i|
    mode_labels[i]
  end
  discrete = band_mins.each_with_index.map do |min, i|
    mid = i < band_mins.length - 1 ? (min + band_mins[i + 1] - 1) / 2 : (min + 127) / 2
    { "value" => mid, "name" => mode_labels[i] }
  end
  gate = device["controlChangeCommands"].find { |c| c["controlChangeNumber"] == gate_cc }
  gate["x_mandatory"] = true
  gate["valueRange"] = { "min" => 0, "max" => 127, "discreteValues" => discrete }
  gate.delete("additionalInfo")
  knob_matrix.each do |cc, names|
    variants = build_banded_variants(gate_cc, band_mins, names)
    patch_cc!(device, cc, name: names[0], variants: variants)
  end
end

# --- Alexander Leap matrices (PG1: 50-52, PG2: 54-57, PG3: 58) ---

LUMINOUS_BANDS = [0, 13, 26, 38, 51, 64, 76, 89, 102, 114]
LUMINOUS_MODES = %w[CLASSIC DUAL\ PHZ PHAZDLAY K-TREM DYNAMIC INFINITE FLYINGPAN PATTERN UNIQUE PHLANGER]
LUMINOUS_KNOBS = {
  50 => %w[RATE RAT1 TIME RATE RATE RATE RATE RATE RATE RATE],
  51 => %w[DEPT DEP1 REPT VIB DEPT DEPT DEPT STEP DEPT DEPT],
  52 => %w[MIX MIX MIX TREM MIX MIX MIX MIX MIX MIX],
  54 => %w[STAG RAT2 RATE STAG SENS DIR PRAT STAG STAG TIME],
  55 => %w[RESO DEP2 DEPT IMAG RISE RESO PDEP RESO RESO RESO],
  56 => %w[WAVE WAVE WAVE WAVE SOFT WAVE PWAV PATT BEAT WAVE],
  57 => %w[CENT ROUT CENT SYNC LOUD CENT PAN DIR SYNC CENT],
  58 => %w[DIV DIV DIV DIV MODE DIV DIV DIV DIV DIV]
}

SPACE_BANDS = [0, 16, 31, 46, 61, 76, 91, 106]
SPACE_MODES = %w[PLATE MOD\ HALL PITCH SPRING LO-FI ANALOG DYNAMIC ECHOVERB]
SPACE_KNOBS = {
  50 => %w[SIZE SIZE SIZE PING SIZE TIME SIZE REVB],
  51 => %w[DAMP TONE TONE TONE DIRT REPT DAMP TONE],
  52 => %w[MIX MIX MIX MIX MIX MIX MIX MIX],
  54 => %w[PRE LOW UP TANK PRE TONE PRE DTIM],
  55 => %w[RATE RATE DOWN RATE RATE RATE TIME REPT],
  56 => %w[WAVE WAVE P.UP WAVE WAVE WAVE ATTK DMIX],
  57 => %w[DEPTH P.DN DEPTH DEPTH DEPTH DEPTH RELS D.EQ],
  58 => %w[DIV DIV DIV DIV DIV DIV TYPE DIV]
}

REWIND_BANDS = [0, 13, 26, 38, 51, 64, 76, 89, 102, 114]
REWIND_MODES = %w[TAPE ANALOG DIGITAL PITCH DUAL DIFFUSE REVERSE DYNAMIC FILTER LO-FI]
REWIND_KNOBS = {
  50 => %w[TIME TIME TIME TIME TIM1 TIME TIME TIME TIME TIME],
  51 => %w[REPT REPT REPT REPT REP1 REPT REPT REPT REPT REPT],
  52 => %w[MIX MIX MIX MIX MIX1 MIX MIX MIX MIX MIX],
  54 => %w[WOW TONE BITS MODE TIM2 BITS BITS MODE RESO DIRT],
  55 => %w[FLUT RATE RATE Tune REP2 SOFT DIR RISE Rate/Lag RATE],
  56 => %w[AGE WAVE WAVE PMIX MIX2 HIGH TONE ATTK MOD TONE],
  57 => %w[HEAD DEPTH DEPTH Fine/Patt TYPE LOW CLIK RELS Dept/Sens DEPT],
  58 => %w[DIV DIV DIV DIV DIV DIV DIV DIV DIV DIV]
}

DYNA_BANDS = [0, 13, 26, 38, 51, 64, 76, 89, 102, 114]
DYNA_MODES = %w[AUTO DYNA DUAL\ AUTO DUAL\ DYNA SPIRAL STEP ECHO FLERB FILTER TURBO]
DYNA_KNOBS = {
  50 => %w[RATE SOFT RAT1 UP RATE RATE TIME SIZE RATE RATE],
  51 => %w[DEPT LOUD DEP1 DOWN DEPT DEPT REPT TONE DEPT DEPT],
  52 => %w[RESO SENS RES1 SENS RESO RESO MIX MIX RESO RESO],
  54 => %w[MANU FALL RAT2 FALL DLAY STEP RATE SPD TREM],
  55 => %w[MIX MIX DEP2 MIX MIX PATT DEPT DEPT FREQ DEPT],
  56 => %w[WAVE RESO RES2 RESO DIR PATT RESO RESO PEAK WAVE],
  57 => %w[ZERO FILT ROUT ROUT ZERO DIR ROUT FMIX MIX MIX],
  58 => %w[DIV DIV DIV DIV DIV DIV DIV DIV DIV DIV]
}

# --- Meris type-gated param tables (rows = type index 0 Off, cols = param slot 0..5) ---

LVX_PREAMP_MINS = [0, 19, 37, 55, 74, 92, 110]
LVX_PREAMP = [
  [nil, nil, nil, nil, nil, nil],
  ["Level", "Balance", nil, nil, nil, nil],
  ["Gain", "Level", nil, nil, nil, nil],
  ["Gain", "Level", nil, nil, nil, nil],
  ["Gain", "Level", nil, nil, nil, nil],
  ["Gain", "Bass", "Treble", "Level", nil, nil],
  ["Smpl Rate", "Bit Depth", "Level", nil, nil, nil]
]

LVX_DYN_MINS = [0, 26, 52, 77, 103]
LVX_DYN = [
  [nil, nil, nil, nil, nil, nil],
  %w[Threshold Ratio Gain Attack Release Mix],
  ["Attack", "Gain", nil, nil, nil, nil],
  ["Density", "LPF", nil, nil, nil, nil],
  %w[Threshold Gain Release nil nil nil]
]

LVX_PITCH_MINS = [0, 22, 43, 64, 86, 107]
LVX_PITCH = [
  [nil, nil, nil, nil, nil, nil],
  ["Pitch", "Mix", nil, nil, nil, nil],
  %w[Pitch L Pitch R Key Scale Glide],
  ["Pitch L", "Pitch R", "Mix", nil, nil, nil],
  ["Pitch L", "Pitch R", "Glide", "Mix", nil, nil],
  ["Pitch L", "Pitch R", "Mix", nil, nil, nil]
]

LVX_FILTER_MINS = [0, 26, 52, 77, 103]
LVX_FILTER = [
  [nil, nil, nil, nil, nil, nil],
  %w[Frequency Resonance Topology Spread nil nil],
  %w[Frequency Resonance Topology Spread nil nil],
  ["Depth", "Resonance", "Level", "Spread", nil, nil],
  %w[Frequency Resonance Topology Gain nil nil]
]

LVX_MOD_MINS = [0, 16, 32, 48, 64, 80, 96, 112]
LVX_MOD = [
  [nil, nil, nil, nil, nil, nil],
  %w[Speed Depth Mix nil nil nil],
  %w[Speed Depth Feedback Mix nil nil],
  ["Attack", "Depth", "Feedback", "Direction", "Mix", nil],
  %w[Slip Crinkle Static Highs Lows Mix],
  %w[Speed Feedback Direction nil nil nil],
  %w[Size Repeats Spread Direction nil nil],
  %w[Frequency Waveshape Mix nil nil nil]
]

MERCURY_PREAMP_MINS = [0, 26, 52, 77, 103]
MERCURY_PREAMP = [
  [nil, nil, nil, nil, nil, nil],
  ["Level", "Balance", nil, nil, nil, nil],
  ["Gain", nil, "Level", nil, nil, nil],
  ["Gain", nil, "Level", nil, nil, nil],
  ["Gain", nil, "Level", nil, nil, nil]
]

def apply_mercury_preamp!(device)
  mins = MERCURY_PREAMP_MINS
  table = MERCURY_PREAMP
  mapping = { 7 => 0, 8 => 1, 11 => 2 }
  mapping.each do |cc, slot|
    base, noop, variants = build_type_variants(5, mins, table, slot)
    patch_cc!(device, cc, name: base || "Preamp Param", variants: variants, noop: noop)
  end
  device["controlChangeCommands"].find { |c| c["controlChangeNumber"] == 5 }["x_mandatory"] = true
end

def apply_meris_category!(device, gate_cc, type_mins, table, cc_start, label_prefix, mandatory_gate: true, cc_map: nil)
  gate = device["controlChangeCommands"].find { |c| c["controlChangeNumber"] == gate_cc }
  gate["x_mandatory"] = true if mandatory_gate
  slots = cc_map || table[0].length.times.map { |slot| [cc_start + slot, slot] }
  slots.each do |cc, slot|
    next unless device["controlChangeCommands"].any? { |c| c["controlChangeNumber"] == cc }
    base_name, base_noop, variants = build_type_variants(gate_cc, type_mins, table, slot)
    default_name = base_name || "#{label_prefix} #{slot + 1}"
    patch_cc!(device, cc, name: default_name, variants: variants, noop: base_noop)
  end
end

def apply_enzo_drive!(device)
  mins = [0, 19, 37, 55, 74, 92, 110]
  table = LVX_PREAMP
  { 7 => 0, 8 => 1, 9 => 2 }.each do |cc, slot|
    base, noop, variants = build_type_variants(5, mins, table, slot)
    names = %w[Gain Vol/Smpl Balance/Bits Drv Level]
    patch_cc!(device, cc, name: base || names[slot], variants: variants, noop: noop)
  end
  device["controlChangeCommands"].find { |c| c["controlChangeNumber"] == 5 }["x_mandatory"] = true
end

def apply_enzo_ambience!(device)
  mins = [0, 26, 52, 77, 103]
  # Echo: Fdbk; Small/Med/Large: Decay on param slot matching CC11
  table = [
    [nil, nil, nil, nil, nil, nil],
    ["Feedback", nil, nil, nil, nil, nil],
    ["Decay", nil, nil, nil, nil, nil],
    ["Decay", nil, nil, nil, nil, nil],
    ["Decay", nil, nil, nil, nil, nil]
  ]
  base, noop, variants = build_type_variants(10, mins, table, 0)
  patch_cc!(device, 11, name: "Fdbk/Decay", variants: variants, noop: noop)
  device["controlChangeCommands"].find { |c| c["controlChangeNumber"] == 10 }["x_mandatory"] = true
end

def apply_enzo_mod!(device)
  mins = [0, 22, 43, 64, 86, 107]
  table = [
    [nil, nil, nil, nil, nil, nil],
    ["Speed", "Depth", "Mix", nil, nil, nil],
    ["Speed", "Depth", "Feedback", "Mix", nil, nil],
    ["Speed", "Depth", "Mix", nil, nil, nil],
    ["Speed", "Depth", "Stages", "Mix", nil, nil],
    ["Frequency", "Mix", nil, nil, nil, nil]
  ]
  slots = { 88 => 0, 89 => 1, 90 => 2, 91 => 3 }
  labels = %w[Mod Speed Mod Depth Mod Wave Mod Fdbk]
  slots.each do |cc, slot|
    _base, noop, variants = build_type_variants(86, mins, table, slot)
    patch_cc!(device, cc, name: labels[slot], variants: variants, noop: noop)
  end
  device["controlChangeCommands"].find { |c| c["controlChangeNumber"] == 86 }["x_mandatory"] = true
end

def apply_ottobit_preamp!(device)
  mins = [0, 26, 52, 77, 103]
  table = [
    [nil, nil, nil, nil, nil, nil],
    ["Level", "Balance", nil, nil, nil, nil],
    ["Gain", "Level", nil, nil, nil, nil],
    ["Gain", "Dust", "Level", nil, nil, nil],
    ["Gain", "Wave", "Level", nil, nil, nil]
  ]
  apply_meris_category!(device, 5, mins, table, 7, "Preamp")
end

def apply_ottobit_mod!(device)
  mins = [0, 22, 43, 64, 86, 107]
  table = [
    [nil, nil, nil, nil, nil, nil],
    ["Frequency", "Depth", "Shape", "Blend", "Mix", nil],
    ["Speed", "Depth", "Shape", "Bias", "Mix", nil],
    ["Speed", "Width", "Mode", "Bias", "Mix", nil],
    ["Freq", "Depth", "Shape", "Bias", "Track", nil],
    ["Speed", "Depth", "Shape", "Bias", "Mix", nil]
  ]
  (0..4).each do |slot|
    cc = 32 + slot
    _base, noop, variants = build_type_variants(30, mins, table, slot)
    names = %w[Mod Speed Mod Depth Mod Shape Mod Blend Mod Mix]
    patch_cc!(device, cc, name: names[slot], variants: variants, noop: noop)
  end
  device["controlChangeCommands"].find { |c| c["controlChangeNumber"] == 30 }["x_mandatory"] = true
end

leap_files = {
  "alexander_pedals/luminous.json" => [LUMINOUS_BANDS, LUMINOUS_MODES, LUMINOUS_KNOBS],
  "alexander_pedals/space_force.json" => [SPACE_BANDS, SPACE_MODES, SPACE_KNOBS],
  "alexander_pedals/rewind.json" => [REWIND_BANDS, REWIND_MODES, REWIND_KNOBS],
  "alexander_pedals/dynaflanger_213.json" => [DYNA_BANDS, DYNA_MODES, DYNA_KNOBS]
}

meris_handlers = {
  "meris/lvx.json" => lambda do |d|
    apply_meris_category!(d, 5, LVX_PREAMP_MINS, LVX_PREAMP, 7, "Preamp")
    apply_meris_category!(d, 62, LVX_DYN_MINS, LVX_DYN, 64, "Dyn")
    apply_meris_category!(d, 70, LVX_PITCH_MINS, LVX_PITCH, 72, "Pitch")
    apply_meris_category!(d, 78, LVX_FILTER_MINS, LVX_FILTER, 80, "Filter")
    apply_meris_category!(d, 86, LVX_MOD_MINS, LVX_MOD, 88, "Mod")
  end,
  "meris/mercury_x.json" => lambda do |d|
    apply_mercury_preamp!(d)
    apply_meris_category!(d, 62, LVX_DYN_MINS, LVX_DYN, 64, "Dyn")
    apply_meris_category!(d, 70, LVX_PITCH_MINS, LVX_PITCH, 72, "Pitch")
    apply_meris_category!(d, 78, LVX_FILTER_MINS, LVX_FILTER, 80, "Filter")
    apply_meris_category!(d, 86, LVX_MOD_MINS, LVX_MOD, 88, "Mod")
  end,
  "meris/enzo_x.json" => lambda do |d|
    apply_enzo_drive!(d)
    apply_enzo_ambience!(d)
    apply_enzo_mod!(d)
  end,
  "meris/ottobit_x.json" => lambda do |d|
    apply_ottobit_preamp!(d)
    apply_ottobit_mod!(d)
  end
}

changed = 0
leap_files.each do |rel, (bands, modes, knobs)|
  path = root.join("devices", rel)
  device = JSON.parse(path.read)
  apply_leap!(device, bands, modes, knobs)
  unless options[:dry_run]
    path.write(JSON.pretty_generate(device) + "\n")
  end
  changed += 1
  puts "Leap: #{rel} (#{knobs.values.sum { |v| build_banded_variants(53, bands, v).length }} variant entries)"
end

meris_handlers.each do |rel, handler|
  path = root.join("devices", rel)
  device = JSON.parse(path.read)
  handler.call(device)
  unless options[:dry_run]
    path.write(JSON.pretty_generate(device) + "\n")
  end
  changed += 1
  puts "Meris: #{rel}"
end

puts options[:dry_run] ? "Dry run: #{changed} files" : "Updated #{changed} files"
