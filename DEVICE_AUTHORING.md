# Prompt: Generate a Storm Summoner Device Definition File

You are helping create a MIDI device definition file in JSON format for the Storm Summoner pedal controller. These files describe how a specific MIDI pedal responds to Control Change (CC) messages, Program Changes, and other MIDI data.

### Before you write

1. Read the **full** MIDI CC section of the manual (all tables, appendices, mode-specific pages) — not just the first table.
2. List every documented CC number and its meaning per mode/page.
3. Identify gate CC(s) that select modes; everything else is either plain or `x_variants`.
4. Author gate CC(s) first, then plain CCs, then variant CCs — or generate from a matrix if there are more than ~20 variant-bearing CCs.
5. Run `midi-devices/tools/validate_devices.rb` and reconcile entry count vs your CC inventory.

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

### Rollers vs discrete lists vs single-value verbs

Storm Summoner derives the on-device and web widget from the **effective**
`valueRange`. Pick the shape that matches the parameter:

- **Continuous roller** — no `discreteValues`. A swept value over a numeric
  range (depth, rate, mix). The user scrolls a roller from `min` to `max`.
- **Discrete list / dropdown** — `discreteValues` with **2 or more** entries.
  A pick-one selector (mode, shape, subdivision). Each entry needs a short name.
- **Single-value verb / trigger** — `discreteValues` with **exactly one**
  entry. A momentary action that fires when *any* value is sent (tap, reset,
  record, play). The web editor renders this as a verb badge, not a dropdown.

### Tighten `max` to the highest useful value

Do **not** use `"max": 127` when the highest meaningful value is smaller. A
toggle or verb is `"max": 1`; a 4-mode selector is `"max": 3`. A too-wide range
produces a roller full of meaningless values. Reserve `"max": 127` for genuinely
continuous parameters and for banded ranges (see below) where the full sweep is
valid.

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

## Mode-dependent CCs: `x_variants`

Some devices reuse one CC for different functions depending on a *mode* set by
another CC (e.g. on a delay/looper, CC 102 = Bypass in Delay mode but Play/Stop
in Loop mode, where CC 24 selects the mode). There is still **exactly one entry
per CC number** — `cc_lookup` and the validators require it. Instead of a second
entry, attach an `x_variants` array that overrides the entry's `name` and
`valueRange` when a constraint on the gating CC matches.

```jsonc
{
  "controlChangeNumber": 102,
  "name": "Bypass",                  // base = default-mode (gating value 0) behavior
  "valueRange": {
    "min": 0, "max": 1,
    "discreteValues": [
      { "name": "Off", "value": 0 },
      { "name": "On", "value": 1 }
    ]
  },
  "x_variants": [
    {
      "constraint": { "cc": 24, "op": ">=", "value": 3 },
      "name": "Play/Stop",
      "additionalInfo": "Loop mode: toggles play/stop on any value",
      "valueRange": {
        "min": 0, "max": 1,
        "discreteValues": [ { "name": "Toggle", "value": 1 } ]
      }
    }
  ]
}
```

Rules:

- **`constraint`** is `{ "cc": <gating CC>, "op": <operator>, "value": <int> }`.
  `op` is one of `<`, `<=`, `>`, `>=`, `==`, `!=`, evaluated as
  *(current value of the gating CC)* `op` *value*. The gating CC must be a
  defined `controlChangeNumber` in the same file.
- Variants are evaluated **in array order; first match wins**. When no variant
  matches (or the gating value is unknown), the base entry applies.
- The **base entry is the default-mode behavior** (gating value 0). Do not
  author a redundant variant for the default mode, and never use a
  "mode-agnostic" placeholder — a pedal is always in some mode.
- Only add `x_variants` to CCs whose meaning actually changes with the mode.
  CCs unaffected by the mode stay plain. The base must always be valid on its own.
- A variant may override `name`, `valueRange`, and/or `additionalInfo`; omitted
  fields fall back to the base. The same roller/list/verb rules apply to the
  effective `valueRange` (so a CC can be a list in one mode and a verb in another).
- The variant `name` still obeys the 14-character display budget.
- CCs that exist only in a non-default mode should be hidden in the modes where
  they do nothing using `x_noop` (see below) rather than being shown as inert
  controls.

#### Variant anti-patterns (read before authoring)

These mistakes produce huge, wrong files. **Reference:** `devices/chase_bliss/big_time.json` (simple gate); `devices/torso_electronics/s4.json` (multi-mode matrix).

| Wrong | Right |
|-------|-------|
| Every CC lists a variant for **every** gate value, mostly `x_noop` | Base = gate value **0** behavior; add variants **only** where the name or `valueRange` actually changes, or where the CC is dead in that mode (`x_noop`) |
| Redundant variant when the mode uses the **same** name as the base | Omit that variant entirely |
| `"name": "Offset"` on the base with no `x_noop`, but the CC is unused in the default mode | Either base = default-mode function, **or** base `x_noop: true` plus a variant for the mode where it is active |
| Stopping after the first mode table in the manual | Inventory **all** documented CC tables/sections before writing JSON |
| Hand-typing 50+ variant entries in one chat turn | Build a CC×mode matrix from the manual, then generate JSON (script or structured passes) |

**Sanity check:** if most of your `x_variants` arrays are the same length as the number of gate values, you are probably enumerating modes instead of diffing them. A typical CC should have zero variants, one `x_noop`, or one renamed variant — not seven no-ops and two names.

**Completeness check:** after authoring, count documented CC numbers in the source against `controlChangeCommands` entries. Every documented CC number gets exactly one entry. Gaps in the middle of a range (e.g. CC 47 or CC 14–45 missing) usually mean the file was truncated, not that those CCs are unused.

### Multi-mode matrix devices

When the manual gives **separate parameter tables per mode** (engine, device type, page, etc.) that reuse CC numbers:

1. **Pick the gate CC** — the documented CC (or CCs) that select the mode. Mark it `x_mandatory` with `discreteValues` matching the manual.
2. **Build a matrix** — rows = CC numbers, columns = gate values, cells = parameter name or blank. Blanks become `x_noop` variants (or a no-op base with one active variant, whichever is shorter).
3. **Default column = base** — gate value 0 is the base entry; do not repeat it in `x_variants`.
4. **Plain CCs** — CCs whose meaning does not change with the gate stay a single entry with no `x_variants`.
5. **Independent subsystems** — if another axis also changes names (e.g. modulator *type* vs device *type*) but the manual does not expose it via MIDI, you cannot fully model both axes with one constraint each. Use generic names, base+partial variants for the axis you *can* gate, and note the limitation in `additionalInfo`. Do not invent a second gate CC without maintainer agreement.

Run `tools/validate_devices.rb` when done.

### `x_mandatory` on gate CCs

A gate CC — the one other CCs constrain against (the Mode selector above) —
should carry `"x_mandatory": true`:

```jsonc
{
  "controlChangeNumber": 24,
  "name": "Mode",
  "x_mandatory": true,
  "valueRange": {
    "min": 0, "max": 3,
    "discreteValues": [
      { "name": "Mod", "value": 0 },
      { "name": "Short", "value": 1 },
      { "name": "Long", "value": 2 },
      { "name": "Loop", "value": 3 }
    ]
  }
}
```

`x_mandatory` flags the CC as one whose value gates other controls' variants.
Each scene keeps a **required, non-deletable CC Defaults entry** for it: it is
auto-set to its first valid option when the scene's CC Defaults are first opened
and cannot be set to "None". That stored value is the scene's source of truth for
mode resolution (it seeds the live CC cache on both the device and the web
editor) and is transmitted on scene load. A gate CC has no `x_variants` of its
own.

### `x_noop`: hiding a CC in certain modes

Some CCs only exist in one mode (e.g. a looper's Record/Play/Stop footswitches
exist in Loop mode but do nothing in the Delay modes). Rather than show an inert
control, mark the dead modes with `x_noop`. A no-op CC is skipped by the device
parameter menus and shows as "n/a in this mode" in the web editor; its stored
value is preserved so it returns when the gate changes back.

`x_noop` can appear in two places:

- **On a variant** — hide the CC only while that variant's constraint matches.
  This is the usual form: the base entry is the real function, and a no-op
  variant removes it in the modes where it does not apply.

```jsonc
{
  "controlChangeNumber": 104,
  "name": "Record",                  // base = the real (Loop-mode) function
  "valueRange": {
    "min": 0, "max": 1,
    "discreteValues": [ { "name": "Record", "value": 1 } ]
  },
  "x_variants": [
    { "constraint": { "cc": 24, "op": "<", "value": 3 }, "x_noop": true }
  ]
}
```

- **On the base entry** — hide the CC by default (when no variant matches), with
  variants supplying the modes where it *does* appear. Use whichever framing
  keeps the base entry meaningful.

Notes:

- A no-op variant needs only its `constraint` and `"x_noop": true`; `name` and
  `valueRange` are ignored.
- `x_noop` is boolean. It does not change what the device transmits — it only
  filters editing/rendering in the gate combinations where the CC is dead.

---

## The additionalInfo Field

This optional field on a CC entry (or a variant) is **author-only**. It is
**never displayed** in the device or web UI — it exists purely as a note for
whoever maintains the JSON. Because it is never shown, the `name` must stand on
its own within the ~14-character budget; do not rely on `additionalInfo` to
disambiguate a name. Good uses:

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

11. **Named PCs and note triggers are out of scope.** Do not add `controlChangeCommands` entries for Program Change preset names or MIDI-note transport/mute actions unless the schema explicitly supports them. List only what `controlChangeCommands` can express today.

12. **MIDI channel affects meaning, not `x_midiChannel` alone.** If the manual says the same CC number means different things on different channels (e.g. track 1–4 vs global channel 16), document that in the device or gate CC `additionalInfo`. The scene still uses one effective channel; per-parameter channel is not modeled separately.

13. **Do not stop mid-table.** If the manual documents CC 46–61 *and* CC 62–125 in separate sections, the file must cover both. Partial coverage is worse than a smaller device file done completely.

14. **`x_variants` is for diffs, not inventory.** Never emit a variant whose only purpose is to restate the base name. Never list every gate value on every CC "just to be safe."

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
