# Engine layering batch, 2026-10-06

Branch: `codex/engine-layering-1006`, based on `origin/master` at `0add9783a0`.
Earlier completed branches were left untouched. Only this private branch is pushed.

## Completed production changes

- Pure move: `code/engine/library/spaces.dm` to `code/engine/parts/spaces.dm`, with the DME include updated in its own commit.
- Spaces, doors, containment-path reach and one-item var slots remain generic engine machinery. Content-specific size, cell, inventory and telekinesis implementations now live in `code/library/{items,machine,containers}`. The two-argument `rel_take` is correct: the slot is one movable in a holder variable, not a list.
- Actual engine-declared virtual hooks bridge ledger lookup, transfer, delivery and construction graph lookup to the existing downstream implementation. Unowned var-slot writes go through `op_write_key`, preserving generated setters and tracked notifications.
- Inbox held values and arguments use `/atom/movable`. Window/state references use `/datum`; window dispatch goes through a declared engine hook supplied by the tgui adapter. State is a declared reference, cleared when its target is deleted. The deliberate `usr` native-input shim is retained and documented. `lifeforms/input.dm` already had no `/obj/item` field to change.
- Message singleton/cache foundations moved into `code/engine/present/messages.dm`; typed rendering remains downstream. Lifeform placement, language and registry mirrors use actual engine hooks with exact downstream carriers.
- Shared mob-work policy moved to `code/library/jobs/mob_work.dm`; concrete species callback presets moved to `code/content/jobs/mob_work.dm`.
- Added 31 system accessors and replaced 35 private-read occurrences (33 counted B1 sites) in the profiler, round statistics, announcements, ghost options, mail and window spawner. Existing job API used for mail. Fractional supply rates and metrics are preserved.
- One existing kernel UI admin-rights check now uses `admin_can`, equivalent to its previous holder check; no permissions changed.

All new DM files are included; no generated output is committed. Debug/AI tracing is retained. One changelog stub is included.

## Ratchets

| Metric | Before | After | Reduction |
| --- | ---: | ---: | ---: |
| system_boundary B1 counted sites | 942 | 909 | 33 |
| system_boundary B3 counted sites | 81 | 81 | 0 |
| system_boundary total counted sites | 1023 | 990 | 33 |
| system_boundary baseline rows | 306 | 301 | 5 |
| check_grep admin-holder ceiling | 107 | 106 | 1 |
| check_grep periodic ceiling (existing headroom) | 27 | 26 | 1 |

The system baseline was regenerated with `analyze baseline --update --lint system_boundary`; it only shrank. The native check_grep updater also lowered the admin-holder ceiling and already-existing periodic headroom; no periodic site was edited. No ceiling was raised and no new ALLOW was added.

## G3: blocked; lint preserved as a pending patch

`tools/ci/pending_engine_layering.patch` contains the strict hard lint, semantic provenance indexes and 16 falsifiable Rust fixtures. It is **not enabled on this branch**: enabling it requires fixing protected framework dependencies first. No baseline, ceiling or ALLOW mechanism is provided. Generated caller paths alone are exempt in TOML; generated declarations do not authorize downstream types.

The prototype found 783 external-definition findings in the semantic sweep. A finding is a resolved dependency/definition pair, not necessarily a unique source line. These include foundational old-datum definitions as well as concrete content. The scope rule prevents reaching zero, for example:

- `code/engine/stats/store.dm:60` calls `om_time_of` defined in `code/datums/om/contribution.dm`.
- `code/engine/stats/recompute.dm:209` and `vars_write.dm:38` call `changed` defined under `code/datums/capabilities/`.
- `code/engine/stats/recompute.dm:217` resolves `status_flipped` in protected `code/library/mob/statuses.dm`.
- `code/engine/time/timers.dm` uses the old OM scheduler/record types and procs defined under `code/datums/om/`.
- `code/engine/actions/change.dm` calls legacy reaction and ownership helpers defined in `code/datums/`.

| Engine folder | Findings |
| --- | ---: |
| actions | 23 |
| declare | 81 |
| io | 2 |
| kernel | 71 |
| lifeforms | 13 |
| parts | 413 |
| present | 42 |
| stats | 12 |
| time | 126 |

The lint follows typed signatures/locals/fields, static calls, inherited methods, static callback proc references and macro-erased declaration markers. Built-ins are recognized from DreamMaker's exact builtin table. Real engine virtual declarations permit downstream overrides. Dynamic targets and untyped receiver chains without static provenance remain a limitation; this is not a blanket dynamic-call ban.

To resume G3 after ownership is assigned, apply the pending patch, build analyze with a private Cargo target, fix the findings without exemptions, and run `analyze check --lint engine_layering`. Do not enable it before zero.

## Verification

- Initial focused run: 13 passed, zero failed/skipped, clean boot.
- Final space/graph run: 6 passed, zero failed/skipped, clean boot; overlaps earlier tests.
- Final state-reference focused rerun: 2 passed, zero failed/skipped, clean boot; the deleted-state assertion passed.
- 16 focused Rust layering fixtures: all passed; no full Rust suite.
- DM focused compilation: zero errors; 28 pre-existing unused-variable warnings.
- `tools/build/build.sh lint`: passed, zero DreamChecker diagnostics, clean TypeScript/Biome and analyzer checks.
- Standalone `bash tools/ci/check_ratchets.sh`: passed, including generator checks.
- No full DM suite, shard run or E0 tier was run. Test runs were sequential.

The checked-in Windows focused wrapper calls `build.bat`; for these runs an ignored copy changed only that entry point to `build.sh` using system Bun, with the same explicit focused names. No tracked wrapper change was made. Logs are local under `data/codex-layering/`.

### Focused DM tests run

- `/datum/unit_test/dq_e1/graph_advance_undo_ledger`
- `/datum/unit_test/dq_engine_layering_actor_restore`
- `/datum/unit_test/dq_engine_layering_cell_delivery`
- `/datum/unit_test/dq_engine_layering_graph_protrusion`
- `/datum/unit_test/dq_engine_layering_movable_input_record`
- `/datum/unit_test/dq_engine_layering_size_requirement`
- `/datum/unit_test/dq_engine_layering_unowned_slot_setter`
- `/datum/unit_test/dq_engine_layering_window_dispatch`
- `/datum/unit_test/dq_gap/input_tk_is_a_provider_for_what_no_hand_reaches`
- `/datum/unit_test/dq_lifeform_contents`
- `/datum/unit_test/dq_lifeform_input`
- `/datum/unit_test/dq_lifeform_registry`
- `/datum/unit_test/dq_p1/cell_bay_takes_and_inserts_behind_the_cover`
- `/datum/unit_test/dq_p2_lib/present_outputs`
- `/datum/unit_test/dq_system_boundary_scalar_accessors`

### Protected system-boundary rows left for their owners

These exact baseline rows were not edited. Additional remaining contexts require individual review for protected declaration/OM forms; this is not a claim that every other row is safe to migrate.

```text
B1:code/datums/om/watch.dm:SSmachines 3
B1:code/game/machinery/computer/security.dm:SSjob 1
B1:code/game/machinery/computer/skills.dm:SScontracts 13
B1:code/game/machinery/computer/skills.dm:SSsupply 3
B1:code/game/machinery/computer/supply.dm:SSsupply 15
B1:code/game/machinery/computer/timeclock.dm:SSjob 4
B1:code/game/machinery/doors/airlock.dm:SSplanets 2
B1:code/game/machinery/embedded_controller/docking_program.dm:SSshuttles 3
B1:code/game/machinery/jukebox.dm:SSmedia_tracks 3
B1:code/game/machinery/nuclear_bomb.dm:SSticker 12
B1:code/game/machinery/seed_extractor.dm:SSplants 2
B1:code/game/machinery/status_display.dm:SSemergency_shuttle 1
B1:code/game/machinery/status_display.dm:SSsupply 1
B1:code/game/machinery/supply_display.dm:SSsupply 1
B1:code/modules/power/cable.dm:SSmachines 3
B1:code/modules/power/power_bridge.dm:SSmachines 1
B1:code/modules/power/power_grid.dm:SSmachines 14
B1:code/modules/power/solar.dm:SSplanets 3
B1:code/modules/power/solar_service.dm:SSplanets 3
B3:code/modules/power/power_bridge.dm:machines 4
```

## Filesystem limitation

Automatic approval review rejected removal of the now-empty `code/engine/library/` disk directory with “blocked by policy.” Its tracked file and include are gone; the empty directory was left alone.
