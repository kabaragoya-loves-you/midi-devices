#!/usr/bin/env ruby
# frozen_string_literal: true

# Best-effort shorten controlChangeCommands[].name to <=14 chars.
# Usage: ruby tools/shorten_cc_names.rb [--dry-run]

require "json"
require "optparse"
require "pathname"

MAX = 14
options = { dry_run: false }
OptionParser.new do |opts|
  opts.on("--dry-run", "Report changes without writing") { options[:dry_run] = true }
end.parse!

root = Pathname.new(__dir__).join("..").expand_path
devices_dir = root.join("devices")

# Longest-first prefix / phrase replacements (case-sensitive).
PHRASES = [
  ["Switch between Compression or Saturation", "Comp/Sat Sw"],
  ["Bypass Switch (Explicit Channel Routing)", "Bypass Ch Rt"],
  ["Karplus Strong Decay Time Compensation", "KS Dec Comp"],
  ["Bypass Switch (Last Saved Channels)", "Bypass Last Ch"],
  ["Bypass Switch (Dark/World Channels)", "Bypass DW Ch"],
  ["Preview / Save-Load Toggle Select", "Prev/Save Sel"],
  ["Looper - Full/Half Speed (toggle)", "Loop 1/2 Speed"],
  ["Ramp Trigger (Press and Release)", "Ramp Trig P+R"],
  ["Modulation Depth / Multi Pattern", "Mod Depth/Pat"],
  ["Looper - Undo (to initial loop)", "Loop Undo Init"],
  ["Infinite Hold (w/o Oscillation)", "Inf Hold w/o Osc"],
  ["Infinite Hold (w/ Oscillation)", "Inf Hold w/ Osc"],
  ["Randomize Robots & Tape Machine", "Rnd Robots/Tape"],
  ["Envelope / Time Stretch (right)", "Env/Stretch R"],
  ["PARA / A >> B / B >> A Select", "Para A>>B Sel"],
  ["Extra Tap (Press and Release)", "Extra Tap P+R"],
  ["Alt Mode (Both Switches Hold)", "Alt Both Hold"],
  ["Mod Mode / Waveshape / Stages", "Mod/Wave/Stage"],
  ["MIDI Patch Bank (Bank Select)", "Patch Bank Sel"],
  ["Cycle Distortion Gain Stages", "Cyc Dist Stages"],
  ["Reset Black + White Controls", "Reset B+W Ctrl"],
  ["Secondary Drive/Boost On/Off", "2nd Drv/Bst"],
  ["Bypass Switch (Drive Routing)", "Bypass Drv Rt"],
  ["Tap Switch Tap/Speed", "Tap Tgl T/S"],
  ["MIDI Clock Off/On", "MIDI Clk Off/On"],
  ["Expression Off/On", "Expr Off/On"],
  ["Expression Pedal", "Expr Pedal"],
  ["Slow Rotor Speed", "Slow Rot Spd"],
  ["Preamp Drive", "Pre Drive"],
  ["Stereo Spread", "St Sprd"],
  ["Choir Voice", "Choir"],
  ["Mod Speed", "Mod Spd"],
  ["Type Encoder", "Type Enc"],
  ["Ping Pong", "PingPong"],
  ["Bank Select", "Bank Sel"],
  ["Press and Release", "P+R"],
  ["Left Bank - ", "L: "],
  ["Right Bank - ", "R: "],
  ["Left Bank: ", "L: "],
  ["Right Bank: ", "R: "],
  ["Reverb 1: ", "R1: "],
  ["Reverb 2: ", "R2: "],
  ["Voice 1: ", "V1: "],
  ["Voice 2: ", "V2: "],
  ["VINTAGE TREM - ", "V TREM: "],
  ["PATTERN TREM - ", "PAT: "],
  ["QUADRATURE - ", "QUAD: "],
  ["AUTOSWELL - ", "ASW: "],
  ["DESTROYER - ", "DEST: "],
  ["FLANGER - ", "FL: "],
  ["CHORUS - ", "CH: "],
  ["ROTARY - ", "ROT: "],
  ["VIBE - ", "VIBE: "],
  ["PHASER - ", "PH: "],
  ["FILTER - ", "FIL: "],
  ["FORMANT - ", "FORM: "],
  ["NONLINEAR - ", "NL: "],
  ["Looper - ", "Loop: "],
  ["Track 1 ", "Trk1 "],
  ["Track 2 ", "Trk2 "],
  ["Track 3 ", "Trk3 "],
  ["Track 4 ", "Trk4 "],
  ["Track 5 ", "Trk5 "],
  ["Track 6 ", "Trk6 "],
  ["Track 7 ", "Trk7 "],
  ["Track 8 ", "Trk8 "],
  ["MIDI Clock Tempo Mult/Div", "Clk Tempo M/D"],
  ["Rhythm Tempo Fine Adjust", "Rhythm Fine Adj"],
  ["Engine Mode/Neural Setting", "Eng Mode/Neural"],
  ["EXP Out Override Value MSB", "EXP Val MSB"],
  ["EXP Out Override Value LSB", "EXP Val LSB"],
  ["EXP Out Override Value", "EXP Override"],
  ["EXP Out Override Enable", "EXP Ovr En"],
  ["Clear Current Looper Track", "Clr Loop Track"],
  ["Clear All Looper Tracks", "Clr All Loops"],
  ["Synth Hard Sync / Ring Mod", "Sync/Ring Mod"],
  ["Tape Speed Robot Polarity", "Tape Spd Pol"],
  ["Tape Speed Robot Waveform", "Tape Spd Wave"],
  ["Tape Speed Robot Amount", "Tape Spd Amt"],
  ["Series / Parallel / Split", "Ser/Par/Split"],
  ["DIGITAL: Repeat Dynamics", "DIG: Rpt Dyn"],
  ["Comp 1 Pre High Shelf EQ", "C1 Pre Hi EQ"],
  ["Comp 2 Pre High Shelf EQ", "C2 Pre Hi EQ"],
  ["Comp 1 Pre Low Shelf EQ", "C1 Pre Lo EQ"],
  ["Comp 2 Pre Low Shelf EQ", "C2 Pre Lo EQ"],
  ["Comp 1 Sidechain Filter", "C1 Sidechain"],
  ["Comp 2 Sidechain Filter", "C2 Sidechain"],
  ["Oscillator Mod Ramp Time", "Osc Mod Ramp"],
  ["Pitch Correction + Glide", "Pitch Corr/Gld"],
  ["Speed Range/Subdivision", "Spd Rng/Sub"],
  ["Doubletracker Boost/Cut", "DblTrk Bst/Cut"],
  ["Filter Envelope Amount", "Filt Env Amt"],
  ["Auto Mode Phase Offset", "Auto Ph Offset"],
  ["Pedal + Pressure Value", "Pedal+Press"],
  ["Clear Touch Mode Loops", "Clr Touch Loop"],
  ["Gain Cycle Enable/Mode", "Gain Cyc Mode"],
  ["Gain / Vol / Smpl Rate", "Gain/Vol/Smpl"],
  ["Ensemble mp Lvl Adjust", "Ens mp Lvl Adj"],
  ["MIDI Clock Ignore", "Clk Ignore"],
  ["MIDI Clock Enable", "Clk Enable"],
  ["Ignore MIDI Clock", "Ign MIDI Clk"],
  ["Midi Clock Ignore", "Ign MIDI Clk"],
  ["MIDI Clock Listen", "Clk Listen"],
  ["Ignore MIDI Start", "Ign MIDI Strt"],
  ["MIDI Expr Off/On", "MIDI Expr"],
  ["MIDI Clk Off/On", "MIDI Clk"],
  ["Expr Destination", "Expr Dest"],
  ["Pattern 8 Step ", "Pat8 St "],
  ["Sequencer Step ", "Seq St "],
  ["Rec/Play/Dub", "Rec/Play"],
  ["Upper left main", "UL Main"],
  ["Upper right main", "UR Main"],
  ["Upper right alt", "UR Alt"],
  ["Upper left alt", "UL Alt"],
  ["Lower left main", "LL Main"],
  ["Lower right main", "LR Main"],
  ["Lower right alt", "LR Alt"],
  ["Lower left alt", "LL Alt"],
  ["Upper Left Main", "UL Main"],
  ["Upper Right Main", "UR Main"],
  ["Upper Right Alt", "UR Alt"],
  ["Lower Left Main", "LL Main"],
  ["Lower Right Main", "LR Main"],
  ["Lower Right Alt", "LR Alt"],
  ["Footswitch", "Stomp"],
  ["Subdivision", "Subdiv"],
  ["Compression", "Comp"],
  ["Destination", "Dest"],
  ["Structure", "Struct"],
  ["Location", "Loc"],
  ["Character", "Char"],
  ["Increment", "Inc"],
  ["Decrement", "Dec"],
  ["Variation", "Var"],
  ["Calibration", "Cal"],
  ["Dispersion", "Disp"],
  ["Transpose", "Xpose"],
  ["Enable/Mode", "En/Mode"],
  ["Off/On", "On/Off"],
  ["Predelay", "PreDly"],
  ["Pre-Delay", "PreDly"],
  ["Reverb", "Rv"],
  ["Delay", "Dly"],
  ["Looper", "Loop"],
  ["Sequencer", "Seq"],
  ["Dynamics", "Dyn"],
  ["Parameter", "Param"],
  ["Footswitch", "Stomp"],
  ["Attenuverter CV In 1", "Atten CV In 1"],
  ["Attenuverter CV In 2", "Atten CV In 2"],
  ["Attenuverter CV In 3", "Atten CV In 3"],
  ["Attenuverter CV In 4", "Atten CV In 4"],
  ["MIDI Clock Input Mode", "Clk Input Mode"],
  ["Measure Length Adjust", "Meas Len Adj"],
  ["Cycle OD Clipping Mode", "Cyc OD Clip"],
  ["Instrument Input Lvl", "Inst Input Lvl"],
  ["Rotary Fast Rate", "Rotary Fast Rt"],
  ["Rotary Slow Rate", "Rotary Slow Rt"],
  ["Map ENV Filter Cutoff", "Map ENV Filt Cut"],
  ["Map LFO Filter Cutoff", "Map LFO Filt Cut"],
  ["Step Filter Play Mode", "Step Filt Play"],
  ["Flutter Trig & Amount", "Flutter Trig/Amt"],
  ["Trem Engage/Disengage", "Trem Eng/Dis"],
  ["Current Memory Reload", "Curr Mem Reload"],
  ["UnrealPlayer Fidelity", "Unreal Fidelity"],
  ["Loop Output Lvl", "Loop Out Lvl"],
  ["Soundscape Ctrl", "Scape Ctrl"],
  ["Pitchtrack Mode", "Pitchtrack Md"],
  ["Loop FX Param 1", "Loop FX P1"],
  ["Loop FX Param 2", "Loop FX P2"],
  ["Loop FX Param 3", "Loop FX P3"],
  ["Input FX Param 1", "In FX Param 1"],
  ["Input FX Param 2", "In FX Param 2"],
  ["Input FX Param 3", "In FX Param 3"],
  ["MIDI Patch Bank", "Patch Bank"],
  ["Rhythm Fine Adj", "Rhy Fine Adj"],
  ["Dynamic Param 1", "Dyn Param 1"],
  ["Dynamic Param 2", "Dyn Param 2"],
  ["Dynamic Param 3", "Dyn Param 3"],
  ["Dynamic Param 4", "Dyn Param 4"],
  ["Dynamic Param 5", "Dyn Param 5"],
  ["Dynamic Param 6", "Dyn Param 6"],
  ["Filter Envelope", "Filter Env"],
  ["Movement Module", "Move Module"],
  ["Effect Vol Diff", "FX Vol Diff"],
  ["Effect Vol Char", "FX Vol Char"],
  ["Memory/Boost Sw", "Mem/Boost Sw"],
  ["Mod Depth/Width", "Mod Dpth/Width"],
  ["Booster Pre-Lvl", "Boost Pre-Lvl"],
  ["Booster Post-Lvl", "Boost Post-Lvl"],
  ["Direct Save Pres", "Direct Save"],
  ["Stop All + Clear", "Stop+Clear All"],
  ["Retrigger Glitch", "Retrig Glitch"],
  ["Retrigger Freeze", "Retrig Freeze"],
  ["Rhythm Fill Trig", "Rhythm Fill Tr"],
  ["Loop FX Type Sel", "Loop FX Type"],
  ["Input FX Type Sel", "In FX Type Sel"],
  ["Rhythm Start/Stop", "Rhythm Strt/Stop"],
  ["Tempo Half/Double", "Tempo 1/2x/2x"],
  ["Trig Hold Modifier", "Trig Hold Mod"],
  ["Rhythm Pattern Sel", "Rhythm Pat Sel"],
  ["Rv Mix & Placement", "Rv Mix/Place"],
  ["Performance Sw 1", "Perf Sw 1"],
  ["Performance Sw 2", "Perf Sw 2"],
  ["Performance Sw 3", "Perf Sw 3"],
  ["Performance Sw 4", "Perf Sw 4"],
  ["Aux Performance Sw 1", "Aux Perf Sw 1"],
  ["Aux Performance Sw 2", "Aux Perf Sw 2"],
  ["Aux Performance Sw 3", "Aux Perf Sw 3"],
  ["Aux Performance Sw 4", "Aux Perf Sw 4"],
  ["Map ENV Drive / Fold", "Map ENV Drv/Fold"],
  ["Map LFO Drive / Fold", "Map LFO Drv/Fold"],
  ["Treb Band Output Lvl", "Treb Out Lvl"],
  ["Bass Band Output Lvl", "Bass Out Lvl"],
  ["Mid Band Output Lvl", "Mid Out Lvl"],
  ["Gain / Vol Pedal Lvl", "Gain/Vol Ped Lvl"],
  ["Mechanical Noise Lvl", "Mech Noise Lvl"],
  ["Loop Play/Stop Press", "Loop Play/Stop"],
  ["Save to Current Slot", "Save Curr Slot"],
  ["SOS Rec/Splice/Clear", "SOS Rec/Spl/Clr"],
  ["Unspecified Neo Knob", "Neo Knob Unspec"],
  ["Middle Stomp: Scroll", "Mid St: Scroll"],
  ["Pitch Ctrl Smoothing", "Pitch Ctrl Smooth"],
  ["Oscillator Mod Depth", "Osc Mod Depth"],
  ["Currently Seled Pres", "Curr Sel Pres"],
  ["Filter Envelope Type", "Filt Env Type"],
  ["Parallel Path Enable", "Par Path Enable"],
  ["Stomp: ", "St: "],
].freeze

WORD_SUBS = [
  ["Frequency Middle", "Freq Mid"],
  ["Frequency", "Freq"],
  ["Resonance", "Res"],
  ["Waveshape", "Wave"],
  ["Acceleration", "Accel"],
  ["Modulation", "Mod"],
  ["Diffusion", "Diff"],
  ["Sample Rate", "Smpl Rate"],
  ["Sample", "Smpl"],
  ["Direction", "Dir"],
  ["Feedback", "Fdbk"],
  ["Stretch", "Str"],
  ["Spacing", "Space"],
  ["Swell Type", "Swell"],
  ["Headroom", "HeadRm"],
  ["Expression", "Expr"],
  ["Quadrature", "Quad"],
  ["Destroyer", "DEST"],
  ["Flanger", "FL"],
  ["Chorale", "Ch"],
  ["Nonlinear", "NL"],
  ["Magneto", "Mag"],
  ["Impulse", "Imp"],
  ["Shimmer", "Shim"],
  ["Randomize", "Rnd"],
  ["Compensation", "Comp"],
  ["Oscillation", "Osc"],
  ["Infinite", "Inf"],
  ["Preview", "Prev"],
  ["Trigger", "Trig"],
  ["Switch", "Sw"],
  ["Select", "Sel"],
  ["Toggle", "Tgl"],
  ["Routing", "Route"],
  ["Channel", "Ch"],
  ["Encoder", "Enc"],
  ["Controls", "Ctrl"],
  ["Control", "Ctrl"],
  ["Parameter", "Param"],
  ["Settings", "Set"],
  ["Secondary", "2nd"],
  ["Primary", "1st"],
  ["Direction", "Dir"],
  ["Reverse", "Rev"],
  ["Forward", "Fwd"],
  ["Division", "Div"],
  ["Intensity", "Int"],
  ["Sensitivity", "Sens"],
  ["Threshold", "Thresh"],
  ["Sustain", "Sus"],
  ["Release", "Rel"],
  ["Attack", "Atk"],
  ["Decay", "Dec"],
  ["Volume", "Vol"],
  ["Balance", "Bal"],
  ["Panning", "Pan"],
  ["Stereo", "St"],
  ["Spread", "Sprd"],
  ["Manual", "Man"],
  ["Machine", "Mach"],
  ["Rotor", "Rot"],
  ["Level", "Lvl"],
  ["Bypass", "Byp"],
  ["Record", "Rec"],
  ["Playback", "Play"],
  ["Overdub", "Dub"],
  ["Undo", "Undo"],
  ["Preset", "Pres"],
  ["Program", "Prog"],
  ["Algorithm", "Algo"],
  ["Compressor", "Comp"],
  ["Saturation", "Sat"],
  ["Distortion", "Dist"],
  ["Overdrive", "OD"],
  ["Harmonics", "Harm"],
  ["Regeneration", "Regen"],
  ["Regenerate", "Regen"],
  [" (toggle)", ""],
  [" (Toggle)", ""],
  [" (w/o ", " w/o "],
  [" (w/ ", " w/ "],
  [" (right)", " R"],
  [" (left)", " L"],
  [" (Press and Release)", ""],
  [" (Explicit Channel Routing)", ""],
  [" (Last Saved Channels)", ""],
  [" (Dark/World Channels)", ""],
  [" (Drive Routing)", ""],
  [" (Both Switches Hold)", ""],
  [" (to initial loop)", ""],
  [" (Bank Select)", ""],
  [" - ", ": "],
  ["Knob Value", "Knob"],
  ["Robot Rate", "Rob Rt"],
  ["Robot Sync", "Rob Sync"],
  ["Robot Phase", "Rob Ph"],
  ["Robot Shape", "Rob Sh"],
  ["Robot Amount", "Rob Amt"],
  ["Robot St", "Rob St"],
  ["High Shelf", "Hi Shelf"],
  ["Low Shelf", "Lo Shelf"],
  ["High-Pass", "HPF"],
  ["Low-Pass", "LPF"],
  ["Topology", "Topo"],
  ["Typology", "Typo"],
  ["Polarity", "Pol"],
  ["Waveform", "Wave"],
  ["Tempo Mult", "Tempo M"],
  ["Fine Adjust", "Fine Adj"],
  ["Sidechain", "SideCh"],
  ["Subdivision", "Subdiv"],
  ["Destination", "Dest"],
  ["Structure", "Struct"],
  ["Location", "Loc"],
  ["Increment", "Inc"],
  ["Decrement", "Dec"],
  ["Dispersion", "Disp"],
  ["Transpose", "Xpose"],
  ["Footswitch", "Stomp"],
  ["Compression", "Comp"],
  ["Character", "Char"],
  ["Variation", "Var"],
  ["Calibration", "Cal"],
  ["Enable/Mode", "En/Mode"],
  ["Predelay", "PreDly"],
  ["Pre-Delay", "PreDly"],
  ["Performance", "Perf"],
  ["Attenuverter", "Atten"],
  ["Instrument", "Inst"],
  ["Currently", "Curr"],
  ["Selected", "Sel"],
  ["Unspecified", "Unspec"],
  ["Mechanical", "Mech"],
  ["Parallel", "Par"],
  ["Envelope", "Env"],
  ["Oscillator", "Osc"],
  ["Modifier", "Mod"],
  ["Output Lvl", "Out Lvl"],
  ["Band Drive", "Band Drv"],
  ["Band Output", "Band Out"],
  ["Module Byp", "Mod Byp"],
  ["Module Sel", "Mod Sel"],
  ["Robot Wave", "Rob Wave"],
  ["Robot Pol", "Rob Pol"],
  ["Robot Sync", "Rob Sync"],
  ["Fine Adj", "FineAdj"],
  ["Patch Bank", "Patch Bk"],
  ["Soundscape", "Scape"],
  ["Pitchtrack", "PtchTrk"],
  ["Subdiv", "Subdv"],
].freeze

REGEX_RULES = [
  [/\A(R[12]): ([A-Za-z]+): /, '\1 \2: '],           # R1: Hall: X -> R1 Hall: X
  [/\A([A-Z]+): ([A-Za-z ]+): /, '\1 \2: '],         # SHIMMER: Low End -> SHIMMER Low End:
  [/ Off\/On\z/, ""],                                 # drop trailing Off/On when still long
  [/ On\/Off\z/, ""],
  [/\s+/, " "]
].freeze

def shorten_name(name)
  return name if name.length <= MAX

  s = name.dup
  PHRASES.each { |from, to| s = s.gsub(from, to) if s.include?(from) }

  12.times do
    break if s.length <= MAX

    prev = s.dup
    WORD_SUBS.each { |from, to| s = s.gsub(from, to) if s.include?(from) }
    REGEX_RULES.each { |re, rep| s = s.gsub(re, rep) }
    s = s.gsub(/\s+/, " ").strip
    break if s == prev
  end

  # Drop trailing parenthetical fragments
  s = s.sub(/\s*\([^)]+\)\z/, "") while s.length > MAX && s.match?(/\s*\([^)]+\)\z/)

  # Last resort: trim after last colon segment if prefix is informative
  if s.length > MAX && s.include?(": ")
    parts = s.split(": ")
    if parts.length >= 2
      tail = parts.last
      head = parts[0..-2].join(": ")
      if head.length + 2 + tail.length > MAX && tail.length > 6
        s = "#{head}: #{tail[0, MAX - head.length - 2]}"
      end
    end
  end

  s = s.gsub(/\s+/, " ").strip

  s
end

changed_files = 0
changed_names = 0
still_long = 0

Dir.glob(devices_dir.join("**/*.json").to_s).sort.each do |fp|
  rel = Pathname.new(fp).relative_path_from(root).to_s
  j = JSON.parse(File.read(fp, encoding: "bom|utf-8"))
  file_changed = false

  (j["controlChangeCommands"] || []).each do |entry|
    next unless entry.is_a?(Hash) && entry["name"].is_a?(String)

    old = entry["name"]
    next if old.length <= MAX

    new = shorten_name(old)
    still_long += 1 if new.length > MAX
    next if new == old

    puts "#{rel} CC#{entry["controlChangeNumber"]}: #{old.length}->#{new.length} #{old.inspect} => #{new.inspect}"
    entry["name"] = new
    file_changed = true
    changed_names += 1
  end

  next unless file_changed

  changed_files += 1
  next if options[:dry_run]

  json_str = JSON.pretty_generate(j, indent: "  ").gsub(/\r\n/, "\n")
  File.write(fp, json_str + "\n", encoding: "utf-8")
end

puts
puts "Changed #{changed_names} names in #{changed_files} files"
puts "Still over #{MAX} after pass: #{still_long}" unless options[:dry_run]
