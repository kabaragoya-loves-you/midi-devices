# Prompt: Generate a Storm Summoner Device Definition File

You are helping create a MIDI device definition file in JSON format for the Storm Summoner pedal controller. These files describe how a specific MIDI pedal responds to Control Change (CC) messages, Program Changes, and other MIDI data.

---

## Required File Structure

Every file must contain all of the following top-level fields:

```json
{
  "schemaVersion": "0.1.1",
  "implementationVersion": "0",
  "title": "Manufacturer Model Name",
  "displayName": "Short Name",
  "device": {
    "displayName": "",
    "manufacturer": "Manufacturer Name",
    "model": "Model Name",
    "version": ""
  },
  "receives": [],
  "transmits": [],
  "controlChangeCommands": [],
  "x_pc": {
    "indexBase": 0,
    "count": 0,
    "bankSelectMode": "none"
  },
  "x_midiTrs": "TYPE_A",
  "x_midiChannel": 1
}
```

- `schemaVersion` must be exactly `"0.1.1"`.
- `implementationVersion` is always `"0"` for new files.
- `title` is the full name shown in search/lists.
- `displayName` is the short name shown on the device screen (keep it brief).
- `device.displayName` is usually left as an empty string `""`.
- `device.version` is left as `""` unless a specific hardware version applies.

---

## The x_pc Block (Program Change / Presets)

This block is **always required**, even if the device has no presets.

```json
"x_pc": {
  "indexBase": 0,
  "count": 128,
  "bankSelectMode": "none"
}
```

- `indexBase`: `0` if the device numbers its presets starting from 0; `1` if it starts from 1.
- `count`: Total number of presets. Use `0` if the device has no presets at all.
- `bankSelectMode`: `"none"`, `"CC0"`, or `"CC0_CC32"` depending on whether the device uses bank select messages to access more than 128 presets.

---

## The receives and transmits Arrays

Only use these valid message type strings:

- `"NOTE_NUMBER"` — do **not** use `NOTE_ON` or `NOTE_OFF`
- `"PROGRAM_CHANGE"`
- `"CLOCK"`
- `"VELOCITY_NOTE_ON"`, `"VELOCITY_NOTE_OFF"`
- `"CHANNEL_PRESSURE"` — do **not** use `AFTERTOUCH`
- `"POLY_PRESSURE"`
- `"PITCH_BEND"`
- `"TRANSPORT_START"`, `"TRANSPORT_STOP"`, `"TRANSPORT_CONTINUE"`

`transmits` is almost always `[]`. Only add `"CLOCK"` to transmits if the device manual explicitly states it can output MIDI clock.

---

## The x_midiTrs Field

Must be one of: `"TYPE_A"`, `"TYPE_B"`, `"TYPE_TS"`, `"BOTH"`.

Check the device's manual or TRS MIDI standard information to determine the correct value. Default to `"TYPE_A"` if unknown.

---

## controlChangeCommands Entries

Each entry describes one CC parameter. The minimal form for a simple continuous parameter is:

```json
{
  "controlChangeNumber": 14,
  "name": "Mix",
  "valueRange": { "min": 0, "max": 127 }
}
```

Use this compact single-line format for `valueRange` when there are no discrete values.

### CC Name Length

**Names must be 12–14 characters or fewer.** The device has a small display. Use abbreviations where necessary:

| Full word   | Abbreviation |
|-------------|--------------|
| Frequency   | Freq         |
| Resonance   | Res          |
| Level       | Lvl          |
| Active side | Act          |
| Side 1      | S1           |
| Side 2      | S2           |
| Left        | Left (fine)  |
| Right       | Right (fine) |

---

## Value Ranges — The Rules

### Simple continuous (0–127)
```json
"valueRange": { "min": 0, "max": 127 }
```

### Range does not start at 0
If the documented range starts at 1 (e.g., "1–3"), use `"min": 1`. Example: a Mode parameter documented as `1=Tap, 2=Knob, 3=Auto` should have `"min": 1, "max": 3`.

### Discrete values — when to add them

Add `discreteValues` when the parameter has specific named states. Common patterns:

**Standard toggle (0=off, 1-127=on or 64-127=on):**
```json
"valueRange": {
  "min": 0, "max": 127,
  "discreteValues": [
    { "name": "Off", "value": 0 },
    { "name": "On", "value": 127 }
  ]
}
```

**Physical footswitch (momentary press):**
```json
"valueRange": {
  "min": 0, "max": 127,
  "discreteValues": [
    { "name": "Release", "value": 0 },
    { "name": "Press", "value": 127 }
  ]
}
```

**Bypass state toggle (0=bypass, 127=engaged):**
```json
"discreteValues": [
  { "name": "Bypass", "value": 0 },
  { "name": "Engaged", "value": 127 }
]
```

**INVERTED bypass logic (0=ON meaning bypassed, 1=OFF meaning active):**
Some devices — particularly those with a parameter literally named "Noise Gate Bypass" — use inverted logic where 0 means the bypass IS engaged (effect inactive) and 1 means bypass is disengaged (effect active). In these cases, do NOT use On/Off. Use:
```json
"discreteValues": [
  { "name": "Bypassed", "value": 0 },
  { "name": "Active", "value": 1 }
]
```

**"Any value" trigger (tap tempo, reset, one-shot actions):**
When the documentation says "any value" or "any non-zero value" triggers the action:
```json
"valueRange": {
  "min": 0, "max": 127,
  "discreteValues": [
    { "name": "Tap", "value": 1 }
  ]
}
```
Use value `1` as the canonical trigger value. Choose a contextually appropriate name: `"Tap"`, `"Trigger"`, `"Reset"`, `"Exit"`, etc.

**Exception:** If the device manual specifically states that value `0` is the trigger and all other values are ignored, use value `0` as the single discrete entry instead.

**Multi-state banded ranges:**
Some devices use MIDI value ranges to select modes rather than exact values. For example: `0–63 = Off, 64–127 = On`. Use the canonical extreme values:
- Two bands: use `0` and `127`
- Three bands (e.g., 0–42 / 43–85 / 86–127): use midpoints `21`, `64`, `106`
- Four bands (e.g., 0–31 / 32–63 / 64–95 / 96–127): use midpoints `15`, `47`, `79`, `111`
- Seven bands of equal width across 0–127: use midpoints `9`, `27`, `45`, `63`, `81`, `99`, `118`

Always set `"min": 0, "max": 127` for banded parameters since the full range is technically valid.

---

## Handling Duplicate CC Numbers

Some devices assign the same CC number to different parameters depending on context (e.g., CC 102 = Bypass in delay mode, Play/Stop in loop mode). The JSON format only supports **one entry per CC number**. In this case:

1. Use the primary / most common behavior as the entry name.
2. Add an `additionalInfo` field describing the secondary behavior.

```json
{
  "controlChangeNumber": 102,
  "name": "Bypass",
  "additionalInfo": "In Loop mode: Play/Stop (any value)",
  "valueRange": { ... }
}
```

---

## The additionalInfo Field

This optional field on a CC entry is for notes that help a user understand the parameter but don't change its behavior in the firmware. Good uses:

- Engine/mode restrictions: `"Spring and Tank engines only"`
- Unusual behavior: `"Value 0 triggers tap; values 1-127 have no effect"`
- Dual-purpose CC: `"Alt control: Spread (off=0, on=1+)"`
- Range notes: `"0=0.2 Hz, 100=10 Hz"`

---

## Common Gotchas

1. **No presets ≠ no x_pc block.** Always include `x_pc` with `"count": 0`.

2. **indexBase matters.** If a device's preset menu shows "1–128", set `indexBase: 1`. If it shows "0–127", set `indexBase: 0`.

3. **Don't guess receives/transmits.** If the manual doesn't mention MIDI clock reception, don't add `"CLOCK"`. If it doesn't mention notes, don't add `"NOTE_NUMBER"`.

4. **Value 1, not 0 or 127, for "any" triggers.** Unless the manual specifically describes a different canonical value, use `1` for one-shot trigger actions.

5. **Sort CC entries by controlChangeNumber.** Always list entries in ascending numeric order.

6. **For stepped selectors with no documented mode names**, leave as a plain range with `min: 1` (or `min: 0`) rather than fabricating names. It is better to leave it as a range than to invent wrong names.

7. **"0=OFF, 1-127=ON" is not the same as a standard toggle.** The canonical On value is still `127` for discrete values, but the threshold is 1, not 64.

8. **Relay/cycle buttons** (e.g., "Cycle OD Mode") that advance through options on each press should be treated as momentary footswitches (`Release`/`Press`), not as stepped selectors, because MIDI cannot express "advance by one."

9. **The `device.displayName` field is intentionally blank** in most cases. It is separate from the top-level `displayName`. Leave it as `""`.

10. **Do not add Program Change CC entries.** Program changes are handled separately via `receives` and `x_pc`. Do not create a `controlChangeCommands` entry for a CC that saves or recalls presets — unless the device explicitly documents a CC for this (e.g., "CC 27 = Save to Slot").

---

## Complete Example

```json
{
  "schemaVersion": "0.1.1",
  "implementationVersion": "0",
  "title": "Acme Effects Reverberator Pro",
  "displayName": "Reverberator",
  "device": {
    "displayName": "",
    "manufacturer": "Acme Effects",
    "model": "Reverberator Pro",
    "version": ""
  },
  "receives": [
    "PROGRAM_CHANGE",
    "CLOCK"
  ],
  "transmits": [],
  "controlChangeCommands": [
    {
      "controlChangeNumber": 14,
      "name": "Mix",
      "valueRange": { "min": 0, "max": 127 }
    },
    {
      "controlChangeNumber": 15,
      "name": "Decay",
      "valueRange": { "min": 0, "max": 127 }
    },
    {
      "controlChangeNumber": 16,
      "name": "Type",
      "valueRange": {
        "min": 0,
        "max": 4,
        "discreteValues": [
          { "name": "Room", "value": 0 },
          { "name": "Hall", "value": 1 },
          { "name": "Plate", "value": 2 },
          { "name": "Spring", "value": 3 },
          { "name": "Shimmer", "value": 4 }
        ]
      }
    },
    {
      "controlChangeNumber": 80,
      "name": "Bypass",
      "valueRange": {
        "min": 0,
        "max": 127,
        "discreteValues": [
          { "name": "Bypass", "value": 0 },
          { "name": "Engaged", "value": 127 }
        ]
      }
    },
    {
      "controlChangeNumber": 93,
      "name": "Tap Tempo",
      "valueRange": {
        "min": 0,
        "max": 127,
        "discreteValues": [
          { "name": "Tap", "value": 1 }
        ]
      }
    }
  ],
  "x_pc": {
    "indexBase": 0,
    "count": 128,
    "bankSelectMode": "none"
  },
  "x_midiTrs": "TYPE_B",
  "x_midiChannel": 1
}
```
