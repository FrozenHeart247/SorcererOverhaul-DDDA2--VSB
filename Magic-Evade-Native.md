# Magic Evade: native AbsoluteAvoidance while held

**Live result of trial 1:** Skill3 was captured correctly; the native start call read back `active=true`, then the flag was false 8–10 ms later. Automatic avoidance did not work. The report is preserved in `verification/magic-evade-native/trial-1/native-status.json`. This proves activation was transient, not a working held ability. The cause of the immediate reset is not yet confirmed.

**Live result of trial 2:** without any Start/End requests, the buff still ended on the first update (about 0.013 seconds). Its parameter changed from present to absent. The original native AbsoluteAvoidance skill level was 0; stamina was still above 870. Thus, the forced animation hypothesis did not explain the failure. The report is preserved under `verification/magic-evade-native/trial-2/`.

**Live result of trial 3:** exposing native level 1 did not help. Only diagnostic getter calls were intercepted before expiry; the buff still vanished on the first update. This availability override has been removed.

**Current trial 4:** live inspection found the exact cause. The derived `Job04AbsoluteAvoidanceBuff.isTimerOver()` directly scans the current vocation's equipped skill array for native skill ID 42. If absent, it immediately returns true; if present, it calls `CustomSkillBuff.isTimerOver()`. This scan is inlined, so hooks on skill-level and equipment getters cannot affect it. The captured code and report are preserved under `verification/magic-evade-native/trial-3/` and `trial-4/`.

The companion now calls that same base expiry method only for the exact buff instance it owns. A live paused test confirmed: the owned expiry result was false, the buff remained active after 120 manager updates (timer about 2 seconds), and explicit release cleared it. Afterwards, the original equipment expiry result was true again. Actual automatic avoidance against an incoming attack still needs a gameplay test.

This trial uses the real AbsoluteAvoidance buff rather than relying on animation requests to activate it. A live TDB 83 report from the user's game identified:

```text
app.Human.SpecialBuffManager : app.HumanSpecialBuffManager
startBuff_Job04AbsoluteAvoidance(app.HumanCustomSkillLevelNo, System.Action`1<app.DummyArg_2_0_0_1>)
get_IsActiveJob04AbsoluteAvoidance()
clearBuff_Job04AbsoluteAvoidance()
```

The earlier Start/End-only trial failed its in-game test: Start played its animation without activating avoidance. The original Avoid action was also confirmed to be one dodge, not automatic evasion. The earlier controller checks therefore establish input/action scheduling only.

## How the native trial works

The companion subscribes to the VSB application's public event bus (`VSB_API.app.bus`). It matches only `fh_sorc` skill UUID `3f67be32-a628-4ec1-8e8a-0f13b70725cc`.

At activation it captures the held Skill1…Skill6 inputs, obtains the current player's HumanSpecialBuffManager, calls the exact start signature with the skill level and a null callback, then reads back the active flag. The live trial now confirms that the buff remains active through manager updates; automatic avoidance itself is not yet verified.

The JSON controller keeps VSB active until release. The companion manages the buff without forcing Start or End actions. To retain VSB's normal hit checks, it observes the already-current action in the cast context without requesting another animation. Releasing a captured button or ending the VSB cast clears the buff created by this companion. The same cleanup covers hits, forced replacement, pack reload and script reset. A changed/invalid player is never accessed through the old manager.

The companion does not repeatedly refresh the buff. If the native game ends it, the VSB controller is asked to finish. An already-active native buff is treated as externally owned and is not cleared by the companion. Persistent native-clear failures are reported after bounded retries; they are not proof of a successful clear.

For trial 4, the companion intercepts only the derived AbsoluteAvoidance expiry method. For the exact owned buff and current valid player manager, it uses the base CustomSkillBuff expiry method. Other buff instances and externally owned native buffs keep their original behavior. No learned-level list, equipment slot or player job is changed. Native duration/parameter checks and `updateStamina` remain in effect. Hook registration happens before the first cast because REFramework applies newly registered hooks after the current Lua callback. Diagnostic snapshots include adapter version, expiry check count and base expiry errors.

The configured VSB costs and learning settings are unchanged. Native buff stamina behavior remains under the game manager and has not been measured. VSB still allows one cast per actor, so another ordinary VSB skill cannot run concurrently at the same priority.

## Installation

Merge `prepared/magic-evade-native/reframework/` into the game's `reframework/` directory. The package contains:

- `autorun/FH_MagicEvade.lua`
- `autorun/FH_MagicEvade/bridge.lua`
- `autorun/FH_MagicEvade/native.lua`
- `data/VSB/packs/fh_sorc/skills/new_skill_7.json`

The status report is written under `data/VSB/diagnostics/`; that folder exists in the current installation from the metadata probe. Ensure it exists when installing this package elsewhere. No VSB or DragonCore source files are replaced.

New autorun scripts need a game restart or REFramework script reset; Rescan packs alone only reloads the JSON. Once loaded, use the assigned Magic Evade skill button, not the editor's Test button.

The companion writes recent activation/cleanup events to `data/VSB/diagnostics/magic_evade_native_status.json`, including active-flag readback, captured inputs, failed activation, native expiry and cleanup errors. This report contains local diagnostics, not save data.

## Validation status

The actual installed VSB executor, sandbox, event bus and node handlers were tested together with the companion and native adapter. Native SDK objects/hooks were simulated using the exact reported signatures. All 55 assertions passed, including all six inputs, long hold without refresh, release, interruption/replacement/reload/reset cleanup, pre-existing buffs, failed activation, missing input/signatures, transient cleanup failure, player replacement, scoped equipment bypass and preserved base expiry. The live manager-update test independently verifies that the real hook prevents the immediate expiry and that explicit release clears the native buff. Neither check proves automatic avoidance against a real attack.

Run `verification/magic-evade-native/verify.ps1`, optionally specifying `-AutorunRoot`. Supporting live metadata excerpts are in `verification/magic-evade-native/native-api.json`.

**Native activation, persistence through updates and explicit cleanup are verified in game; real automatic avoidance remains unverified.** Next test: hold Magic Evade while receiving an ordinary attack, release, then verify that the next attack is no longer automatically avoided. Read the status report to distinguish an activation error from an active buff with unexpected gameplay behavior. `diagnostics/verify_magic_evade_expiry.lua` reproduces the paused update/cleanup check after the companion has initialized.

## Rollback

Restore `backups/magic-evade-native/new_skill_7.json` to the skill path. Remove only the three companion Lua files listed above, then restart/reset scripts. The original one-shot dodge remains available. The read-only metadata probe is no longer needed once its report has been collected.
