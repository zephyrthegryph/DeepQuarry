# Native compiler status

## Latest validated candidate — 8 October, shared worker pool

Phase 0 measurement and structural traversal gates are closed; Phase 1 is open
under the user's D36 decision. All six ABABAB self-comparison runs passed the
strict CPU interval cross-check, fresh DMB/RSC/diagnostic oracle and structural
no-regression checks. Phase 1 performance and memory targets still fail.

Eight-worker cold compilation, empty compiler cache, warmed captured inputs:

| Measurement | Six-run median | Range |
| --- | ---: | ---: |
| End-to-end compiler child wall | 20.93 s | 15.15–22.46 s |
| Critical-path CPU | 16.77 s | 13.00–18.19 s |
| Total process CPU | 35.85 s | 30.56–37.92 s |
| Peak private memory | 2.54 GB | 2.53–2.65 GB |

Self-comparison A/B median drift is 9.8% critical-path CPU and 8.0% wall;
changes smaller than that are not established speedups in this machine window.
The input warm-up (86.01 s) and structural/oracle harness work are outside child
compile wall. This is the pinned historical test-defined DeepQuarry fixture,
not a benchmark of current master or warm edits.
Evidence: `E:/dmb-native-v2-phase0/r6-cohorts/self-pool-20261008-193650/`.
Source archive: `042a29a6d88ac48bd9d274a91fff4a78281b36d446457281298e80a3377eed3c`.

## Implemented candidate awaiting output benchmark — 8 October, 20:43

Typed `SymRef` operands and numeric branch IDs now flow directly through lowering,
encoding and linking; exact binary string payloads share an interned roster.
The request-local body arena parses each issued body once and transfers it into
lowering. Parallel resources, directive preparation, type inventory, initializer
classification/code generation and canonical DMB table encoding use one borrowed
build executor. Initializer groups merge in source order; a single global group
and dependent constant/inheritance propagation remain sequential.

Immutable DMB/RSC owners compute their hashes during canonical serialization.
Publication consumes those certificates, avoids immediate staged-output rereads,
and preserves exact-input verification and authenticated resource reuse. UTF-8
input decoding reuses the authenticated byte allocation; conversion to the
current `Arc<str>` representation still copies. The opt-in heap census counts
retained body ASTs and output capacity; worker transient AST copies are excluded.

Validation: **1,445 ordinary workspace library tests passed**, zero failures;
release Clippy across workspace/all targets passed with warnings denied.
This does not claim the full release-profile workspace test gate. Earlier full
ordinary workspace runs found five obsolete typed-binding fixtures, now fixed;
all compiler libraries are green. No DreamDaemon or DM test runs were made.

Frozen source archive:
`848b95d470abb6ea37232ae997077dff0201944e4edf2ffcfdd7e1ba9fe240cc`.
The native method fixes now compile the complete captured DeepQuarry project.
The unoptimized diagnostic succeeded in 207.38 s; the frozen release diagnostic
with heap census succeeded in 32.56 s using the default worker stack. These are
successful output diagnostics, not accepted throughput comparisons. The new
ABABAB comparison is running against the previous accepted compiler. Its first
control run passed the fresh output oracle but failed stage-mapping accounting;
the independent CPU ratio bounds passed. Measurement admission remains failed
until that accounting issue is explained; no tolerances have been relaxed.

1,456 ordinary workspace library tests passed after the method/provider/publication
fixes (8 October, 21:43), and release all-target Clippy passed. New early-freeze,
capacity-compaction and shared-debug-path changes are implemented but await their
own validation; those changes are excluded from the frozen benchmark candidate.
The retained frontend census fell from 596.6 MiB to 557.5 MiB after macro-trace
compaction; process peak-memory improvement remains unmeasured.

Frozen candidate archive:
`f17e02dc6c0feac78151c77a5ac910f7654c5d2991c43d3f05e03fec437ca9b9`.
Compiler SHA-256:
`d734d632386c127ee457db74eb110657aecf5445c801cc27728dab1dcb4ef860`.
Evidence: `E:/dq-cache/dmb-native-v2/census-20261008-214351/` and
`E:/dmb-native-v2-phase0/r6-cohorts/compare-throughput-20261008-214351/`.
No accepted speedup or process-memory reduction is claimed yet.

Changed requests still reconstruct the frontend, scalar facts and linked image.
Disk procedure/expansion/map memos are present, but a retained daemon session
pipeline is not implemented. The accepted 20.93 s figure is a full build, not
an unchanged or minimal-edit measurement. Phase 2 edit targets remain open.

Updated 8 October 2026. Binding plan: DESIGN.md revision 6.

## Historical profiler-only measurements

At this historical checkpoint, no admitted revision-6 cohort existed. Earlier counting/LTO-disabled
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
0.141 s. The user authorized continued parallel implementation; the shared
pool exception was approved; the completed result is recorded above.

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

Shared-executor migration validation passes: 1,498 ordinary-profile workspace
tests in 154.37 seconds, zero failures/ignored tests; release-profile
whole-workspace/all-target Clippy passes (31.13 seconds), and formatting passes.
Focused release executor/profiler checks also passed before the final invalid-
worker-count regression was added; that regression passes in the full workspace.
Unsupported worker counts now fail before allocation or thread creation.
The acceptance candidate is being frozen for the whole-program comparison.

1. Finish validation of the shared build executor, authorized by the user's
   instruction to continue implementing on 8 October; rerun the pinned self
   cohort with the unchanged strict 5% uncertainty check. One pool now spans
   input preparation, expansion, parsing, startup, ABI, lowering and freezing.
2. Retain the separate release-profile test requirement as open; preserve the
   completed ordinary workspace tests and whole-workspace Clippy evidence.
3. After the measurement gate, measure mimalloc alone, move remaining main-thread
   bulk work, emit symbol IDs directly and retain startup parses for lowering.

Structured evidence: `phase0/results.jsonl` and `bench/results.jsonl`.
Earlier narratives: [r5 close-out archive](archive/STATUS-r5-closeout.md).

## 8 October: consuming procedure completion

The production worker now lowers, captures its memo receipt, and consumes each
procedure into its typed frozen contribution before returning. The coordinator
retains compact contributions rather than the whole rich instruction forest.
Required-type admission and modified-instance discovery use the same ordered
collectors as the compatibility path; source bindings and prepared initializer
sidecars are released or moved at their last use. Fresh CLI memo storage now
keeps disk publication/replay but skips request-local resident RichIR clones.

The full captured DeepQuarry diagnostic completed successfully in 205.58 seconds
using the unoptimized diagnostic binary and heap census. This is **not** an
acceptance speed measurement. Its DMB and RSC SHA-256 hashes match the previous
successful diagnostic exactly. Known retained container capacity at
`lowering.ready` fell from 1,114.8 MiB to 755.8 MiB, approximately 359 MiB less.
This census excludes allocator overhead and unknown backing; it is not peak RSS.

The first optimized A/B pair passed its fresh-output oracle but failed exact
stage-map coverage, so the cohort was stopped and its receipts preserved.
Per-binary pinned maps and self-comparison selection are repaired; 30 focused
Python harness checks pass. No new accepted speedup is claimed. The last accepted
full-project median remains 20.93 seconds on the captured historical project.

The final ordinary library run passed 1,466 checks in 89.91 seconds, with zero
failures or ignored checks. Release-profile whole-workspace/all-target Clippy
passes with warnings denied (133.49 seconds). Parallel final instruction
validation uses the shared executor with ordered error reduction. The narrow
debug-site accessor preserves macro/include/offset semantics without constructing
temporary include chains. These latest changes await frozen throughput evidence.
The retained daemon, structural-edit incremental pipeline, disk artifact replay,
runtime baseline and production readiness remain open. Phase 1 must close before
daemon or new disk-cache work resumes, as required by the review.
