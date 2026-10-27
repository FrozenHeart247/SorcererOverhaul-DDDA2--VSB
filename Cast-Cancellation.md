# Canceling a Custom Spell

A trial adjustment dated October 27, 2026, for *Fire Ground* / *Molten Ground* and *Lightning Strike* / *Lightning Burst*.

## Why the Delay Occurred

While the game’s internal cancellation mechanism would interrupt the animation, the VSB (Visual Skill System) `wait_until` function would continue waiting for the *Cast* phase to complete. Since the system allows only one active skill per character, any subsequent attempt to use a skill would trigger an "already using a skill" error, persisting until a 600-frame window had elapsed.

The current VSB configuration is set to interrupt a skill only upon taking a hit or death, rather than upon any transition to a different action. Simply enabling `interrupt.cancel_on_other_action` is not a viable solution here: the game engine itself initiates the *Ready* and *Cast* phases, and the system might mistakenly interpret a standard, intended progression as an external interruption. Furthermore, this setting is explicitly designed to ignore transitions back to neutral (idle) states.

## The Change

A `scripts.on_frame` block has been added to the existing JSON definitions for both skills. All existing nodes, shell settings, coordinates, IDs, and levels remain unchanged.

The handler monitors both action layers, tracking actions associated with the `Salamander` or `Levin` families:

- Actions such as *Prepare*, *Ready*, *Ready…SpellStock*, *Cast*, and others within the same family keep the skill active.
- If, following the initiation of a spell, both layers transition out of this family and an action containing "cancel" in its name is detected, the timeline is terminated immediately during that update.
- For other types of transitions—such as moving into *Strafe* or *UpperBodyDefault*—a 0.10-second grace period is applied, after which `skill.finish()` is called to release the VSB executor.
- At the start of a skill, there is a 0.25-second grace period to account for asynchronous action requests. This also prevents a "cancel" action—left over from a previous skill—from interfering with a new cast attempt.
- If data for one of the layers is missing, it is not interpreted as a confirmed cancellation. The original time-out remains as a fallback.

The handler terminates only the VSB timeline. A Wight that has already been spawned remains under the standard control of the shell; no command to remove previously spawned effects has been added.

The specific action triggered by the cancel button in the current gameplay state has not yet been explicitly cleared. A separate check for exiting the skill family handles the transition back to standard, neutral actions. The actual behavior must be verified in-game.

## Verification

After performing a "Rescan packs" or restarting the game:

1. Begin the preparation phase, cancel it using the standard in-game command, and then activate the same skill again.
2. For "Lightning," repeat the cancellation after the Wight appears, but before "Thunder Rain" is cast.
3. Ensure that the full, standard casting sequence for both spells functions as expected.

When exiting the sequence normally, the wait time should be reduced to a short interval—approximately 0.1 seconds plus one update step—instead of the previous duration of up to 10 seconds. If the lock persists, the next step is to examine the active actions on layers 0 and 1 immediately following the cancellation; one of them may still be retaining the spell family name.

## Files and Rollback

Game files: `reframework/data/VSB/packs/fh_sorc/skills/new_skill_3.json` and `new_skill_4.json`.

Backups taken immediately prior to this change are located in `backups/cancel-fix/`. These contain your current user settings, including the positioning of the "Fire Ground" shell. To roll back, copy these files over the corresponding game JSON files while the game is closed.

Handler template: `prepared/cancel-guard.template.lua`. In the provided JSON files, all code is embedded within `scripts.on_frame`; there is no need to load the template into the game separately. This does not involve any modifications to the mod's Lua execution engine. Automated verification: `verification/cancel-fix/verify.ps1`, with results in `verification/cancel-fix/results.txt`. This process utilizes the actual, installed executor, scripting, sandbox, schema, and node handlers, while simulating in-game actions and the passage of time. A total of 44 checks were performed, covering: reproduction of the original lock-up, re-execution following a cancellation, both levels of both skills, standard shell release, intervals between actions, asynchronous startup, handling of missing data, impact events, and the initial timeout. This is not an in-game test.