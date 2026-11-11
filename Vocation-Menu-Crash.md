# Vocation-menu crash diagnostics

The 2026-10-29 13:13:56 UTC REFramework dump is archived under `verification/vocation-menu-crash/initial/`. It records a native access violation (`0xc0000005`, read) at `DD2.exe + 0x562f6c9`. This identifies the fault location, not the originating mod. The bundled parser lists raw stack pointer candidates, not an unwound call stack.

The user reports that opening the menu with **Arbor Warden's Jerkin** can crash before or during vocation selection; removing it appears to avoid the crash. The installed `reframework/data/usercontent/bundles/Elf Origin - Arbor Garb.json` identifies that item as **31751**, `_StyleNo` **2155**. It uses an NPC clothing style according to that bundle's description. This is a useful suspect, not a confirmed cause. No armor, skill, native hook or save data is changed by this diagnostic setup.

The live REFramework configuration was changed through the running game's overlay, then saved and verified on disk. It enables:

- `ScriptRunner_LogToDisk=true`: Lua errors (the overlay labels this "Log Lua Errors to Disk").
- `LooseFileLoader_LogLooseFiles=true`: loose replacement file accesses.
- `LooseFileLoader_LogAccessedFiles=true`: file accesses for correlating the model/resource reload.

`FaultyFileDetector_Enabled=true` was already set and remains set. The original configuration is in `backups/vocation-menu-crash/re2_fw_config.txt`. The only three changed settings are listed above. File access logging is temporary and may grow large; disable both LooseFileLoader log settings again after reproducing the fault.

The flags are already active in the current session; no script reset was performed. A fresh game launch is useful if logging the entire initial model/resource load is needed. For a useful comparison, open the same menu several times with ordinary armor, then with the suspect jerkin, keeping other settings the same. If a crash recurs, collect immediately, before restarting the game, because ordinary logs are replaced on startup. A last-accessed resource is a lead, not proof that it caused the fault.

The current ScriptRunner overlay also reported `MeshModEnabler.lua:216: attempt to concatenate a nil value (field '?')`, inside its `UpdateBehavior` callback beginning at line 194. That line concatenates `e.Tops_styles[entry._TopsStyle]` into a configuration path without a nil check. The failing style ID was not logged, so this does not identify style 2155 as the trigger or establish the cause of the native crash. The source is archived with the initial evidence. It was not modified.

Run `verification/vocation-menu-crash/Collect-Crash.ps1` to copy the dump, logs, companion statuses, armor bundle and an autorun hash inventory into a new timestamped subfolder under `verification/vocation-menu-crash/captures/`. It changes no game files and does not upload anything. `capture.json` records original timestamps; an old dump must not be mistaken for the latest run's fault. The optional dump parser uses the bundled Python runtime.

To stop diagnostic logging, close the game and change only the three settings above back to their original values. Preserve any unrelated settings changed since the backup. No additional Lua tracer or native hooks are installed: the armor lead is investigated with REFramework's existing resource logging.
