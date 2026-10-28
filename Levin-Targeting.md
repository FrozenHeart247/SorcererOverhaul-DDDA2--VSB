# Lightning Strike / Lightning Burst: native Levin targeting

Companion version 4 is installed and loaded in the running game. Native hook validation with an initially empty targeting request passed on 2026-10-28. Enemy acquisition on the first real cast after loading still needs a gameplay check.

The version 3 gameplay test found a missing part of profile selection: casting Lightning Burst first produced requests with `Job=0`, `ActionType=0`, `CustomSkillID=0`. The hook supplied Levin's ID but preserved Job 0, so the native lookup still returned a default profile. After a vanilla spell, subsequent requests already contained Job 6 and the override resolved Levin correctly. Those real-cast logs are preserved in `verification/levin-targeting/cold-start/before-fix-status.json`. Version 4 explicitly selects Job 6 in the copied range request; it does not change the character's vocation.

VSB intercepts `PlayerInputProcessorDetail.processCustomSkill(...)`, starts its own executor and skips the original handler. Its action node requests `JobMagicUser_PrepareLevin` through `ActionManager.requestActionCore(...)`. That animation request does not select Levin's lock-on profile for the custom skill ID.

The live lookup compared job 6 / action type CustomSkill / action ID 0:

| Request skill | Resolved profile | Camera targeting | Lock-on UI | MaxDistance |
| --- | --- | --- | --- | --- |
| Lightning Strike custom ID 141 | Default / skill 0 | false | false | -1 |
| Native `Job03_Levin` ID 25 | CustomSkill / skill 25 | true | true | 32 m |

Levin's acquisition ranges in this installation are 30 m. These are the user's current game/mod parameters, not a claim about unmodified game defaults. The companion selects the existing profile instead of hardcoding a larger radius.

## Implementation

`FH_LevinTargeting.lua` subscribes to `VSB_API.app.bus` and matches pack `fh_sorc` plus skill UUID `3c0b8528-94e6-431a-bd46-a2be7e2c6501`. Both levels share that UUID. The displayed names and the dynamically assigned custom game ID are not used to identify the skill.

While that cast is active, a hook on `app.LockOnController.updateLockOn(app.LockOnController.Option)` copies the exact player's Option and its referenced RequestParameterInfo. Both are **managed reference types** in this DD2 build. It selects Job 6 / CustomSkill / action 0 / the native Levin ID and enables lock-on UI on the copy. Airborne/target-change flags, update mode, target object, transforms, scaling, counts and other option fields are copied unchanged. Both copies remain referenced until the native call returns. The caller's objects and the game's range table are not edited.

Cast end, cancellation, replacement, invalid player, detachment and script reset remove the active scope. A stopped controller's installed hooks remain neutral. SDK errors leave the original call arguments in place and are reported. Hook installation happens before the first cast, because REFramework applies newly registered hooks after the frame callback.

The companion does not force a new target, force animations, spawn shells or change the player's vocation/equipment. Skill JSON, costs, timing and cancellation guards are unchanged. Other mods' existing targeting profile changes therefore remain part of the native Levin profile used here.

## Files and installation

Merge `prepared/levin-targeting/reframework/` into the game's `reframework/` folder:

- `autorun/FH_LevinTargeting.lua`
- `autorun/FH_LevinTargeting/controller.lua`

The current installation was hot-loaded without resetting VSB or the editor. On a fresh installation, restart the game to load the autorun entry. Ensure `reframework/data/VSB/diagnostics/` exists for optional status JSON. The companion still works if diagnostic writing is unavailable.

The status file is `data/VSB/diagnostics/levin_targeting_status.json`. It records readiness, cast level, number of intercepted updates and the first request/profile used. Normal real casts should produce `start` then `stop` events with updates greater than zero. A `hook_error` disables that cast's override.

## Validation

39 standalone behavioral checks passed with mocked SDK objects and the real VSB event bus: both levels, unrelated skills/controllers, original-object preservation, option flags, native profile selection, copy lifetime, cancellation, completion, invalid actor, SDK failure and shutdown. The regression case begins with Job, action type and skill ID all zero; the copied request still selects the native Levin range.

The version 4 bounded live check called the real controller once using KeepLockOn, without emitting VSB events or requesting an action/shell. Its initial request had Job 0, action type 0, skill 0 and resolved a default profile with MaxDistance -1 and camera targeting false. The hook changed the copy to Job 6 / native Levin 25 and resolved the camera/UI profile with MaxDistance 32. The original request retained Job 0 and skill 0, original UI stayed false, the target stayed absent and the active scope was cleared. This validates native profile selection from an empty request; it does not prove enemy acquisition during gameplay. The report is `verification/levin-targeting/cold-start/live-verification.json`.

Evidence is under `verification/levin-targeting/`. The live skill JSON SHA256 before and after installation was `633C5384F61F80BAD655ACF2B1F3B845D8B93B409C30BD2BAAAC29D3C26A15E0`.

For gameplay verification, cast Lightning Strike/Burst immediately after loading, before any vanilla spell. Test a visible distant enemy, hold the prepare phase, change target, cancel, then cast again. Real-cast version 3 reports showed update modes 1 and 7 with Job 0, and mode 1 with Job 6; version 4 preserves those update modes and initializes the profile's Job itself. The bounded check intentionally uses KeepLockOn mode to avoid changing targets while paused.

The diagnostics directory contains a read-only metadata probe, standalone test, bounded live check, and a hot-load helper. The helper has paths specific to this machine and is not an autorun component. The REFramework ScriptRunner uses its own module search paths; the helper supplies this companion's module explicitly through `package.preload`.

SDK allocation and hook APIs were checked against the [REFramework SDK documentation](https://cursey.github.io/reframework-book/api/sdk.html). Game-specific types and fields were verified in the live TDB probe.

## Rollback

Move only the two companion Lua files out of autorun and restart the game. No JSON restoration is necessary. To disable only the current loaded instance from Lua, call `_G.FH_LevinTargeting:shutdown()`.
