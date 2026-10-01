# Full DM test suite — 2026-09-28

The translated test world and paired native reference both completed the full
unfiltered suite in trusted mode. **The translated suite is not passing.**

| Result | Native | Translated |
| --- | ---: | ---: |
| Passed | 991 | 982 |
| Failed | 25 | 34 |
| Skipped | 58 | 58 |
| Recorded results | 1,074 | 1,074 |

Both runners enumerate 1,098 test types. The standard runner excludes 24 abstract
or focus-only types before recording results. The 58 skips are the runner's
existing map/disabled-feature skips; no focus filter or shard was applied.
There are no missing or extra translated result keys. Both worlds shut down
after the suite; neither writes the clean-run marker.

## Differences requiring investigation

Fourteen tests pass native and fail translated:

- `dq_air_alarm_receives_matching_status`
- `dq_air_alarm_skips_unchanged_air`
- `dq_blocked_airlock_wakes_from_blocker_movement`
- `dq_closed_airlock_clears_stale_autoclose`
- `dq_combat_ai_spatial_sleep_wakes`
- `dq_damage_flavour_bands`
- `dq_idle_auxiliary_machines_hibernate`
- `dq_idle_meter_and_fire_alarm_hibernate`
- `dq_integrity_pool/mech_packet`
- `dq_latent_light_emergency`
- `dq_latent_light_parts`
- `dq_rare_case_report_workflow`
- `dq_reactor_probe_watches`
- `dq_state_latent_round_trip`

Five fail native and pass translated:

- `dq_contract_sustained_evidence`
- `dq_gas_dependencies_wake_exact_devices`
- `dq_h3_hotspot_heats_items`
- `dq_reactor_clear_on_destroy`
- `dq_shuttle_repeated_moves_preserve_air`

Twenty failures are shared. Test order differs between the two runs. Several
changed results include the shared power-facade runtime being attributed to
different currently running tests. Other differences are direct assertions.
These observations do not establish which changes are compiler defects versus
order, state, or timing effects; focused paired reproduction remains necessary.

The final runtime-log comparison reports zero translated-only error identities.
The interim food-replicator division-by-zero difference was also reached by
native later in its test order. Total reported world runtimes are 1,398 native
and 1,373 translated; fewer reports do not establish better correctness.

## Build and execution evidence

This uses the same frozen source snapshot and matching Verdigris dependency as
the validated translated server, not the changing main checkout:
`C:/Users/bmene/.codex/worktrees/dmb-format/CHOMPStation2`.

The compiler overlay defines `CBT`, `CIBUILDING`, and `CITESTING`, selects the
Virgo minitest map, and retains native conditional branches. Both compilers see
the same previously documented legal compatibility overlay. Native compilation
reports zero errors and five warnings; OpenDream reports zero errors and 202
warnings. All 61,246 emitted procedures decode, with zero reserved instructions
or failures. Expanded metadata comparison reports zero differences. These static
checks do not explain or dismiss the changed test outcomes.

Both console servers use `-trusted -invisible -params log-directory=ci`, with
independent data/config directories and matching dependency DLLs. Input hashes,
build options, and output hashes are recorded in the provenance file.

Translated DMB SHA256:
`8BCBEDB25DD7987F2395933B5699E5547DCD4391B0255D7B332347ED5D43C349`.

Evidence under `D:/opendream-diagnostic/dm-tests/`:

- `test-comparison.json`: complete counts, changed statuses, and failed assertions.
- `runtime-comparison.json`: shared and unique runtime error identities.
- `native/data/unit_tests.json` and `translated/data/unit_tests.json`: raw results.
- `native/server.log` and `translated/server.log`: complete console logs.
- `provenance.json`: exact inputs/options/hashes.
- `metadata.txt` and `opcode-audit.txt`: static checks.

`scripts/compare-dm-tests.py` exits nonzero for translated failures or missing/extra
result keys. Runtime-error identity comparison alone is insufficient to certify
the suite: the assertions above differ despite zero translated-only identities.
