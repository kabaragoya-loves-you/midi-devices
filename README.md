# Storm Summoner MIDI Device Database

A comprehensive database of MIDI-capable effects pedals for the [Storm Summoner](https://kabaragoya.com) MIDI controller.

## Overview

This repository contains device profiles in JSON format that describe the MIDI implementation of various effects pedals. Each profile includes information about supported MIDI messages, control change parameters, and program change behavior.

## Schema

Device profiles are based on the [Open MIDI RTC JSON schema](https://github.com/Open-MIDI-RTC/MIDI-RTC-Schema) with several custom extensions prefixed with `x_`:

### Custom Extensions

**Program Change Support**
```json
"receives": ["PROGRAM_CHANGE"]
```

**Program Change Configuration**

Simple count-based:
```json
"x_pc": { "indexBase": 0, "count": 36 }
```

Named presets:
```json
"x_pc": { "indexBase": 0, "names": ["Hall", "Plate", "Spring", "..."] }
```

Bank select support:
```json
"x_pc": { "indexBase": 0, "count": 128, "bankSelect": true }
```

**Program Change Notes**
```json
"x_pcNote": "Responds to CC#0/32 bank select before PC."
```

## Structure

```
devices/
  vendor/
    product.json
```

Each device file contains:
- `implementationVersion` - Version of the device profile (increment when updating)
- `receives` / `transmits` - Supported MIDI message types
- `controlChangeCommands` - CC parameter definitions
- `nrpnCommands` - NRPN parameter definitions (if supported)
- `x_pc` - Program change configuration (if supported)

## Manifest

The `manifest.json` file provides a compiled index of all device profiles with metadata:
- SHA-256 hashes for integrity verification
- File sizes
- Quick reference to MIDI capabilities
- Version information

### Building the Manifest

```bash
ruby tools/build_manifest.rb
```

### Verifying the Manifest

```bash
ruby tools/verify_manifest.rb
```

## Contributing

Contributions of new device profiles are welcome! Please ensure:
1. Device files follow the naming convention: `devices/vendor/product.json`
2. The `implementationVersion` field is set appropriately
3. The manifest is rebuilt after adding/updating devices
4. The manifest passes verification

## License

MIT License - see [LICENSE](LICENSE) file for details.

