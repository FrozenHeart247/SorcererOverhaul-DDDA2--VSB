# Lightning Ball / Elemental Orb: Amaterasu sphere

The live skill is `reframework/data/VSB/packs/fh_sorc/skills/new_skill_5.json`, UUID `a7b6261c-d143-4b8a-a270-ba457717e7c2`.

Its base node `n4` already selected `AppSystem/Shell/UserData/HumanShellParamData_Job08.user`, shell **45** (Amaterasu Magic Sphere Air Activated Shell, Burning), with `lifetime: 5`. However, the level-2 patch still replaced that node's file and ID with `ch227001DarkAreaShellParamData.user #1`. The fix changes only those two level-2 override values. Level 1 keeps `n4` disabled; level 2 enables it at frame 60. Costs, other nodes, UUID and timings are preserved.

The editor's ordinary **Test** deliberately uses `shellopts.plain(node)`, which strips lifetime and other modifiers. **Test with this node's settings** preserves them. The user confirmed using ordinary Test initially.

An in-game node-settings test then demonstrated a second problem: the Amaterasu effect still persisted at 15.48 seconds despite lifetime 5. DragonCore temporarily writes the native `ShellBaseParam` lifetime, but its independent cleanup previously checked only the global cap (120 seconds by default).

`DragonCore/game/shells.lua` now also checks the positive `r.node.lifetime` in the existing cleanup path. This gives the tracked spawn and its tracked children a maximum duration measured from the spawn request. The earlier of the node duration and global cap wins. Zero or omitted lifetime keeps the old behavior. Natural early termination is still allowed; keep-alive does not extend past the cap. This applies to all tracked shells with an explicit positive lifetime, rather than hardcoding five seconds or the Amaterasu ID. No new native hook or continuous logging is added.

## Installation and verification

The two changed live files are copied under `prepared/lightning-ball-amaterasu/reframework/`; original files are under `backups/lightning-ball-amaterasu/`. JSON packs were rescanned, then REFramework **Reset scripts** loaded the updated tracker.

`verification/lightning-ball-amaterasu/variant-check.txt` records validation with the actual installed VSB level-patching and schema code. Both variants validate without warnings, and level 2 passes `UseLifeTime=true, LifeTime=5` to the shell override path. `verify-tracker.lua` exercises the real original/prepared tracker against simulated SDK objects: 13 checks passed, including root/child cleanup, early native finish, global cap precedence, keep-alive and zero/unset duration.

After loading the fix in the game, a full level-2 editor Test cast completed. A separate **Test with this node's settings** showed the orange Amaterasu effect at 1.737 seconds and its absence at 10.488 seconds without manual destruction. This confirms real cleanup, but the screenshots do not measure the exact disappearance frame; the five-second boundary is checked by the tracker tests. A normal gameplay-button cast was not separately exercised.

Installed hashes and reload/test details are recorded in `verification/lightning-ball-amaterasu/installation.json`. A future DragonCore update may overwrite the tracker fix.

## Rollback

Restore the backed-up `new_skill_5.json` and `shells.lua` to their corresponding game paths and reset/restart Lua. Preserve any subsequent user edits when restoring.
