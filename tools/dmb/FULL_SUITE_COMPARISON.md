# Full suite compiler comparison

Completed 2026-09-30 using the same frozen game source, identical runtime overlays, and BYOND 516.1687 DreamDaemon in trusted mode. These are two continuous full-suite runs, not aggregated focused runs.

## Results

| Result | Stock BYOND compiler | Rust compiler |
|---|---:|---:|
| Pass | 985 | 997 |
| Fail | **46** | **34** |
| Skip | 58 | 58 |
| Recorded tests | 1,089 | 1,089 |
| Runtime duration | 1,486.4 seconds | 1,471.0 seconds |

984 tests pass with both compilers, 33 fail with both, and 58 skip with both. Thirteen fail only with BYOND output; one fails only with Rust output. The results therefore do **not** establish full test-result parity.

## Coverage

Both DMBs expose exactly the same 1,113 `/datum/unit_test` subtypes. Frozen `RunUnitTest` intentionally omits 19 types under `/datum/unit_test/focus_only` and five abstract types:

- `/datum/unit_test/dq_constraint_parity`
- `/datum/unit_test/dq_damage_packet`
- `/datum/unit_test/dq_explosion_batch`
- `/datum/unit_test/dq_integrity_pool`
- `/datum/unit_test/dq_interaction_domain_snapshot`

The other 1,089 types all have fresh final JSON entries in each run. There are no unrun eligible tests, no conflicting duplicate results, no focused test selection, and no tier filter in this frozen runner.

## Rust-only failure

`/datum/unit_test/dq_damage_flavour_bands`: expected damage band 2 at 0.45 integrity, received 3 (`code/modules/unit_tests/dq_breakpoint_tests.dm:143`). BYOND passes. This is an assertion divergence requiring investigation; the full-suite result alone does not determine whether it is compiler semantics or accumulated game state.

A separate focused rerun of this test using the same two DMBs passes with both compilers: BYOND run `a6272e8b992d4d1bad22df675b916492`, Rust run `046a1f3f31cc40798ab0bee0733fbec4`. The focused test records 46 runtime errors with BYOND output and 10 with Rust output, so neither focused pass is runtime-clean. The full-suite divergence remains real but is not independently reproduced in isolation; accumulated state, test order, and timing need investigation. These focused runs do not replace or alter the full-suite totals above.

## BYOND-only failures

All thirteen BYOND-only failure messages contain game runtime errors. Their assertion/result difference is real, but fewer failed statuses do not by themselves prove the Rust output is more correct: runtime timing, suppression, and which active test owns background errors can differ.

- `/datum/unit_test/dq_constraint_declarations_compile`: Runtime in code/modules/power/power_bridge.dm,154: list index out of bounds.
- `/datum/unit_test/dq_covert_market_agent_integration`: Runtime in code/game/atoms_movable.dm,119: /mob/living/carbon/human still holds contents/latent entries entering Destroy() -- the destroy transaction's contents phase should have released them.
- `/datum/unit_test/dq_destroy_transaction_phase_timing_recorded`: Runtime in code/modules/unit_tests/dq_destroy_transaction_tests.dm,399: list index out of bounds.
- `/datum/unit_test/dq_expanded_department_outcomes`: Runtime in code/modules/power/power_bridge.dm,154: list index out of bounds.
- `/datum/unit_test/dq_idle_turret_wakes_for_nearby_mob`: Runtime in code/modules/power/power_bridge.dm,154: list index out of bounds.
- `/datum/unit_test/dq_lifecycle_sandbox`: Runtime in code/modules/unit_tests/dq_lifecycle_tests.dm,91: Cannot read null._active_timers.
- `/datum/unit_test/dq_power_idle_apc_and_smes_sleep`: Runtime in code/modules/power/power_bridge.dm,151: list index out of bounds.
- `/datum/unit_test/dq_radiation_insulated_movable_blocks`: Runtime in code/modules/power/power_bridge.dm,154: list index out of bounds.
- `/datum/unit_test/dq_real_canister_release_spreads_via_master_loop`: Runtime in code/modules/power/power_bridge.dm,154: list index out of bounds.
- `/datum/unit_test/dq_rule_thresholds`: Runtime in code/modules/power/power_bridge.dm,154: list index out of bounds.
- `/datum/unit_test/dq_rust_adjacency_matches_pairwise_rule`: Runtime in code/modules/power/power_bridge.dm,154: list index out of bounds.
- `/datum/unit_test/dq_state_latent_round_trip`: Runtime in code/datums/state/serializer.dm,41: Cannot read null.type.
- `/datum/unit_test/nuke_cinematic`: Runtime in code/modules/power/power_bridge.dm,154: list index out of bounds.

## Shared failures

Of the 34 Rust failures, 33 also fail with BYOND. Fifteen shared failures have byte-for-byte identical complete messages; another thirteen match after removing timestamps. Five have additional or different failure details:

- `/datum/unit_test/dq_constraint_parity/storage`
- `/datum/unit_test/dq_interaction_domain_snapshot/i7_bulk`
- `/datum/unit_test/dq_latent_closet_types`
- `/datum/unit_test/dq_latent_destroy_parity`
- `/datum/unit_test/dq_power_apc_cycle`

The storage sweep reports 56 mismatching cells of 559,101 with BYOND versus 55 of 559,922 with Rust. The other four differences involve extra/different runtime messages or the APC runtime-versus-assertion failure. Exact messages for every test are preserved in [the comparison CSV](results/full-suite-comparison-2026-09-30.csv).

## Runtime errors are independent of pass/fail

| Runtime measurement | BYOND output | Rust output |
|---|---:|---:|
| Errors recorded during tests | 2,583,214 | 2,564,329 |
| Tests recording errors | 600 | 613 |
| Passing tests recording errors | 561 | 586 |

Neither run is runtime-clean. A passing status means its assertions passed; it does not imply zero runtime errors. Counts are the game recorder’s per-test totals and do not include errors outside test ownership windows.

## Reproduction and snapshot

- Comparison ID: `dcd1b1f39fe14bd6a3ad65fd8d2bc1da`.
- BYOND runtime run ID: `6475a3d057ca4f5eabab43addc3dae04`.
- Rust runtime run ID: `8a6054fad0144a82b6456d651415ba16`.
- BYOND DMB: comparison snapshot `source-final/comparison.dmb`.
- Rust DMB generation: `2be3e35918c9bd4cc7f90b0ad9c71e55655e61f604584e60085d446fbdbc9fbc` under `rust-output-final/generations`.
- Rust compiler binary: `target/compiler-integration-fiftieth.exe`.
- Both runtimes had a 2 GiB memory ceiling and a one-hour time limit. Both produced final JSON and shut down; the runner returns failure because the suite contains failed tests.
- Raw JSON, full logs, frozen source and generated comparison JSON/CSV remain under the gitignored comparison/runtime directories in `target/`.

Both compilers used the same private source compatibility edits: the generated gas-mix-holder `get_temperature` override omits the `proc/` declaration qualifier, and the copied manifest defines the missing `VERB_CAT_OOC_RESOURCES` category as `OOC.Resources`. Runtime map-template substitutions are identical for both: the unavailable indestructible turf becomes simulated wall, and the unavailable test-room area becomes the test area. No emitted bytecode was patched.

These numbers describe the frozen comparison snapshot, not subsequent edits on active branches. Resource files and Verdigris were shared consistently between runs. Compile-time cache state differed, so compile durations are not a compiler-speed comparison.

Regenerate detailed reports with `dev-scripts/compare_test_results.py`, supplying each fresh `unit_tests.json`, `native-types.txt` as `--expected`, and `intentional-exclusions.txt` as `--exclusions`.
