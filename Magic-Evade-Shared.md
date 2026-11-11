# Magic Evade copies across vocations

The former companion accepted only pack `fh_sorc` and original skill UUID `3f67be32-a628-4ec1-8e8a-0f13b70725cc`. VSB Duplicate creates a new UUID. The Archer copy (`5b5b6312-1edd-4d8c-8af0-1f22f7ad403f`) therefore paid its VSB stamina cost without activating the companion's native buff handling.

Companion version 5 additionally accepts an explicit boolean marker in the skill JSON:

```json
"meta": {
  "fh_magic_evade": true
}
```

The original and `Magic Evade Archer` now have this marker. Duplicate either updated skill in VSB and select the desired vocation/menu as usual. VSB copies the metadata together with the hold scripts, so the companion needs no new UUID list or class-specific Lua code. Renaming or moving a marked copy to another pack also works. Previously created copies need the same marker once. Keep the existing `meta` fields when adding it.

The marker only identifies skills to the companion. A copy still needs Magic Evade's existing on_start/on_frame scripts and hold timeline to end on button release. It does not automatically turn an arbitrary skill into a held skill. Unmarked skills with unrelated UUIDs remain ignored; the original UUID is retained for backward compatibility.

## Installation

The current game files were updated from `prepared/magic-evade-shared/reframework/`. The bundle contains the shared autorun entry, bridge, unchanged native adapter, and both marked skill JSON files. Install this bundle for current shared behavior; the older `prepared/magic-evade-native/` folder is retained as the prior version.

Only the entry, bridge, and two skill JSON files changed in the live installation. Other JSON settings, UUIDs, costs, names, availability and scripts are preserved. The native buff adapter and its exact-instance expiry protection are unchanged. No VSB or DragonCore source was edited.

For a new installation, load the updated Lua with REFramework Reset scripts or restart the game. Rescan packs alone reloads JSON but leaves the older Lua companion in memory. Existing saved editor changes should be retained before resetting scripts.

## Verification

Run `verification/magic-evade-shared/verify.ps1`. It exercises the actual VSB executor, sandbox, event bus, schema, defaults and Duplicate implementation against simulated native SDK objects. Checks cover hold/release for all six inputs, interruption, cancellation, original UUID compatibility, actual Archer JSON, renamed copies across packs, exact boolean opt-in and inherited metadata. Native-only avoidance behavior was already confirmed by the user for the original skill; the Archer copy still needs a real attack/hold/release gameplay test.

`verification/magic-evade-shared/installation.json` records installed hashes and reload status. Activation events in `reframework/data/VSB/diagnostics/magic_evade_native_status.json` now include the skill UUID, ID and pack, so a test can be attributed to the correct copy.

## Rollback

Restore the four changed files from `backups/magic-evade-shared/` to their corresponding live paths and restart/reset scripts. The native adapter does not need restoration because it was not changed.
