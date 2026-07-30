# Storm Summoner MIDI Device Database

A comprehensive database of MIDI-capable effects pedals for the [Storm Summoner](https://kabaragoya.com) MIDI controller.

## Overview

This repository contains device profiles in JSON format that describe the MIDI implementation of various effects pedals. Each profile includes information about supported MIDI messages, control change parameters, and program change behavior.

## Schema

Device profiles conform to `schemaVersion` `"0.1.1"`, based on the [Open MIDI RTC JSON schema](https://github.com/Open-MIDI-RTC/MIDI-RTC-Schema) with several Storm Summoner extensions prefixed with `x_`. The extension schema lives in `web/schemas/storm-summoner-extensions.schema.json`, and the authoritative, step-by-step authoring guide is [`DEVICE_AUTHORING.md`](DEVICE_AUTHORING.md).

Validate any change before committing:

```bash
ruby tools/validate_devices.rb
```

Unknown `x_`-prefixed keys are rejected, so only the extensions below are allowed.

### Top-level extensions

**Program change / presets (`x_pc`)** — always present, even when the device has no presets:

```json
"x_pc": { "indexBase": 0, "count": 128, "bankSelectMode": "none" }
```

- `indexBase` — `0` or `1`, matching how the device numbers its presets.
- `count` — total number of presets (`0` if the device has none).
- `bankSelectMode` — `"none"`, `"CC0"`, or `"CC0_CC32"`, depending on how the device reaches banks beyond 128 presets.

**TRS/TS MIDI wiring (`x_midiTrs`)** — the physical MIDI TRS/TS wiring standard the device expects:

```json
"x_midiTrs": "TYPE_A"
```

- `BOTH` — signal sent on both TRS/RTS polarities (default when unknown)
- `TYPE_A` — signal on tip (Empress, 1010music, Red Panda, etc.)
- `TYPE_B` — signal on ring (Chase Bliss Audio)
- `TYPE_TS` — tip/sleeve (Disaster Area, Source Audio, etc.)

**Default MIDI channel (`x_midiChannel`)** — the device's factory/default MIDI channel (1–16):

```json
"x_midiChannel": 1
```

### Control change parameters

Each `controlChangeCommands` entry describes one CC parameter. The minimal form for a continuous control is:

```json
{ "controlChangeNumber": 14, "name": "Mix", "valueRange": { "min": 0, "max": 127 } }
```

- `name` — display label. Keep to **14 characters or fewer**; the device screen is small. `validate_devices.rb` emits a warning for longer base names, and rejects over-length `x_variants` names outright.
- `valueRange` — `min`/`max` bound the control. Tighten `max` to the highest useful value (a toggle is `"max": 1`, a four-way selector is `"max": 3`); reserve `"max": 127` for genuinely continuous or banded parameters.
- `discreteValues` — optional array of named states inside `valueRange`:
  - **2 or more** entries render a pick-one list/dropdown (modes, shapes, subdivisions).
  - **exactly 1** entry renders a momentary "verb" trigger (tap, reset, record) that fires on any value.
- `additionalInfo` — optional author-only note. It is **never shown** in any UI, so `name` must stand on its own.

### Mode-dependent CCs (`x_variants`, `x_mandatory`, `x_noop`)

Some devices reuse one CC for different functions depending on a *mode* selected by another CC. There is always **exactly one entry per CC number**; mode-specific behavior is expressed with extensions rather than duplicate entries.

**`x_variants`** overrides an entry's `name`, `valueRange`, and/or `additionalInfo` when a constraint on a gating CC matches:

```json
{
  "controlChangeNumber": 102,
  "name": "Bypass",
  "valueRange": {
    "min": 0, "max": 1,
    "discreteValues": [ { "name": "Off", "value": 0 }, { "name": "On", "value": 1 } ]
  },
  "x_variants": [
    {
      "constraint": { "cc": 24, "op": ">=", "value": 3 },
      "name": "Play/Stop",
      "valueRange": {
        "min": 0, "max": 1,
        "discreteValues": [ { "name": "Toggle", "value": 1 } ]
      }
    }
  ]
}
```

- `constraint` is `{ "cc": <gating CC>, "op": <operator>, "value": <int> }`, where `op` is one of `<`, `<=`, `>`, `>=`, `==`, `!=`, evaluated as *(current gating CC value)* `op` *value*. The gating CC must be a defined `controlChangeNumber` in the same file.
- Variants are evaluated **in array order; first match wins**. The base entry is the default-mode (gating value 0) behavior — never author a redundant variant that just restates it.

**`x_mandatory`** marks a gate CC — the one other CCs constrain against. Each scene keeps a required, non-deletable CC-defaults entry for it, which is the source of truth for mode resolution and is transmitted on scene load. A gate CC has no `x_variants` of its own.

**`x_noop`** (boolean) hides a CC in the modes where it does nothing — e.g. a looper's Record/Play footswitch in the delay modes — instead of showing an inert control. It can sit on a variant (hide only while that constraint matches) or on the base entry (hidden by default, with variants supplying the active modes). A no-op only filters editing/rendering; it does not change what the device transmits.

See [`DEVICE_AUTHORING.md`](DEVICE_AUTHORING.md) for the full rules, the multi-mode matrix workflow, and the variant anti-patterns to avoid.

## Structure

```
devices/
  vendor/
    product.json
```

Each device file contains:
- `schemaVersion` - Schema version (currently `"0.1.1"`)
- `implementationVersion` - Version of the device profile (increment when updating)
- `title` / `displayName` - Full name (search/lists) and short name (device screen)
- `device` - Manufacturer/model metadata
- `receives` / `transmits` - Supported MIDI message types
- `controlChangeCommands` - CC parameter definitions (with optional `x_variants` / `x_mandatory` / `x_noop`)
- `nrpnCommands` - NRPN parameter definitions (if supported)
- `x_pc` - Program change configuration (always present)
- `x_midiTrs` - TRS/TS MIDI wiring type
- `x_midiChannel` - Default MIDI channel

## Manifest

The `manifest.json` file provides a compiled index of all device profiles with metadata:
- SHA-256 hashes for integrity verification
- File sizes
- Quick reference to MIDI capabilities
- Version information

This is the **shared (read-only) device manifest** that ships in the
`/assets` partition. The build script intentionally skips the
`devices/user/` subtree — user-created and cloned pedals live on the device
in `/userdata/devices/`, with their own manifest regenerated by the firmware
when files change. At runtime the firmware loads both manifests and merges
them, with same-slug entries from `/userdata/devices/` overriding the shared
copy.

### Building the Shared Manifest

```bash
ruby tools/build_manifest.rb
```

### Verifying the Shared Manifest

```bash
ruby tools/verify_manifest.rb
```

## Contributing

Contributions of new device profiles are welcome! See [`DEVICE_AUTHORING.md`](DEVICE_AUTHORING.md) for the full authoring guide, then ensure:
1. Device files follow the naming convention: `devices/vendor/product.json`
2. The `implementationVersion` field is set appropriately
3. The file passes `ruby tools/validate_devices.rb` (no errors)
4. The manifest is rebuilt after adding/updating devices
5. The manifest passes verification

## License

MIT License - see [LICENSE](LICENSE) file for details.

