# Magic Evade: hold instead of toggle

**In-game result: this trial does not activate native avoidance.** Start plays its animation only. The user also confirmed that the original Avoid action produced a single dodge, not an active automatic-avoidance mode. The controller tests below verify input and action requests only; they do not establish a working ability. The installed skill is being restored to its original single-dodge JSON while the native control is investigated.

The subsequent native-buff companion trial is documented in `Magic-Evade-Native.md`. It uses activation/clear methods identified in the live game report and is separate from this failed animation-only trial.

`diagnostics/FH_MagicEvadeProbe.lua` is a one-shot, read-only metadata probe for that investigation. When installed under autorun, it waits for a loaded player, lists bounded Human/Character-related type metadata, and writes `reframework/data/VSB/diagnostics/magic_evade_probe.json`. It invokes no discovered setters or ability methods and makes no character-state writes. It does not require combat or changing vocation. Remove the probe after collecting the report.

This is a trial input controller for `new_skill_7` (Magic Evade). It requests `Job04_AbsoluteAvoidanceStart` on activation and `Job04_AbsoluteAvoidanceEnd` on release, using the installed VSB script API.

The original enabled node requested `Job04_AbsoluteAvoidanceAvoid` directly. The action catalogue contains separate Start, Avoid and End actions; whether Start and End correctly activate and deactivate the native ability from a sorcerer skill still requires an in-game check.

## Input handling

`scripts.on_start` captures the held `Skill1` through `Skill6` input flags once. `scripts.on_frame` ends the cast when a captured input is released. This aims to follow the assigned skill slot rather than a hard-coded keyboard key. Another button pressed later cannot take over the original hold.

If several skill flags are held at activation, all of them must remain held; releasing any captured flag ends the cast. If none is detected, the cast finishes immediately and requests End, with a diagnostic message in the VSB log. This prevents a missing input mapping from leaving the toggle active.

The configured `end.exit_action` requests the native End action on a normal VSB finish. Standard interruption and replacement rules remain those of VSB; this is not a new global invulnerability flag or a framework patch. Native behavior during hits, death or unrelated interruption needs separate in-game confirmation.

The large `end.at_frame` prevents VSB's default timeline/tail completion from ending a held skill after a few seconds. Normal operation finishes through the input script on release; it does not wait for that frame. The editor's disabled end and empty shell nodes were preserved.

VSB runs one active cast per actor. While this controller is holding Magic Evade, another ordinary VSB skill cannot take over at the same priority. No concurrency changes were made.

## Files

- Prepared JSON: `prepared/magic-evade-hold/new_skill_7.json`
- Readable scripts: `prepared/magic-evade-hold/on_start.lua` and `on_frame.lua`
- Original backup: `backups/magic-evade-hold/new_skill_7.json`
- Game destination: `reframework/data/VSB/packs/fh_sorc/skills/new_skill_7.json`

Only the prepared JSON needs to be installed. Both scripts are embedded in it. Identity, presentation, conditions, learning requirements and configured costs are unchanged. Native ability stamina drain, if activated by Start, remains game behavior and has not been measured here.

## Verification

`verification/magic-evade-hold/verify.ps1` runs the actual installed VSB executor, scripting extension, sandbox, schema and node handlers with simulated input/actions. It accepts an optional `-AutorunRoot` path. All 35 assertions passed: Start/End requests for the six candidate slot flags, natural action changes, a 20-second hold, release, immediate retry, held-input retry rejection, unrelated buttons, ambiguous chords and missing input.

These checks verify requested actions and controller behavior. They do not prove real input flag mapping, native ability state, avoidance effectiveness, animations or ongoing stamina drain.

After Rescan packs or a restart, equip Magic Evade and activate it from its assigned slot. Hold, release, then press and release again. Also check that an attack during the hold uses the expected avoidance behavior and that avoidance stops after release. The editor's Test button has no held skill input and is therefore expected to finish immediately.
