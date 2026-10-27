# Improved Salamander — experimental scheme for VSB 1.4.0

Prepared on October 27, 2026. The logic has been verified using the VSB Lua executor with a simulated game character. In-game testing has not yet been performed.

## Issues Identified

- The executor sorts nodes by `frame`, and then by their order in the JSON file if the frame values ​​are identical. Consequently, a `shell` node at frame 68 would execute before a `branch` node at frame 73, even if the `shell` appeared after the `branch` in the array.
- Initially, the `branch` node referenced a non-existent `n4`. The saved backup now points to `n3`; since the `branch` points to itself, it triggers an immediate re-evaluation within the same update cycle, which activates the infinite-loop protection mechanism.
- The `else_target: n1` setting caused the timeline to loop back to the `shell` node. This meant the `branch` could be reached repeatedly, potentially triggering the effect multiple times.
- A `branch` node checks the state only once, at the moment of execution. The `window` field does not transform a `branch` into a "wait" (blocking) operation.
- "No longer in the 'Prepare' phase" does not necessarily mean "already in the 'Cast' phase." In the recorded file `fh_sorc/skills/recorded_skill.json`, the phases are: Prepare (frame 0), Ready (150), Cast (216), and the first standard `shell` (261). These values ​​are specific to that particular recording and do not represent fixed, mandatory durations for each phase.

## New Scheme

| ID | frame | Action |
|---|---:|---|
| `n2` | 0 | Requests `Job06_PrepareSalamander` on layer 1. Original parameters are preserved. |
| `n3` | 0 | `wait_until`: waits until the current action contains `Job06_CastSalamander`. |
| `n1` | 1 | Creates an initial shell with `shell_id: 1` — "6 shots". |
| `n_end` | 2 | Ends the VSB timeline. A timeout also leads here. |

The "Prepare" step and the "Wait" step are both set to the same frame; their order in the array matters. As long as the condition remains false, the timeline stays on frame 0, while in-game actions continue to execute. Therefore, frame 1 for the shell signifies "after the wait," rather than "immediately upon pressing the button."

```json
{
"id": "n3",
"type": "flow",
"frame": 0,
"enabled": true,
"op": "wait_until",
"window": 600,
"condition": {
"state": "in_action",
"arg": "Job06_CastSalamander",
"negate": false
},
"else_target": "n_end"
}
```

Editor labels: `Operation → Wait until...`, `Check → Current action contains...`, `Action name contains → Job06_CastSalamander`, `Wait at most (frames) → 600`, `When time runs out, jump to → n_end`.

In a `wait_until` operation, if the time expires without an `else_target` specified, the timeline simply continues—meaning the shell would have been fired regardless once the timer ran out. In this case, the timeout bypasses that by jumping to `n_end`.

## What exactly is synchronized

The effect is tied to the first detected instance of `Job06_CastSalamander`. At a standard speed of 1, each additional timeline step represents approximately 1/60th of a second; the actual delay also depends on the game's refresh rate. This approach does not directly read the button input, nor does it force the execution of a "Cast" action. Hypothesis to be tested in-game: the initial `Prepare` phase transitions naturally into `Ready`, followed by `Cast` upon the release of the button. A recording of a standard skill confirms the names and sequence of these actions, though it does not definitively prove the behavior for a custom skill. If no such natural transition exists, separate `Ready`/`Cast` states—along with a check for the actual button input—will be required; however, there is no need to guess the specific button at this stage.

In the recording, standard projectiles appear 45 frames after the start of the `Cast` phase. This aligns with the requirement for the effect to trigger "upon release / at the start of the cast." If the precise moment of the standard projectile's appearance is desired, a specific delay following the `Cast` phase will need to be determined. Furthermore, the "shell" (projectile/effect) itself may have an internal delay before it becomes visible or deals damage.

## Limitations of the Initial Version

- A single `wait_until` command in VSB is capped at 600 frames—equivalent to 10 seconds of in-game time at a speed of 1. This duration begins at the start of the `Prepare` phase and encompasses both the preparation and the "hold" period. Once this time elapses, no further effects will occur.
- If the character is struck after their initial defensive window, the skill will be interrupted according to standard VSB rules. If the character returns to an "idle" state without reaching the `Cast` phase, the shell will not appear; however, the `wait_until` condition may persist until it times out, effectively keeping the VSB executor occupied in the meantime.
- The `in_action` check searches for a substring across both layers (0 and 1). The `condition.layer` field does not affect this check; it is used exclusively for `anim_frame`.
- While the `hold` action field remains in the schema, it is hidden in the editor for this version and is not processed by the action handler. Modifying `hold` in an attempt to wait for a button release will have no effect.
- The label "6 shots" is simply a catalog entry for `shell_id: 1` and does not imply the creation of six identical nodes. In this implementation, only a single instance of this shell is created. The number of visible projectiles, their trajectory, and their hit detection must be verified in-game. ## Files and In-Game Verification

Active game file: `F:\SteamLibrary\steamapps\common\Dragons Dogma 2\reframework\data\VSB\packs\fh_sorc\skills\new_skill_3.json`.

Prepared JSON: `prepared/new_skill_3.json`. Source file: `backups/new_skill_3.original.json`. The UUID, ID, name, learning cost, activation conditions, and shell parameters have been preserved; only the timeline sequence has been modified.

1. Restart the game or use the `Rescan packs` option in VSB. Do not overwrite the new file by saving from an editor instance that still has the old version of the skill loaded.
2. Verify the **Improved Salamander** skill specifically—found within the **Sorc** pack—rather than its "B" variant.