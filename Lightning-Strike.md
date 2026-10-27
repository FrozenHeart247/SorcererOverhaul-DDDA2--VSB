# Lightning Strike / Lightning Burst

Trial edit from October 27, 2026. The logic for the implemented VSB (Visual/Skill Behavior) has been verified on a test character; in-game testing has not yet been performed.

## Reason for the premature *Thunder Rain*

The wait condition was set at frame 0, triggered when the current action contains `JobMagicUser_PrepareLevin`. Since the "Prepare" phase begins at the start of the skill, this condition was met immediately. Consequently, the timeline continued to progress—triggering *Wight* at frame 70 and *Thunder Rain* at frame 80—regardless of whether the skill was actually ready or the button had been released.

In the functional *Fire Ground* implementation, a different condition is used: it waits for `JobMagicUser_CastSalamander`. For *Levin*, the corresponding stage is `JobMagicUser_CastLevin`—a name present in both the established action catalog and the list of actions detected by the game.

## Sequence after the edit

| ID | Timeline Frame | Action |
|---|---:|---|
| n1 | 0 | `JobMagicUser_PrepareLevin`, layer 1 |
| n2 | 70 | *Wight*: `ch227001DarkBulletSLightVerShellParamData.user`, shell 15 |
| n3 | 70 | `wait_until`: current action contains `JobMagicUser_CastLevin` |
| n4 | 71 | `ch253001LevinSpellShellParamData.user`, shell 11 — *Straight Thunder Rain* (Enhanced) |
| n5 | 72 | End timeline |

Nodes occurring on the same frame are executed in the order they appear in the JSON array. Therefore, n2 must remain before n3: *Wight* is triggered first, followed by the wait condition. If the wait condition were placed at frame 0, it would also delay the *Wight* effect until the preparation phase is complete. Frame 71 does not mean that "Thunder Rain" will necessarily appear 71 frames after the button is pressed; the wait command pauses the timeline at frame 70. The subsequent frame occurs once the VSB detects the "CastLevin" action.

In `n3`:

```json
"frame": 70,
"op": "wait_until",
"window": 600,
"condition": {
"state": "in_action",
"arg": "JobMagicUser_CastLevin",
"negate": false
},
"else_target": "n5"
```

The `else_target` in `wait_until` serves as an exit point if the time limit is reached. Previously, it pointed to "Thunder Rain," which meant the skill would trigger even without the "Cast" action if the timeout elapsed. Now, the exit point leads to the completion phase.

The wait is capped at 600 frames—approximately 10 seconds at a speed of 1—starting from frame 70. Here, the effect is tied to the initiation of "CastLevin" (following the preparation phase), much like "Fire Ground" is tied to "CastSalamander." The full completion of the casting animation is a separate stage; this configuration does not wait for it to finish.

## Files

- Game file: `F:\SteamLibrary\steamapps\common\Dragons Dogma 2\reframework\data\VSB\packs\fh_sorc\skills\new_skill_4.json`
- Prepared version: `prepared/new_skill_4.json`
- Backup: `backups/new_skill_4.original.json`

Only the wait frames, the primary shell, the completion phase, the expected action name, and the timeout exit point have been modified. The parameters for both shells—including their positioning and tracking of the Wight—as well as the settings for both levels, remain unchanged. "Fire Ground" has not been altered. After restarting the game or performing a "Rescan packs": hold the preparation phase beyond frame 80 — the Wight should appear, while the Thunder Rain should not yet be triggered. Upon transitioning to the "CastLevin" state, the Thunder Rain should be requested exactly once. The visible effect may have its own internal shell-level delay.

## Automated Verification

`verification/lightning-strike/verify.ps1`: 34 test cases executed on actual modules from an installed VSB, using a dummy actor. A previously identified bug has been reproduced; the tests cover both stages—ensuring the Wight appears at frame 70 and that the Thunder Rain does not trigger before the "Cast" phase—across various preparation durations, including single-trigger scenarios, timeouts, and interruptions via a strike. Results: `verification/lightning-strike/results.txt`.