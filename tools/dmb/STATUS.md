# Native compiler status — 8 October 2026

[DESIGN.md revision 5](DESIGN.md) governs this work. **Phase 0 remains open.** New disk-cache features are frozen. Phase 1 throughput acceptance, the resident daemon and later disk-cache acceptance are unfinished.

## Implemented and checked

- Commits `9d079bce60` and `067885825c`: finalize inherited class headers after authored members, preserve native subtype defaults and runtime override tokens, and derive known mouse callback flags from bound procedures. All 18 focused class checks and dmbc all-target Clippy pass. Real output comparison for these changes is pending; this is not a runtime parity result.
- Compiler l's captured run failed in header finalization after 38.17 s; no successful build timing is claimed. The finalizer incorrectly required ordinary class bindings for separately routed root/world records and retained engine classes. Routing is corrected with a full-finalizer regression; a new real output run is required.
- Compiler m (`17ec7425a8`) also failed before output publication, after 32.72 s, because `/savefile` intrinsic defaults use a separate writer route. This is the second failed header integration round: DESIGN §8's stop-loss is reached. Header finalization must share the member writer's exact routing contract before further retries. Evidence: `E:/dmb-native-v2-phase0/review-power-focus/native-retries/retry-9851f518661a4c358ab8857f4d5a9dc3/receipt.json` and `cold.trace.report.json`. Its partial-run CPU and memory observations are not successful compile benchmarks.
- Commits `1fc5b7da55`, `6b6c54504f`, `e2eeac5199`, `17ec7425a8`: contextual class routing diagnostics, shared borrowed bytecode validation, and earlier graph/capture releases. Focused checks passed: 13 bytecode/reference, five encoder, 19 class and 11 composition checks. All-target Clippy for the format, codegen and compiler packages passed; formatting and workspace source-size gates pass. Full output/runtime acceptance remains open.

- Detailed freeze instrumentation in compiler k failed the independent CPU check (covered/process interval 0.89984–0.93309) and added substantial measurement overhead. Its timings are rejected as performance evidence. Fine freeze spans now require `DMB_PROFILE_FREEZE_DETAIL=1`; normal tracing retains the broader measurements. Allocation observations identify owned decode validation as a substantial allocation source, but the fine CPU bounds cannot rank those stages reliably.

- Commit `83c1f30d9f`: bounded persistent ABI worker pool, reuse of captured resource demand, indexed missing-resource lookup, and same-thread interval-union CPU coverage.
- Commit `8d667228af`: release rich procedure IR after freezing, sorted branch-target validation, private-module cleanup throughout native crates, lexical proc-wide settings, parser fragment version 5, explicit `view(usr, 1)` source metadata, and a workspace source-size gate.
- The preceding full release suite passed **1,403 tests, zero failures** (`review-piecewise-split-workspace.log`). This count describes that snapshot.
- Current ABI/tree changes passed **371 targeted release tests, zero failures** and all-target Clippy with warnings denied (`review-abi-repair-targeted-final.log`, `review-abi-repair-clippy.log`). The earlier cleanup batch passed workspace/all-target Clippy. The repeated full suite was cancelled during reference-translator test compilation; it supplies no new pass result.
- Python profile/oracle regressions passed **35 tests** before the ABI repair. Formatting and diff whitespace checks pass.
- Every Rust workspace source, test, example and explicit audit target passes the 1,000-line source-size gate. Remaining format/reference/audit splits are applied and passed all-target Clippy plus 462 root-library tests. The proc-constructor classifier passed seven focused tests; asset digest reuse passed all 16 resource tests. Current workspace/all-target Clippy passed with warnings denied in `review-resource-digest-clippy.log`. These later checks use the development profile.

## Earlier accepted-clock audit

Frozen compiler f, commit `83c1f30d9f`, SHA256 `0053703bcc91cef14def7ca7d4da657a9aeb9ca937a675c954e4ef86006c599d`, release with LTO disabled, allocation counting, eight workers, no cache:

| Measurement | Single run |
| --- | ---: |
| Profiler wall | 52.0421 s |
| Harness child wall | 52.7230 s |
| Process CPU | 79.078125 s |
| Critical CPU uncertainty bounds | 35.1875–36.5 s |
| Covered CPU bounds | 75.390625–78.0625 s |
| Covered/process ratio bounds | 0.9533689–0.9871567 |
| Peak private memory | 3,219,111,936 bytes |

The entire ratio interval passes the independent 5% check; CPU quality reports no errors. Precise scalar conversion remains incomplete. This is usable **single-run uncertainty evidence**, not the required median baseline or Phase 1 acceptance. The fresh-output and diagnostic oracle passed. Evidence: `E:/dmb-native-v2-phase0/review-bounds-clock-audit-20261008-f/receipt.json` and `cold.trace.report.json`.

Largest maximum-thread CPU bounds: resources/maps 9.140625–9.203125 s; symbolic linking 7.640625–7.703125 s; procedure lowering 3.4375–3.5 s; initializers 2.921875–2.984375 s; composition 2.71875–2.78125 s; input scan 2.53125–2.59375 s; tree resolution 1.875–1.9375 s. Speed and memory remain above target. The later memory/ABI changes have not been benchmarked.

## Latest complete-source output and cold audit

Commit `8554b25773` preserves explicit proc/verb declarations versus implicit override paths. All 11 composition tests and targeted all-target Clippy pass. Frozen compiler j cleared the focused project twice in harness wall 44.8504 s and 45.1297 s at two workers; DMB/RSC bytes and normalized diagnostics match. The repaired global-vars table has the same full 1,198 physical paths as BYOND and exactly the same 1,148 `/proc/` namespace entries. The previous extra 50 entries caused unintended lifecycle/override calls during global initialization. The repaired pair has not yet run; a second bounded focused runtime comparison was requested after the one-pair allowance was used.

A separate eight-worker no-cache/no-daemon run of the **historic focused DeepQuarry project** (`ac1af55d1a`, captured `comparison.dme`) passed its fresh byte/diagnostic oracle:

| Measurement | Single run |
| --- | ---: |
| Compiler stage timer | 33.898 s |
| Profiler wall | 36.2511 s |
| Harness child wall | 36.8076 s |
| Process CPU | 65.53125 s |
| Critical CPU bounds | 26.546875–27.859375 s |
| CPU crosscheck ratio bounds | 0.9585122–0.9980925 |
| Peak private memory | 2,661,777,408 bytes |

CPU quality reports no errors; the entire ratio passes the independent 5% crosscheck. This is one run, a different frozen source scope from compiler f's earlier audit, and not an acceptance median or a measured before/after speedup. CPU and memory remain above Phase 1 targets. Evidence: `E:/dmb-native-v2-phase0/review-power-focus/native-retries/retry-e0a7ff07c0604b2c91cb0d18e3426063/`. No body-edit measurement on this complete snapshot exists yet.

## Focused runtime gate

The human authorized one bounded focused trusted-mode comparison after Rust/output checks, with no full runtime suite authorization. Both worlds completed one focused trusted replay; neither timed out or crashed. This is a single comparison, not full runtime parity.

The preserved source fixture compiled with BYOND 516.1687 in 222.2041 s (exit 0); native f failed in 17.5509 s on two `view(usr, 1)` source restrictions and a nested background setting. Pinned BYOND metadata confirms kind/radius 1/1 for both verbs and the proc-wide background flag on `beacon_locator/process`. These compiler admission failures are repaired in source. Frozen compiler g cleared all three ABI failures, then stopped at a proc/verb constructor initializer in 35.7522 s. Its separate source preflight took 264.4605 s; neither number is a performance acceptance result. Pinned BYOND bytecode pushes proc tag 0x26 followed by NEW, so the classifier now admits captured procedure identities without fabricating a class. That repair passed seven focused tests. Frozen compiler h includes the complete module splits and repairs; its captured-input retry cleared those errors and failed in 25.1862 s on lexical `__TYPE__` in the `MATERIAL_MIX` procedure-static initializer. Snapshot preflight took 0.4269 s. Pinned BYOND initializer bytecode supplies the declaring capacitor type to `dq_register_material_mix`, confirming that scalar evaluation must retain lexical owner context. Commit `45c56edb13` adds owner-aware scalar resolution with inherited lexical scope and authored shadow precedence. Four focused regressions and targeted all-target Clippy pass; its release build completed. Commit `4fc5bc8187` certifies only pinned `__TYPE__` namespace absence while preserving authored shadows and unknown-owner rejection. Frozen compiler i compiled the captured fixture twice: harness wall 44.8523 s and 42.9189 s, no timeout; DMB/RSC bytes and normalized diagnostics match. The pair was published. These runs are output checks, not CPU performance acceptance.

The prepared native-only retry verifies captured source/asset identities and the pinned BYOND pair. It runs two sequential native compilations, each bounded to 285 s, using snapshot replay to require matching DMB/RSC bytes and normalized diagnostics before publication. The runtime runner is trusted, hidden, port 0, one producer pair, with 180 s per world. Evidence and launchers: `E:/dmb-native-v2-phase0/review-power-focus/`.

The single focused replay completed normally on both: BYOND 87.4669 s / 63 per-test runtimes; native 134.2685 s / 181 per-test runtimes. Both failed `nuke_cinematic`. BYOND reproduced `power_bridge.dm:154` bounds errors; native also reports bounds errors but adds null-global and bad-index startup errors. Native global initialization enumeration reports expected 1148 versus actual 1198 procedures; this is under investigation. Evidence: `E:/dmb-native-v2-phase0/review-power-focus/runtime-i-comparison/replay-24ac662a21164d86b2c6579099570708/`. Commit `2b6e98e435` retains explicit runtime test attribution, unassigned events and separate temporal overlap; seven Python regressions pass. Historical `power_bridge.dm:154` runtime differences remain unresolved. PASS markers did not account for all runtime errors, and source-origin cooldown suppression is a known reporting mechanism, not a proven failing receiver/index. Absence of an error in one focused run will not establish full-suite parity.

## Required next work

1. Root-cause and repair the native-only global initialization/runtime differences from the completed focused pair. The authorized one-pair runtime allowance has been used; no full suite has run.
2. Verify fresh output from the complete source-size splits, relocation-binding optimization and asset digest reuse. All are applied and pass source/type/targeted test gates; their combined release output remains unchecked.
3. Measure the memory/link changes on the real captured project; obtain cold and body-edit traces and three-run CPU baselines, with the independent crosscheck unchanged.
4. Close normalized frozen runtime baseline evidence, retaining per-test errors, seeds and nondeterministic classifications.
5. Bring measured stages and memory within Phase 1 budgets, then implement the resident daemon. No-daemon disk-cache features remain frozen until those phases pass.

Earlier cohort narrative and rejected/contaminated timings are preserved in [the review evidence archive](archive/STATUS-20261008-review-evidence.md); structured benchmark records remain in `bench/results.jsonl` and `phase0/results.jsonl`.
