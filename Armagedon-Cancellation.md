# Armagedon: preparation cancellation

This adds a per-skill `scripts.on_frame` handler to Armagedon (`new_skill_copy_copy`). It preserves the existing timeline and all shell settings, including frames **78, 325 and 416**.

The original timeline kept advancing after native preparation cancellation. Consequently, cancelling at about one second still allowed all three scheduled custom shells to launch later.

The handler follows the `MeteorFall` action family on both layers:

- During Prepare / Ready / SpellStock, leaving the family ends the VSB timeline. Explicit cancel action names finish immediately when observed outside that family; returning to neutral actions uses a 0.10-second grace period for short transition gaps.
- Startup has the same 0.25-second allowance used by the other spell guards, so a delayed action request and the previous cancellation state do not stop a fresh cast.
- Once `Job06_CastMeteorFall` has been observed, the handler latches `armagedon_released`. The remaining sequence then follows the original schedule even if the cast animation finishes before frame 416.
- Missing layer data is not treated as confirmed cancellation. Standard VSB hit interruption remains in effect.

Ending the timeline prevents its remaining nodes from firing. It does not remove shells that have already been created: the installed VSB script API has no shell-stop operation. A shell may also launch during the short neutral-state grace interval before cancellation is confirmed. The fix specifically covers cancelling preparation; after actual release, the scheduled sequence is allowed to complete.

## Files

- Prepared skill: `prepared/armagedon-cancel/new_skill_copy_copy.json`
- Readable handler, embedded in that JSON: `prepared/armagedon-cancel/cancel-guard.lua`
- Backup immediately before this change: `backups/armagedon-cancel/new_skill_copy_copy.json`
- Game destination: `reframework/data/VSB/packs/fh_sorc/skills/new_skill_copy_copy.json`

The standalone Lua file is for review. The game only needs the prepared JSON; no framework Lua changes are required.

## Verification

Run `verification/armagedon-cancel/verify.ps1`. Its optional `-AutorunRoot` argument selects the local VSB/DragonCore installation. Repository fixture paths are relative, so moving the repository does not invalidate them.

The check uses the installed VSB executor, scripting extension, sandbox, schema and node handlers with simulated actor actions and time. All 18 assertions passed, including:

- Reproducing the original three-shell sequence after a cancellation at one second.
- No scheduled shells after that cancellation with the fix, and accepting a subsequent cast.
- Cancelling after the frame-78 shell prevents frames 325 and 416.
- Normal Prepare / Ready / SpellStock / Cast transitions retain the exact 78 / 325 / 416 schedule, including early cast-animation completion.
- Delayed startup, brief action gaps, missing layer data and hit interruption.

This is executor-level verification. Reload the packs or restart the game, prepare Armagedon for about one second, cancel, and try again. Also verify one uninterrupted cast. Actual visuals and the native cancellation action still require this in-game check.
