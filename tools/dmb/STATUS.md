# Native compiler status

Updated 8 October 2026. Binding plan: DESIGN.md revision 6.

## Measurements against the cold budgets

**No revision-6 acceptance cohort exists yet.** Earlier counting/LTO-disabled
figures are diagnostics, not acceptance measurements. No speedup is attributed
from runs in different windows.

Latest completed diagnostic: compiler `ca51f2809e`, eight workers, historical
DeepQuarry `ac1af55d1a` captured `comparison.dme`, no cache or daemon. Native DMB,
RSC and normalized diagnostics match an independent fresh native compile.
This is neither current-production-map evidence nor DreamMaker/runtime parity.

| Measure | Latest diagnostic | Revision-6 budget |
| --- | ---: | ---: |
| Critical-path CPU bounds | 22.31–23.63 s | ≤ 15 s; ≤ 20 s needs trace reason |
| Total CPU | 65.20 s | ≤ 40 s |
| Peak private memory | 2.33 GB | ≤ 1.5 GB |
| Bytes read | 1.623 GB | ≤ 400 MB plus cache population |
| Bytes written | 615 MB | ≤ 600 MB plus cache segments |
| Warm daemon body edit | Not measured | ≤ 1 s |
| Warm daemon structural edit | Not measured | ≤ 2.5 s |

Diagnostic child wall and fresh-oracle wall were 31.71 s and 33.52 s.
Wall times are context, not acceptance. Evidence:
`E:/dmb-native-v2-phase0/review-power-focus/native-retries/retry-5d7da6c779ba40d5a2b318d76094b325/`.
The earlier three-run diagnostic median was 38.57 s wall, 65.56 s total CPU,
24.47–25.78 s critical CPU bounds, and 2.34 GB maximum private memory.

## Correctness and implementation

| First structural traversal | Provisional discrepancies |
| --- | ---: |
| Type sets / headers / defaults | 10 / 1,949 / 4,230 |
| Procedure tables / flags / globals | 8,140 / 14 / 14 |
| Strings by use | 201,358 |
| Name-resolved bytecode | 1,644,134 |
| Other | 1,390 |

The latest uncapped traversal completed with exact case signatures and anonymous
ownership pairing. Unsupported coverage is 775 fixed-word occurrences and 3,329
unresolved typed references in the older counting output. Anonymous pairing now
has no uncovered occurrences. Counts are differing fields/instruction positions,
not independent semantic bugs. Evidence:
`E:/dmb-native-v2-phase0/review-power-focus/structural-s-r6-complete-traversal.json`.
Certified mob-table and client-singleton reference repairs passed their library
checks; the rebuilt project has not yet been compared. This is not a passed gate.

Authored layer/luminosity and global procedure namespace
repairs have pinned static evidence; no repaired-output runtime rerun has run.
The recorded native global recursion and null-global errors came from calling
`New`, `Initialize` and variable-edit methods through the erroneous proc table.
The original `power_bridge.dm:154` behavioral difference remains unresolved.

The human deferred the full runtime baseline to Phase 5 and approved opening
Phase 1 after Phase 0 measurement and structural-diff gates complete (D36).
No new DreamDaemon or full runtime suite is running.
The edited-source cold-trace protocol is implemented; it still needs a BYOND
baseline pinned to the edited journal. It does not measure warm incremental latency.

The CLI uses a shared typed runner. Reusable engine/frontend ownership prototypes
are preserved but are not a daemon, do not eliminate frontend reassembly, and
are not the current performance task. Resident/cache work is paused. Whole
canonical linking and encoding remain intentional; text-keyed codegen and its
translation pass must be removed in Phase 1.

The last verified committed batch passed 259 compiler library checks, 91
preprocessor unit checks, two integration checks, and all-target Clippy with
warnings denied. Current uncommitted changes passed 263 compiler library checks,
14 linker checks, 10 profiler unit checks and its artifact integration check,
plus all-target Clippy for those crates. Seventeen benchmark protocol/provenance checks pass.
The thin-LTO acceptance and separate counting binaries are frozen. The comparator
passed 478 library checks, including unmatched-procedure evidence, renumbering,
unknown-case multiplicity and malformed-reference regressions. The r6 self-comparison stopped at the free-space preflight before compiling; it produced
no timing rows. Verified old output copies and traces freed 10.45 GiB, but
concurrent disk growth put E: below the 25 GiB floor again. Verified disposable
artifact cleanup is exhausted; additional disk space is requested.

## Next three actions

1. Complete revision-6 measurement: thin-LTO release/mimalloc without counting,
   stage thread CPU with complete main-thread coverage, warmed alternating
   self-comparison, 600 s watchdog, free-space and evidence retention rules.
2. Produce the uncapped pinned DreamMaker structural diff and record every
   category count, explanations and unsupported coverage; run it with benchmarks.
3. Report Phase 0 results, then open authorized Phase 1: measure mimalloc alone,
   move bulk work onto one pool, emit symbol IDs directly and parse bodies once.

Structured evidence: `phase0/results.jsonl` and `bench/results.jsonl`.
Earlier narratives: [r5 close-out archive](archive/STATUS-r5-closeout.md).
