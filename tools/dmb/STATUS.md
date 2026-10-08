# Native compiler status

Updated 8 October 2026. Binding plan: DESIGN.md revision 6.

## Measurements against the cold budgets

**No revision-6 acceptance cohort exists yet.** Earlier counting/LTO-disabled
figures are diagnostics, not acceptance measurements. No speedup is attributed
from runs in different windows.

Latest completed diagnostic: frozen compiler `58b6a3d51067`, eight workers, historical
DeepQuarry `ac1af55d1a` captured `comparison.dme`, no cache or daemon. Native DMB,
RSC and normalized diagnostics match an independent fresh native compile.
This is neither current-production-map evidence nor DreamMaker/runtime parity.

| Measure | Latest diagnostic | Revision-6 budget |
| --- | ---: | ---: |
| Critical-path CPU upper bound | 18.30 s median (diagnostic) | ≤ 15 s; ≤ 20 s needs trace reason |
| Total CPU | 33.87 s median (diagnostic) | ≤ 40 s |
| Peak private memory | 2.55 GB maximum | ≤ 1.5 GB |
| Bytes read | 1.623 GB | ≤ 400 MB plus cache population |
| Bytes written | 615 MB | ≤ 600 MB plus cache segments |
| Warm daemon body edit | Not measured | ≤ 1 s |
| Warm daemon structural edit | Not measured | ≤ 2.5 s |

The corrected thin-LTO/non-counting ABABAB cohort completed six runs. All fresh
oracles and structural checks passed; four CPU coverage intervals passed, two
failed. Profile-window wall median 18.87 s, range 16.99–21.39 s. End-to-end child
wall was overwritten by profile fields and is unavailable in this cohort; the
reporting bug is now fixed for future runs. No accepted baseline/noise floor.
Evidence: `E:/dmb-native-v2-phase0/r6-cohorts/self-profiler-20261008-165336/`.
53 measured threads add ±1.656 s uncertainty; A2 actual uncovered CPU was only
0.141 s. A shared-pool-before-gate exception is pending human decision.

## Correctness and implementation

| First structural traversal | Provisional discrepancies |
| --- | ---: |
| Type sets / headers / defaults | 10 / 1,949 / 4,230 |
| Procedure tables / flags / globals | 8,983 / 14 / 14 |
| Strings by use | 201,358 |
| Name-resolved bytecode | 1,636,088 |
| Other | 1,277 |

All six uncapped traversals completed with exact case signatures and anonymous
ownership pairing. Total differences: 1,853,923. Unsupported coverage is 126
fixed-word occurrences; unresolved typed-reference and anonymous pairing gaps
are gone after the mob/client repairs. Counts are differing fields/instruction
positions, not independent bugs. Structural measurement admission and subsequent
no-regression checks passed; semantic parity remains incomplete. Raw reports
remain in the cohort; summaries use authenticated references to avoid duplication.

Authored layer/luminosity and global procedure namespace
repairs have pinned static evidence; no repaired-output runtime rerun has run.
The recorded native global recursion and null-global errors came from calling
`New`, `Initialize` and variable-edit methods through the erroneous proc table.
The original `power_bridge.dm:154` behavioral difference remains unresolved.

The human deferred the full runtime baseline to Phase 5 and approved opening
Phase 1 after Phase 0 measurement and structural-diff gates complete (D36).
No new DreamDaemon or full runtime suite is running.
The edited-source private BYOND baseline compiled successfully in 119.2 s after
bounded four-worker staging (110.5 s). Native counting traces for cold and edited
source passed fresh-output and structural-tool checks. Child walls were 25.65 s
and 24.90 s; counting CPU is diagnostic only, never throughput acceptance or
warm incremental latency. Verified outputs and both diagnostic caches were removed.
Evidence: `E:/dmb-native-v2-phase0/r6-cohorts/allocations-20261008-172557/`.

Ten largest inclusive allocation spans in the cold counting trace (overlap;
do not sum these as heap ownership):

| Span | Allocated GB |
| --- | ---: |
| build | 6.26 |
| cold.procedure_lowering | 4.62 |
| frontend.declaration_parsing | 3.87 |
| request.compilation | 3.13 |
| lowering.fresh_codegen | 2.97 |
| frontend.fresh_declaration_facts | 2.08 |
| linking.freeze_artifacts | 1.69 |
| frontend.expansion | 1.59 |
| frontend | 1.57 |
| frontend.fragment_lookup_decode_parse | 1.44 |

The CLI uses a shared typed runner. Reusable engine/frontend ownership prototypes
are preserved but are not a daemon, do not eliminate frontend reassembly, and
are not the current performance task. Resident/cache work is paused. Whole
canonical linking and encoding remain intentional; text-keyed codegen and its
translation pass must be removed in Phase 1.

The earlier shared-runner batch passed 259 compiler library checks, 91
preprocessor unit checks, two integration checks, and all-target Clippy with
warnings denied. Current uncommitted changes passed 263 compiler library checks,
14 linker checks, 10 profiler unit checks and its artifact integration check,
plus all-target Clippy for those crates. Thirty-three benchmark protocol/provenance/NTFS retention checks pass.
The thin-LTO acceptance and separate counting binaries are frozen. The comparator
passed 478 library checks, including unmatched-procedure evidence, renumbering,
unknown-case multiplicity and malformed-reference regressions; all-target Clippy
passes. The release comparator is frozen. Latest profiler checks passed 13 unit
checks and its artifact integration check; current profiler/compiler Clippy passes.
Verified old output retention recovered 16.76 GiB; compacting duplicate evidence
recovered another 1.42 GiB. Human cleanup restored about 99 GiB free on E: and
67 GiB on C:; the disk-space blocker is cleared. Closed owned
hardlink cleanup is implemented in the cohort so immutable private outputs can
be disposed after their oracle passes. External/pinned links remain protected.

The full ordinary-profile workspace check now passes: 1,486 tests across 92
test/doc-test executions, zero failures or ignored tests. It includes the pinned
BYOND fixture comparisons. A stale analysis-export assertion was corrected to
expect proc-wide settings in lexical order, preserving its source-origin checks.
The first attempt reached its 600-second watchdog during fixture execution;
the completed rerun took 127.65 seconds including the affected rebuild.
This is not the separately required release-profile workspace result: that
Thin-LTO attempt was stopped during compilation before tests ran. Workspace
formatting passes; release-profile whole-workspace/all-target Clippy passes with
warnings denied (64.56 seconds).

## Next three actions

1. Resolve the pending shared-pool-before-gate decision; retain the strict 5%
   uncertainty check and rerun the pinned alternating cohort after its repair.
2. Retain the separate release-profile test requirement as open; preserve the
   completed ordinary workspace tests and whole-workspace Clippy evidence.
3. Open Phase 1 after authorization/gates: measure mimalloc alone, move bulk
   work onto one pool, emit symbol IDs directly and parse bodies once.

Structured evidence: `phase0/results.jsonl` and `bench/results.jsonl`.
Earlier narratives: [r5 close-out archive](archive/STATUS-r5-closeout.md).
