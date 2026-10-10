## 2026-10-10 current integration and measured limits

Committed through `2ec3cac345`: shared declaration receipts, immutable cache age eviction, one streamed cache publication per completed request, buffered structural reports, and numeric metadata pressure release. The current workspace/all-target check passes. Shared frozen-frame ownership, an intermediate compiler-artifact pressure tier, frontend stage telemetry, and three captured BYOND default/header corrections are undergoing focused checks; they are not represented by a measured compiler yet.

Latest partial prototype cohort: `607e2c961f`, dmbc optimization level zero, two workers, captured DeepQuarry `ac1af55d1a`.

| Request | Retained end-to-end seconds | Independent fresh seconds |
| --- | ---: | ---: |
| Initial cache population | 83.371 | 36.741 |
| Unchanged | 1.941 | 38.030 |
| Procedure body edit | 65.849 | 38.520 |

All three completed rows match fresh native DMB/RSC bytes. New-procedure children completed in 64.392/36.887 seconds and their pair hashes were checked equal afterward, but the row was not admitted: its structural inspector failed with Windows disk-full error 112. Remaining edit cases did not run. The owned daemon was reaped. This is a partial prototype cohort, not optimized performance or BYOND correctness acceptance. Evidence: `bench/receipts/phase2-20261010-shared-leaf-iteration.json`.

The body request rebuilt the semantic tree after whole-session memory-pressure eviction; tree resolution alone took 10.590 seconds. The intermediate pressure tier retains that exact semantic owner while releasing compiler artifacts. Whether it stays below the unchanged 4 GB daemon limit remains unmeasured. Initializer assembly, canonical projection and output work remain substantial. BYOND structural comparison still reports 1,858,610 unexplained differences and incomplete semantic coverage. Runtime parity remains deferred to Phase 5; compile-error parity, history replay, six-worktree acceptance and production readiness remain open. No complete migration or speedup claim.

## 2026-10-09 current migration integration (unmeasured)

Work continues beyond the d65 prototype cohort. Compact frozen disk replay now includes argument-source helper procedures with current ABI/origin/licensing checks. Retained type reachability has exact field-request and parent-index contributions. First pressure cleanup preserves symbolic dependency receipts while releasing rich, numeric-image and runtime-AST buffers. Canonical initializer roster hits preserve current diagnostic ordinals.

Focused checks passed for compact main/helper replay (3), checked frozen restoration (3), scalar receipts (6), shared producer ownership (1), headers (12), required types (5), initializer classification (8), engine qualification (3), pressure owner preservation (1), assembly (3), host catalog (1), and bound images (3). The final combined workspace/all-target compile check passed in 15.24 seconds. These are focused integration checks, not runtime parity or performance acceptance. Owner metadata checks exposed real pruning before member installation; the correction and inherited name-specific receipts passed all 5 focused checks, including cyclic parent decline. Analysis queries use an immutable facts completion carrier; both coordinate and cache-publication focused checks passed.

No timings below represent these uncommitted changes. The last measured body/new-procedure requests remain 61.43/62.96 seconds in an unoptimized prototype; fresh native byte parity was passed, BYOND structural/runtime gates remain open. No readiness or completion claim.

# Native compiler status

## Latest measured cohort (2026-10-09, d65d5e8c59)

Frozen prototype compiler (dmbc opt-level 0, two workers): initial retained/cache-populating build 82.117 s; independently fresh cold 39.753 s; unchanged 1.641 s; body edit 61.435 s; new procedure 62.961 s. All four DMB/RSC pairs are byte-identical to independently fresh native builds. These are not release-profile acceptance measurements.

The memory-pressure artifact tier deleted symbolic procedure records: the edited request kept session/engine identity and policy but had a new procedure generation and 48,681 absent symbolic records. Source fixes now preserve compact receipts and release rich/numeric buffers first; those fixes are not in this measured binary. BYOND structural comparison remains open (1,834,121 unexplained raw discrepancies, incomplete semantic coverage), and the full runtime baseline stays deferred. Six-worktree acceptance remains unrun.

Receipt: ench/receipts/phase2-20261009-qualified-owner-prototype.json. New header/ancestry/scalar/classification/disk migration source is awaiting combined gates and new measurements.

Updated 9 October 2026. Binding plan: DESIGN.md revision 6.

## Current migration checkpoint (9 October, evening)

The shared retained pipeline is implemented, with remaining global projection,
validation and publication work. It is not fully incremental or production ready.
`phase0/migration_checkpoint_20261009.json` distinguishes focused gates,
experimental timings and open acceptance gates.

The latest completed real retained/fresh cohort used immutable commit `d889b0cac1`
with the main compiler crate at optimization level zero, two workers, and captured
historical DeepQuarry source. This is not a release acceptance cohort.

| Request | Retained end-to-end seconds | Independent fresh seconds |
| --- | ---: | ---: |
| Initial | 86.801 | 46.965 |
| Unchanged | 1.649 | 41.878 |
| Procedure body edit | 69.485 | 44.075 |
| New global procedure | 65.672 | 38.217 |

All eight recorded cases, including declaration/default/resource edits, matched
fresh native DMB and RSC hashes. Retained edits were slower than fresh builds;
the cause has not yet been established. New lifecycle and symbolic decline counters
distinguish policy replacement, idle eviction and semantic rebind misses.
Evidence: `E:/dq-cache/dmb-native-iterations/20261009-200314-60477533/receipt.json`.

Committed `d99017db7a` fixes absolute-header declaration effects, repeated
`#pragma multiple` preprocessing, frame frontier reuse and native format-library
dependencies. Its immutable prototype executable built within the 300-second
watchdog. Compile-only oracle checks then exposed actual outstanding bugs:
Global operands used footer slots instead of variable-record IDs; reserved
constructor classification still dropped initializer markers; method membership
used an inappropriate ordering. Those fixes and exact hierarchy/callable dependency
certificates are in the next validation batch. No improved timings are claimed yet.

Whole-program BYOND structural coverage, compile-error parity, real six-worktree
concurrency, history replay and Phase 5 runtime parity remain open. The 126 unknown
Input middle operands remain explicitly uncovered. Full runtime testing remains
deferred to Phase 5.

## Earlier migration checkpoint

The latest completed matched cold cohort is `be11683d0b`, not the older cohort
below. Against its matched control, launch/reap median was **15.346 s versus
13.820 s**; total CPU was 32.391 s versus 32.547 s, and peak private bytes were
1,554,059,264 versus 1,595,318,272. Read/write bytes were 326,324,811 /
569,627,733. Wall time regressed about 11%; this is not an optimization win.
Evidence: `E:/dmb-native-v2-phase0/r6-cohorts/matched-gzip-20261009-085609-fb0c242d/comparison.json`.
The human has prioritized finishing migration and correctness over further cold
microtuning. These measurements exclude the subsequent retained-session work.

Committed through `1268ec23c1`: native daemon/CLI dispatch, build-system compiler
selection and fallback, resolved analysis query export, shared retained artifact
ownership, initializer classification reuse and embedded default engine data.
An owned tiny daemon smoke passed nine checks, including byte equality against a
fresh local compile, source-error propagation and repeat compilation. Its 7.805 s
batch duration is **not a DeepQuarry benchmark**. Evidence:
`E:/dq-cache/dmb-daemon-smoke/20261009-100001-ef381fcb/report.json`.

The next source batch adds retained declaration contributions, relative startup
plans with fresh current-source issuance, per-procedure ABI artifacts, modifier
facts and independently reusable initializer assignment continuations. Modified
objects retain canonical descriptor/path recipes and reissue from the current
typed expression; old AST owners are stripped before admission. Debug-disabled
and current group-ordinal fixtures pass, and debug mode is an explicit key input.
Stable-roster field metadata edits now recalculate changed members and inheritance
dependants using the same resolver as a full build. ABI producer errors retain
explicit source/unsupported/invariant categories through dependent overrides.

Latest locked all-target check passed in 25.97 s. The focused migration gate
passed 20 intended dmbc cases (3m52s compilation, under one second execution),
five semantic-tree differential cases and twelve ABI cases. The initializer
producer's separate fifteen-case check passed, including independent whole-group
comparisons. Earlier checks caught and repaired stale startup offsets, missing
fixture resolver coverage and debug-disabled modifier retention. Shared artifact
storage checks pass nine cases; three startup cases pass after correction.
Receipt: `E:/dq-cache/dmb-native-v2/migration-fragments-focused-20261009.json`.
The updated binary and daemon edit/concurrency smoke are still pending. Four
unhooked shared AST visitor/analysis children are drafts, not implemented exports.

Remaining limits: additions, removals and parent edits still rebuild the semantic tree; current
roster assembly and portions of startup/ABI inventory still run on each request.
Stable metadata updates still scan the roster, copy the flat member array and
issue fresh occurrences. The new reverse metadata dependency graph is not yet
included in the opt-in retained declaration payload census; that census is not
a total retained-heap measurement. Initializer error typing and exact diagnostic
positions remain incomplete.
There are no new real DeepQuarry daemon/body/structural timings yet. The tiny
six-manifest smoke is not the six real worktree acceptance gate. The recorded
BYOND structural baseline still has 1,853,923 differences and 126 uncovered fixed
words. Runtime parity, including the historical power-bridge discrepancy, remains
unresolved and deferred to Phase 5. This compiler is not declared production ready.

## Latest matched cold cohort (prepared-source snapshot)

The compressed-trace ABABAB cohort for commit `64d40464a9` completed with
three measured runs per compiler, eight workers and the captured historical
DeepQuarry project `ac1af55d`. All six runs passed measurement admission,
native fresh-output/diagnostic equality and structural no-regression.

| Median | Control | Candidate |
| --- | ---: | ---: |
| Child wall | 11.790 s | 12.498 s |
| Critical CPU point | 9.422 s | 9.578 s |
| Critical CPU upper | 11.484 s | 11.703 s |
| Total CPU | 30.250 s | 30.875 s |
| Peak private bytes | 2,198,388,736 | 1,569,341,440 |
| Read bytes | 550,004,461 | 326,324,811 |
| Written bytes | 568,844,338 | 569,274,453 |

This is a 28.6% memory reduction against this control, not a CPU improvement:
candidate wall is 6.0% higher and total CPU 2.1% higher. It is not a paired
comparison against the previous optimized candidate. Memory, input,
resources/maps, ABI/initializers and composition/publication gates remain open.
Candidate byte budgets fit, but the I/O gate remains not evaluable because
blocked-I/O timing is unavailable. Full release tests were not completed before
the cohort; the separate release gate against that immutable candidate
closed at the 1,200 s compilation watchdog without test execution. This cohort excludes the later startup forwarding, borrowed
initializer assignments, transient output/debug roster and parallel path fixes.

Evidence: `E:/dmb-native-v2-phase0/r6-cohorts/matched-gzip-20261009-054556-be4e68dd/comparison.json`.
A separate precondition audit records the stale preparation wording and unrelated
user Cargo activity during sequential builds without modifying frozen receipts:
`E:/dq-cache/dmb-native-v2/matched-gzip-precondition-audit-20261009-054556-be4e68dd-20261009-060514.json`.
BYOND behavioral parity and retained incremental sessions remain unfinished.

## Compact prepared-source candidate

Commit `64d40464a9` stores prepared logical lines in 40-byte checked records
instead of 56-byte records, with an exact wide fallback. Directive planning,
memo replay and source consumers use borrowed immutable range views. Construction
fills the compact backing directly; no full-width intermediate vector remains.
The expected 16 bytes per logical line saving is not a measured private-memory
result. This owner is released after frontend construction.

Ordinary library checks passed 1,586 tests across 15 targets, with zero failures
or ignored tests, in 126.636 s including compilation. Release all-target Clippy
passed in 23.113 s. Evidence: `E:/dq-cache/dmb-native-v2/r6-workspace-tests-20261009-054253-701960af.json`
and `E:/dq-cache/dmb-native-v2/r6-workspace-tests-20261009-053541-ce9c96db.json`.
The exact committed candidate is frozen for a matched compressed-trace cohort:
`E:/dq-cache/dmb-native-v2/matched-gzip-preparation-20261009-054556-be4e68dd.json`.
No timing or acceptance improvement is claimed before this cohort completes.
Later transient region-output changes are excluded from that snapshot.

## Compact provenance and single-codec candidate

Expanded origin storage now uses 32-byte indexed records instead of 72-byte
records, with exact shared path/trace owners and a full usize fallback. Frontend,
analysis, diagnostics and census consumers use borrowed views rather than a
reconstructed Vec. At the older census cardinality this is about 42 MB of record
backing saved before index overhead; private-memory savings are not measured yet.
Immutable current-image origin certificates also use exact-size boxed backing.

Initializer bytes and streamed hashing now share one emission codec, including
nested expressions and arrays. Constant-time expression lengths avoid repeated
token walks. Independent legacy-byte fixtures cover optional fields, targets and
array framing. Optional profiler domain evidence receives the exact authenticated
benchmark stage map and exports its selectors; original acceptance metrics are
unchanged. Input preparation now reports read and lexical preparation separately
under the existing input stage, to identify its remaining CPU cost.

Ordinary workspace library checks passed **1,584 tests across 15 targets**, zero
failures/ignored, in 224.867 s including compilation. Final release workspace
all-target Clippy passed in 26.452 s. The parent-lock comparison preparation's five
Python fixtures passed, including rejection of mismatched profiler dependency
graphs. These checks do not close the full release test or runtime gates.
Receipts: `E:/dq-cache/dmb-native-v2/r6-workspace-tests-20261009-052236-267743a5.json`
and `E:/dq-cache/dmb-native-v2/r6-workspace-tests-20261009-052643-55197219.json`.
The new source batch has not yet been benchmarked.

## Pending scanner/initializer candidate

The next source batch uses SIMD candidate searches in the shared selective
comment scanner, a lexical negative stored-declaration filter, streamed exact
initializer-plan hashing, and avoids allocating stored-header rosters for ordinary
locals. Whole-plan hashing retains the existing byte codec; per-write temporary
buffers remain. Invalid grammar containing qualifier text only in literals may
report during lowering instead of startup. Valid full-capture parity fixtures
remain unchanged.

Ordinary workspace library checks passed after the test expectation correction
(56.585 s), then passed again including the ordinary-local roster change
(72.726 s). These are not release-profile or runtime gates. Receipts:
`E:/dq-cache/dmb-native-v2/r6-workspace-tests-20261009-044508-fa1440e5.json`
and `E:/dq-cache/dmb-native-v2/r6-workspace-tests-20261009-044622-463880ca.json`.
This batch has not yet been benchmarked.

Cleanup removed 24 proven obsolete census output/trace leaves, totaling
2,605,265,225 logical bytes. Immutable pair archives, receipts and the newest
census artifacts remain. Physical free-space gain was not independently measured.
Receipt: `E:/dq-cache/dmb-native-v2/obsolete-census-leaves-cleanup-20261009-043152.json`.
## Next memory candidate

Immutable resource bytes now retain their original filesystem vector allocation;
capture, raw encoding and aliases share the same owner. Stored modified defaults
are captured before procedure lowering, allowing the classified runtime AST ledger
to be released earlier while preserving diagnostic precedence. An optional ledger
census uses the existing AST walker and allocation deduplication. Their admitted
cold measurement is recorded below.

The batch also adds an opt-in generic CPU-domain bound API. It can cap the original
upper bound only with complete, temporally disjoint interval proof across every
selected thread; missing proof retains the original bound. Existing critical CPU
metrics, process audit and benchmark acceptance remain unchanged. The API is not
wired to benchmark acceptance.

Release workspace/all-target Clippy passed in 65.619 s. Ordinary workspace library
checks passed **1,566 tests across 15 targets**, zero failures/ignored, in 228.047 s
including compilation. These are not the full release workspace gate.
Receipts: `E:/dq-cache/dmb-native-v2/r6-workspace-tests-20261009-034905-06380360.json`
and `E:/dq-cache/dmb-native-v2/r6-workspace-tests-20261009-035018-f134b27c.json`.

Full release workspace compilation on the shared-stage candidate also exceeded
the bounded 600-second attempt and one subsequent 600-second continuation before
tests ran. Package-isolated fallback was stopped because changing workspace feature
unification rebuilt dependencies. Alternating worktree/stable source roots also
invalidated dependency fingerprints. Further checks use the same authenticated
stable root. The release gate remains open; no runtime suite was launched.
Latest compilation-only receipt:
`E:/dq-cache/dmb-native-v2/stable-release-gate-20261009-035453-e0b10789-0.json`.

## Shared-stage source validation

The latest batch shares exact macro trace text and empty trace vectors, uses one
literal/comment boundary scanner for full and selective lexing, removes the
duplicate frozen operand-site roster, shares startup's procedure index, borrows
initializer bucket inputs, caches thread labels, and validates final instructions
with disjoint weighted tasks on the common executor. These changes preserve the
existing checks and ordering; their admitted measurement is recorded below.

Release workspace/all-target Clippy passed in 65.886 s. Ordinary workspace library
checks passed **1,559 tests across 15 targets**, zero failures/ignored, in 251.850 s
including compilation. The full release workspace gate reached its 600-second
watchdog during test-target compilation before test execution and remains open.
No DreamDaemon or DM runtime suite was launched.

Receipts: `E:/dq-cache/dmb-native-v2/r6-workspace-tests-20261009-025343-85d91c89.json`,
`E:/dq-cache/dmb-native-v2/r6-workspace-tests-20261009-030557-c864b49e.json`, and
`E:/dq-cache/dmb-native-v2/r6-workspace-tests-20261009-025503-7ed34cec.json`.

## Latest matched compressed-trace measurement

The authenticated control/candidate profiler overlays completed ABABAB, three
cold runs per compiler and eight workers. Candidate median child wall was
**11.588 s**, versus **11.133 s** for control: 4.1% slower, not a wall win.
Candidate total CPU was **27.438 s**, versus 28.203 s; critical CPU was 8.688 s,
uncertainty upper 10.828 s. Private memory was **1,576,521,728 bytes**, versus
2,193,870,848. Reads were 326,324,811 bytes and writes **568,835,247 bytes**.
All six measurement/oracle/structural no-regression checks passed. Reports proved
`gzip-level1-v1` for both compilers; this is an authenticated profiler overlay,
not an unmodified parent commit. The source parent for candidate is `59c1774fdb`;
the later scanner, streaming-codec and compact-origin changes are excluded.

Writes now fit the 600 MB byte budget, but memory and input, ABI/initializer and
composition CPU gates remain open. Full I/O acceptance is not evaluable because
blocked I/O time is unavailable. Raw versus gzip timings are separate methodology
cohorts and are not a paired speedup claim. This remains captured historical
DeepQuarry, fresh CLI, empty compiler caches, no daemon, and no runtime parity claim.

Evidence: `E:/dmb-native-v2-phase0/r6-cohorts/matched-gzip-20261009-041540-1e4173ff/comparison.json`
and `E:/dq-cache/dmb-native-v2/matched-gzip-result-20261009-041540-1e4173ff.json`.

The parent memory-owner candidate also passed whole captured-project 1/2/8-worker
byte and diagnostic equality. Single untraced child wall observations were
30.867/15.557/10.842 s respectively; these are determinism checks, not median CPU
acceptance benchmarks. Receipt:
`E:/dq-cache/dmb-native-v2/whole-project-worker-order-20261009-050904-c68596c7/receipt.json`.

## Previous admitted raw-trace measurement

The memory-owner candidate (`59c1774fdb`) completed ABABAB, three cold runs per
compiler and eight workers on the same captured historical project. Median child
wall was **11.802 s**, versus **11.673 s** for the control: no wall-speed gain in
this cohort. Process CPU was **28.297 s**, versus 29.859 s (5.2% lower). Critical
CPU was 8.766 s, uncertainty upper 10.844 s. Median peak private memory was
**1,565,057,024 bytes**, versus 2,167,504,896 (27.8% lower). Reads were 326,324,811
bytes and writes 655,313,307. All six measurement, fresh-native-output/diagnostic
and structural no-regression checks passed. Memory, write volume, input,
ABI/initializer and composition CPU acceptance remain open. The resource/maps
CPU gate passed in this cohort. This is not daemon/edit performance or BYOND
semantic parity.

Evidence: `E:/dmb-native-v2-phase0/r6-cohorts/paired-corrected-context-20261009-041438-a9e35a44/comparison.json`.
The optimized build passed in 427.083 s, including the authenticated stable-root
workflow. New lexical prefilter, initializer identity streaming and SIMD comment
scanning changes are excluded and awaiting validation.

### Previous shared-stage comparison

The shared-stage candidate (`3c0b93dffc`) completed an ABABAB comparison on the
same captured historical project, three cold runs per compiler and eight workers.
Median child wall was **12.609 s**, versus **12.839 s** for the control (1.8% lower).
Process CPU was 30.234 s versus 30.844 s. Peak private memory was **1,572,433,920
bytes**, versus 2,162,270,208 (27.3% lower). Reads were 326,324,811 bytes and writes
655,317,422. All six measurement, fresh-native-output/diagnostic oracle and
structural no-regression admissions passed. The memory, write-volume, input,
resources/maps, ABI/initializer and composition CPU acceptance gates remain open;
CPU acceptance uses uncertainty upper bounds. This does not establish daemon
iteration performance, current-master compatibility or BYOND semantic parity.

Evidence: `E:/dmb-native-v2-phase0/r6-cohorts/paired-corrected-context-20261009-032736-6f8bda19/comparison.json`.
The optimized candidate build passed in 562.148 s. Its authenticated stable source
root allows subsequent builds and release validation to reuse unchanged source
timestamps. The target cache was already shared by a junction; changed source-root
identity, rather than separate target storage, caused repeated compilation.

The next unvalidated source batch transfers filesystem resource vectors into
immutable shared owners without copying their payloads, captures stored defaults
and releases the classified runtime initializer ledger before procedure lowering,
and adds an opt-in deduplicated ledger census. These changes are not in this cohort.

### Previous semantic-owner comparison

The earlier semantic-owner and staged-output candidate (`36749fd74d`) completed
another ABABAB comparison, three cold runs per compiler, on the same captured
historical project. Median child wall was **12.639 s**, versus **12.227 s** for
the control: no wall-speed improvement in this cohort. Process CPU was 30.172 s
versus 29.797 s. Peak private memory fell from 2.149 GB to **1.624 GB** (24.4%),
and compiler reads fell from 550,004,461 to **326,324,811 bytes**. Writes remained
655,317,267 bytes. All measurement and structural no-regression admissions passed;
the memory, write-volume, input, ABI/initializer and composition CPU gates remain
open. This is not daemon or minimal-edit evidence, nor BYOND semantic parity.

Evidence: `E:/dmb-native-v2-phase0/r6-cohorts/paired-corrected-context-20261009-021800-ff90ad70/comparison.json`.
The following earlier comparison remains historical evidence for its own frozen
candidate; its faster wall measurement is not the latest result.

### Cached CLI diagnostic comparison

The completed ABABAB cached sequence uses the same `36749fd74d` candidate,
eight workers, fresh processes and three runs per compiler/scenario. All 24
measurement, native fresh-output/diagnostic oracle, cache-sequence and structural
no-regression checks passed. These are diagnostic disk-cache measurements, not
daemon acceptance or current-master results.

| Scenario | Control wall median | Candidate wall median | Candidate process CPU |
| --- | ---: | ---: | ---: |
| Populate empty disk cache | 25.578 s | 26.253 s | 64.172 s |
| Unchanged source, existing cache | 17.661 s | 14.526 s | 32.000 s |
| One procedure edit, existing cache | 14.804 s | 15.037 s | 32.797 s |
| Fresh compile of edited source | 13.188 s | 13.333 s | 30.250 s |

The procedure edit has no wall-speed improvement. Cached unchanged peak private
memory is 2.250 GB, and writes are 925.8 MB. The extra approximately 270 MB
written relative to uncached compilation comes mainly from additional per-hit
profiling streams: the folded trace alone adds 137 MB; Chrome tracing adds another
stream. The unchanged request recomputes zero procedures and its cache-flush
interval writes 486 bytes. This does not establish daemon iteration speed.

Evidence: `E:/dq-cache/dmb-native-v2/cached-semantic-20261009-a/cohort/comparison.json`.
Execution receipt: `E:/dq-cache/dmb-native-v2/cached-semantic-20261009-a/execution.json`.

The corrected-context control versus compact-code candidate completed an ABABAB
cold comparison on 9 October: three runs per compiler, eight workers, empty
compiler caches and warmed captured inputs. All six measurement, fresh native
DMB/RSC/diagnostic oracle and structural no-regression gates passed. Phase 1
exit targets remain **not met**.

| Measurement | Control A | Candidate B | Budget |
| --- | ---: | ---: | ---: |
| Compiler child wall median | 12.029 s | 10.976 s | Context; CPU judged |
| Critical CPU median | 9.266 s | 8.703 s | <= 15 s |
| Critical CPU upper | 11.250 s | 10.688 s | <= 15 s |
| Process CPU median | 29.141 s | 28.906 s | <= 40 s |
| Peak private memory median | 2.167 GB | 1.654 GB | <= 1.5 GB |
| Bytes read | 550 MB | 550 MB | <= 400 MB |
| Bytes written | 655 MB | 655 MB | <= 600 MB |

The candidate reduces median private memory by 513,232,896 bytes (23.7%) and
child wall by about 8.8% in this paired cohort. Input, ABI/initializer and
composition/publication stage CPU gates still fail; memory and both I/O gates
also fail. This compares the combined source changes, not an isolated relocation
experiment. Both binaries use corrected stage attribution and the same topology.

Control compiler commit: `a1ee3bb252de6138919df465ce3f8dd4c1084670`.
Candidate compiler commit: `b1236be6e9a893af68e87f5730565aeb2cf09292`.
Candidate SHA-256: `8ff060e4695a14adc1efdabb23389944554c8fdd542cba2ae02758a951d867d0`.
Build receipt: `E:/dq-cache/dmb-native-v2/source-compact-relocations-r6-20261009-011630.build.json`.
Comparison: `E:/dmb-native-v2-phase0/r6-cohorts/paired-corrected-context-20261009-013454-8f706366/comparison.json`.
Scope remains captured historical DeepQuarry `ac1af55...`, `comparison.dme`, test
defines, eight workers and fresh CLI processes; no daemon or minimal-edit result.
The first independent structural report is executed; later identical input/tool
hashes reuse that authenticated report while every row runs its own fresh output
and diagnostic oracle and recomputes its admission. Stable structural differences
are no-regression evidence, not full semantic parity. Later tee/compression work
is outside this frozen candidate.

## Earlier corrected-context self-comparison

Corrected context self-comparison completed on 9 October 2026. A and B run the
**same frozen compiler**, ABABAB, three cold runs per label, eight workers, empty
compiler caches and warmed captured inputs. All six measurement, fresh native
DMB/RSC/diagnostic oracle and structural no-regression checks passed. Phase 1
exit targets remain **not met**. No full migration or production readiness claim.

| Measurement | Self A median | Self B median | Budget |
| --- | ---: | ---: | ---: |
| Compiler child wall | 18.075 s | 16.450 s | Context; CPU judged |
| Critical CPU | 12.031 s | 11.781 s | <= 15 s |
| Critical CPU upper | 13.984 s | 13.813 s | <= 15 s |
| Process CPU | 32.938 s | 33.016 s | <= 40 s |
| Peak private memory | 2.176 GB | 2.174 GB | <= 1.5 GB |
| Bytes read | 550 MB | 550 MB | <= 400 MB |
| Bytes written | 655 MB | 655 MB | <= 600 MB |

Same-binary wall differences are noise, not a speedup. Acceptance fails memory,
I/O and CPU stage budgets. Canonical selectors below match the harness exactly;
inclusive phase maxima and exclusive residuals avoid adding overlapping children.
Cells show point / uncertainty upper in seconds, each domain median over three
runs. Windows bounds widen for genuinely separate observed residual intervals.

| Stage | A critical | A total | B critical | B total | Critical / total budget |
| --- | ---: | ---: | ---: | ---: | ---: |
| input | 0.547 / 0.828 | 3.219 / 3.750 | 0.562 / 0.844 | 3.156 / 3.688 | 0.5 / 1 |
| frontend | 2.844 / 3.375 | 7.062 / 8.906 | 2.781 / 3.312 | 7.047 / 9.078 | 3 / 12 |
| tree | 0.875 / 0.938 | 0.875 / 1.188 | 0.922 / 0.984 | 1.016 / 1.328 | 1 / 2 |
| resources/maps | 1.984 / 2.047 | 3.172 / 3.484 | 1.781 / 1.844 | 3.250 / 3.562 | 2 / 6 |
| abi/initializers | 1.094 / 1.219 | 4.141 / 5.203 | 1.047 / 1.172 | 3.812 / 4.781 | 1.5 / 4 |
| lowering | 1.344 / 1.406 | 9.188 / 9.500 | 1.375 / 1.438 | 9.203 / 9.516 | 3 / 16 |
| link | 0.906 / 0.969 | 1.547 / 1.859 | 0.953 / 1.016 | 1.656 / 1.969 | 1 / 2 |
| composition/publication | 2.391 / 3.188 | 2.938 / 10.281 | 2.438 / 3.281 | 3.000 / 10.328 | 1.5 / 3 |

Largest observed total CPU domains are lowering (~9.2 s) and frontend (~7.0 s),
both largely parallel; frontend and composition dominate critical CPU. Input
total CPU exceeds budget even before uncertainty. ABI total upper exceeds its
budget; resources and link straddle critical limits across identical-binary repeats.
Composition total upper (~10.3 s) is uncertainty, not 10.3 s observed work.

Scope: historical DeepQuarry `ac1af55d1a9a8e023e46bd058be59ed82c503f52`, captured
`comparison.dme`, test defines, no daemon or minimal-edit measurement.
Evidence: `E:/dmb-native-v2-phase0/r6-cohorts/self-corrected-context-20261009-002353-d49988fe/comparison.json`.
Domain calculations: `E:/dq-cache/dmb-native-v2/corrected-self-stage-medians-20261009.json`.
Compiler SHA-256: `4c4048c98413212017638fa33a9eea867856568e79c15df3d5fc0b617ec346f7`.
The earlier 13.97 s wall median remains separate historical evidence; its critical
CPU attribution was incomplete, so no historical critical CPU delta is claimed.

## Newer implemented source

`c9e64d0d78` shares frozen symbolic code with linker content and seals composition
before releasing source/startup owners. Exact collision checks preserve canonical
bytes, including equivalent differently segmented content. `955cf8b662` moves
parsed executable bodies/static-filter storage, shares captured asset payloads,
issues current images on the shared executor, uses a temporary relocation hash
map and validates argument records without temporary vectors.

Latest validation: 1,485 ordinary library checks passed, zero failures/ignored
checks (304.43 s); release all-target Clippy with warnings denied passed (75.39 s).
Full captured-project diagnostic passed with unchanged DMB/RSC SHA-256 hashes
(172.49 s, unoptimized census binary; **not acceptance timing**).
Known retained capacity: frontend 557.5 MiB, startup 623.4 MiB, lowering 699.7 MiB,
linking 684.7 MiB, publication 270.4 MiB. Earlier lowering was 1,114.8 MiB and
publication 827.9 MiB. Census excludes allocator overhead/private backing and
worker temporaries. Diagnostic peak private memory remained 2.262 GB.

The earlier optimized source `955cf8b662fb8ded31ad00441753b40fa7a37c45` lacks
complete worker parent-stage attribution; any traces from it are diagnostic only.
Its optimized build completed successfully in 635.15 s; comparison was withheld
until the attribution fix. Build receipt:
`E:/dq-cache/dmb-native-v2/source-typed-codegen-r6-20261008-232917.build.json`.
Executable SHA-256: `fe00d12ea41c76e7084fdbc39b23d17476d0c86b120651f70a3710eed546ae7b`.
The corrected optimized candidate completed the self-comparison above.
Generic `StageContext` propagation now captures caller stage names at explicit
shared-executor job boundaries, enters thread-local guards on the executing
worker and drops them in reverse order, including panic unwinding. Nested spawns
inherit their active context; disabled profiling allocates no context storage.
`install` propagates its executing closure's context; the ABI parallel iterator
retains its explicit per-chunk phase guard for other participating workers.
Canonical inclusive phase selectors and exclusive ancestor residuals are unchanged.

Current source passed release all-target Clippy with warnings denied (84.38 s):
`E:/dq-cache/dmb-native-v2/r6-workspace-tests-20261008-235525.json`.
The explicit `dm-exec` context integration test passed (11.19 s), covering nested
jobs, panic unwinding, installed work and clean worker reuse:
`E:/dq-cache/dmb-native-v2/profile-context-check-20261008-235701-2ef39ec2.json`.
The final ordinary library batch passed 1,504 checks in 115.98 s:
`E:/dq-cache/dmb-native-v2/r6-workspace-tests-20261009-000821.json`.
It includes the composition planner, source/tree instrumentation and word-transfer
corrections. Two earlier attempts exposed incomplete synthetic linker inventory
in the new initializer fixture; its required spelling is now supplied without
weakening production validation. Final release all-target Clippy passed with
warnings denied in 13.35 s:
`E:/dq-cache/dmb-native-v2/r6-workspace-tests-20261009-001023.json`.
The corrected optimized self-comparison above now supplies admitted CPU evidence
for shared lexical arenas, typed statement-model reuse and immutable resource CRC. Typed statement reuse retains the
existing lossless fallback for unsupported bodies; supported bodies release raw
children.

Implemented source now uses shared `SourceText` file/continuation arenas instead
of per-line text allocations, and one issued `StatementBody` through startup,
static extraction and lowering. Unsupported typed bodies retain lossless fallback.
Immutable shared resource payloads retain reusable CRC evidence rather than
rescanning unchanged payload bytes. Composition uses canonical ordered artifact
rosters and parallel independent procedure metadata; serial ID/list allocation
preserves ordering and error precedence. Borrowed composition avoids its second
word-buffer copy, and owned map/modified initializers transfer certified buffers.
Tree spans distinguish member installation, ancestry resolution, inheritance and
identity hashing. These implementations are covered by the corrected self-comparison; memory
targets and Phase 1 exit remain unmet. Later file-backed resource and additional
parallel inventory work are not included in this frozen measurement.

## Open correctness and architecture items

The latest compact-code source batch passed release all-target Clippy with warnings
denied (31.722 s), receipt
`E:/dq-cache/dmb-native-v2/r6-workspace-tests-20261009-010838-c637ec51.json`,
and 1,525 ordinary workspace library checks (128.485 s), receipt
`E:/dq-cache/dmb-native-v2/r6-workspace-tests-20261009-011029-84bd1c01.json`.
These ordinary-profile tests are not the outstanding release-profile gate.

Frozen `SymbolicCode` now retains 12-byte relocation sites and one exact-sized
per-procedure dictionary of distinct non-source `SymRef` values. Source-file,
source-line and line-delta payloads remain full-width inline ordinals. Borrowed
iteration reconstructs exact relocation values without an expanded array;
constructor validation/error order and canonical v2 bytes remain unchanged.
The recorded pre-change linking census implies 51,184,656 bytes of compact
site/dictionary payload versus 195,442,688 bytes of relocation capacity: an
estimated 144,258,032-byte retained payload reduction. This excludes container,
allocator and temporary constructor overhead and is **not a measured peak-memory
reduction**. New census counts the actual separate retained allocations.
Conventional output installation now reuses unchanged writable DMB/RSC files
only after the shared receipt helper authenticates their hashes and file stamps,
skipping the unchanged copy. This is output reuse, not a decoded engine cache.
Owned certified word-buffer reuse and direct final-slice parallel DMB encoding
remain implemented; the next optimized candidate must measure their combined
effect with compact symbolic storage. The compact-code captured-project diagnostic
completed successfully in 132.323 s, with peak private memory 1,651,974,144 bytes
and unchanged actual DMB/RSC hashes listed below. Actual retained relocation
storage was 51,184,656 bytes at linking and 44,902,860 bytes at lowering; the linking
payload reduction is therefore observed in the census, not merely estimated.
Known retained totals were 713,616,653 bytes at lowering and 706,743,141 bytes at
linking. These totals exclude unobserved allocator backing and worker temporaries.
Evidence: `E:/dq-cache/dmb-native-v2/census-method-prototype-20261009-011320-stack8388608/`.
This debug/census run is **not acceptance timing or acceptance memory evidence**.
The optimized archived candidate completed the paired comparison above; Phase 1
acceptance still fails memory, I/O and selected stage budgets. Later publication tee/compression changes are not validated by this
snapshot.

The later streaming-publication diagnostic `013354` preserved the same actual
DMB/RSC hashes and observed 326,324,811 process read bytes versus 550,004,461
previously, with peak private memory 1,660,530,688 bytes. This is debug/census
evidence, **not an optimized acceptance measurement**; the paired candidate
above excludes this later change. Evidence:
`E:/dq-cache/dmb-native-v2/census-method-prototype-20261009-013354-stack8388608/`.
Optional file-backed RSC publication streams encoding and hashing into immutable
archives; unchanged archives use a hash-only probe and authenticated reuse.
Request-owned resource pins survive until final pair publication. Sink I/O failures
retain the memory fallback and source diagnostic precedence. Generic callers
retain memory output. The latest batch also releases expansion-only region
segments/effects in uniquely owned one-shot frontends after nontext capture;
shared or previously issued revisions retain their complete plans. Source locations,
body issuance, analysis and incremental frontend APIs remain intact.

The streamed-resource-only frozen commit `7325538b10` completed a captured-project
**diagnostic** census with exit 0 (593.055 s). Expensive full macro-environment
census traversal amplified runtime; this is **not a compiler benchmark or acceptance
measurement**. Peak private memory was 1,986,547,712 bytes, compared with
2,236,796,928 bytes in the prior diagnostic. Both actual output SHA-256 hashes
remained identical: DMB
`7039eba3aea7e86a8124f13dbee8bb5dff55ed69e24e31930dbe394346ef7bc5`, RSC
`6a77e931ddc3e8e909e527d839814d18bbfb95651273e8cefdf3bd27b192f437`.
Evidence directory:
`E:/dq-cache/dmb-native-v2/census-method-prototype-20261009-005109-stack8388608/`.
This run excludes the newer compile-only release, bounded writer and structural
macro census changes. Their captured-project diagnostic subsequently completed
with exit 0 in 122.027 s, with peak private memory of 1,880,727,552 bytes and the
same actual DMB/RSC hashes above. This debug/census runtime is **not acceptance
timing**; the changed census traversal also prevents treating its runtime delta
as a compiler speedup. It excludes the newer compact-code work.
Evidence:
`E:/dq-cache/dmb-native-v2/census-method-prototype-20261009-010310-stack8388608/`.
The optimized paired comparison above measures the compact-code source batch;
the earlier corrected self-cohort does not measure these newer changes.

Whole-program structural diff: **1,853,923 differences**, unchanged in the admitted
cohort: bytecode 1,636,088; globals 14; other 1,277; proc flags 14; proc table 8,983;
strings 201,358; type headers 1,949; type set 10; var defaults 4,230. There are 126
uncovered fixed words. Stable counts are a no-regression gate, not semantic parity.
Runtime baseline is deferred to Phase 5. `power_bridge.dm:154` behavior remains
unresolved. No new DreamDaemon/DM suite runs were made and all-tests parity is
not claimed. Full release-profile workspace test evidence remains outstanding;
ordinary library checks and release Clippy are separate gates.

Changed requests still reconstruct whole-program stages. Existing disk memos are
preserved, but retained daemon sessions, fast structural edits, Phase 3 cache
segments, six-worktree acceptance and integration/fallback gates remain open.
No new daemon or disk-cache functionality is added before Phase 1 exits.
Composition metadata/list planning still has serial work. Initial filesystem
read Vec-to-Arc conversion still copies. Immutable pair publication plus writable
conventional output installation writes the large files twice; the current
contract is preserved. Source-level implementation cannot close measured gates.

## Next three actions

1. Validate shared lexical arenas and one issued typed statement model through
   startup/static extraction/lowering; retain exact spans, errors and fallback.
2. Freeze and build a corrected optimized candidate containing context propagation,
   regenerate its comparison and trace remaining input, resources,
   link/composition, memory and I/O misses; cut measured owners/work, not gates.
3. Close Phase 1 worker-count/order/output and release-test evidence, then build
   retained sessions and measure unchanged, body and structural edits honestly.

Structured evidence: `phase0/results.jsonl`, `bench/results.jsonl`.
Earlier narratives: `archive/STATUS-20261008-ownership.md` and older archives.

## Overnight migration batch in progress (9 October)

The completed matched cold cohort still measures commit `64d40464`: 12.498 s
median child wall, 9.578 s critical CPU point, 30.875 s total CPU and
1,569,341,440 peak private bytes. The Phase 1 gates remain open. Newer changes
below are not included in those numbers.

The pending batch moves initializer evaluation through the actual prepared AST
boundary, lowers borrowed initializer assignments, shares frozen debug origins,
compacts transient expanded lines and declaration ledger coordinates, and
parallelizes ordered path preparation. Session records are separated from the
request-held manifest lease. Command-line profile finalization now uses the
same library boundary intended for retained request hosts. This does not
implement or activate a daemon or retained semantic revision.

Validation found and corrected two fixture compilation problems and an error
fixture whose expression the existing compiler legitimately accepts. The latest
ordinary check stopped at that fixture; a coherent check of the completed batch
is still required. Source writes overlapped that diagnostic check, so it is not
a validation receipt for the session refactor. A separate bounded full release
check is running against the immutable older `64d40464` candidate; it cannot
validate this pending batch. Runtime baseline remains deferred to Phase 5.

The immutable `64d40464` full release attempt closed at its 1,200 s
compilation watchdog without test execution. Receipt:
`E:/dq-cache/dmb-native-v2/stable-release-gate-20261009-063800-eb3e7803.json`.
It made progress across compilation targets but does not close the release
test gate. No release-profile flags were relaxed. Independent review also
caught a missing finalization admission-seal call in the new profiling code;
the prepared fix must be applied and validated before capturing a benchmark
source. The current ordinary check is diagnostic for the preceding snapshot.

The finalization seal is now physically verified before the binding/worker/stage
checks. A focused release-profile executor/profiler run passed 43 checks across
seven targets in 40.438 s including compilation, with no failed/ignored tests:
`E:/dq-cache/dmb-native-v2/r6-workspace-tests-20261009-070805-6c7fd698.json`.
The ordinary workspace library run passed 1,602 checks across 15 targets in
279.511 s; that snapshot predates only the finalization seal and updated executor
context fixture, so it is not full-workspace evidence for the final source:
`E:/dq-cache/dmb-native-v2/r6-workspace-tests-20261009-065535-0c2a3d58.json`.
The 28 focused Python benchmark checks also pass. Full release workspace testing
and the new source's captured-project benchmark remain outstanding.

Release all-target workspace Clippy passed with warnings denied in 57.409 s
including compilation after removing three redundant fixture conversions:
`E:/dq-cache/dmb-native-v2/r6-workspace-tests-20261009-071022-8a953707.json`.
This checks all targets but does not substitute for full release test execution.
The next alternating comparison will use the prior optimized candidate as
control, with the exact same request-aware profiler and executor source overlay
on both sides. Old cohort receipts and their instrumentation are unchanged.

## Matched cold comparison — 9 October, 07:38

Committed candidate `607bad5b72`, versus prior optimized `64d40464` with
the candidate's exact profiler/executor overlay on both sides. ABABAB, three
cold runs per compiler, eight workers, gzip level 1, captured historical
DeepQuarry `ac1af55d1a`; these are not current-master measurements.

| Median | Control | Candidate |
|---|---:|---:|
| Child wall seconds | 13.9811 | 12.4763 |
| Critical CPU seconds | 10.6250 | 9.34375 |
| Critical CPU uncertainty upper seconds | 12.71875 | 11.515625 |
| Total CPU seconds | 32.28125 | 30.53125 |
| Peak private bytes | 1,564,590,080 | 1,553,612,800 |

Measurement admission and structural no-regression passed. Candidate memory
still exceeds 1.5 GB; input, resources/maps and composition/publication remain
over stage budgets. Blocked I/O acceptance remains unevaluable. Fresh-native
output comparisons do not establish BYOND semantic parity. Phase 1 remains open;
actual daemon/cross-revision incremental compilation remains unfinished.

Evidence: `E:/dmb-native-v2-phase0/r6-cohorts/matched-gzip-20261009-071225-9e39227f/comparison.json`.
Pending uncommitted RSC-proof, metadata-sharing, tracing and retained-host changes
are excluded from this comparison.

Subsequent ordinary library validation passed **1,620 tests** in 272.537 s
including compilation (`r6-workspace-tests-20261009-073914-a06cc57f.json`).
Focused release executor/profiler validation passed **51 tests** in 295.952 s
including compilation (`r6-workspace-tests-20261009-074358-461fe3b9.json`).
The latter covers persistent physical worker brackets, same-worker request
isolation, panic cleanup and bounded lossless Chrome trace draining. These
checks do not establish a complete release workspace gate or daemon activation.
Further resident memo and immutable asset fingerprint changes postdate the
1,620-test run and require their own validation and captured-source comparison.

## Retained-host core prototype — 9 October, 08:00

The shared request runner now accepts a `BuildHost` retaining exact authenticated
engine owners and bounded region candidates. Candidate visitors use the ordinary
consumer's complete validation; rejected resident variants fall through to disk.
Validated disk hits are promoted without republishing. Keyed lookup checks at
most four variants; ordered indexes drive eviction. Retention is capped at
48 MiB total and 16 MiB per kind including conservative container charges.
CLI one-shot runs bypass resident storage, and no-cache one-shot runs pass actual
`None` to preprocessing so they do not construct unused memo records.

Shared immutable resource owners now compute SHA and canonical CRC together in
capture workers. Full-length resolver/resource IDs reuse those facts; declared
prefixes hash their actual bounded bytes. Canonical CRC uses eight-byte tables,
checked against an independent bitwise implementation and arbitrary streaming
boundaries. Declaration metadata/ABI owners share immutable allocations; prior
RSC proofs retain existing exact/racy verification and isolated writable outputs.
Chrome tracing uses a bounded lossless request-local queue and reports drain
errors. Persistent executor request brackets bind every physical worker and join
coverage on success, failure and panic.

Validation: **1,628 ordinary library tests passed**, zero failures, 82.615 s
including compilation (`r6-workspace-tests-20261009-075840-b6901eb7.json`).
Release all-target workspace Clippy passed with warnings denied, 44.529 s
(`r6-workspace-tests-20261009-075707-45b7adf9.json`). The 51 focused release
executor/profiler tests above apply to unchanged profiling/executor source.
No DM runtime runs were made; full release workspace testing remains incomplete.

This is a useful retained-host prototype, not full incremental compilation:
frontend reassembly and startup facts are still freshly issued, retained worker
brackets are not yet connected to the request runner, and daemon transport,
cross-revision semantic reuse and six-worktree acceptance remain unfinished.
The new source's matched cold comparison is recorded below.

## Matched cold comparison — 9 October, 08:29

Committed candidate `1d5006992b`, compared with `607bad5b72` carrying the
candidate's exact profiler/executor overlay. ABABAB, three cold runs per compiler,
eight workers, gzip level 1, captured historical DeepQuarry `ac1af55d1a`.

| Median | Control | Candidate |
|---|---:|---:|
| Child wall seconds | 12.2873 | 11.6744 |
| Critical CPU seconds | 9.359375 | 8.84375 |
| Critical CPU uncertainty upper seconds | 11.515625 | 10.859375 |
| Total CPU seconds | 29.421875 | 29.890625 |
| Peak private bytes | 1,539,751,936 | 1,598,050,304 |

Wall time fell 5.0% and critical CPU fell 5.5%; total CPU rose 1.6% and memory
rose 3.8%. This is a cold CLI comparison, not a daemon or minimal-edit result.
Measurement admission and structural no-regression passed. Candidate memory,
input, ABI/initializers and composition/publication still fail their budgets.
The existing blocked-I/O completeness gate remains unevaluable; measured bytes
were 326,324,811 read and 569,631,392 written. Those fit the numeric byte budgets,
but do not establish complete blocked-time reporting or BYOND runtime parity.

Evidence: `E:/dmb-native-v2-phase0/r6-cohorts/matched-gzip-20261009-080118-c1a328bd/comparison.json`.
Pending retained-worker integration, procedure memo promotion, sealed input reads
and annotated I/O bounds are excluded from these frozen binaries. Their first
ordinary library validation failed compiling the new profiling report; no tests
executed in that attempt (`r6-workspace-tests-20261009-082930-f3d4c567.json`).

## Retained request integration — work in progress

The shared runner now brackets its complete frontend-through-publication tail
with the host's retained worker pool. Worker-count changes join the prior pool;
unchanged-session returns avoid creating a pool. Procedure memo facades retain
only admitted immutable values across requests, with current resolver answers
checked on every replay. Validated disk results promote without republishing;
debug/source/ABI bindings remain current. Capacity admission walks accessible
owned buffers and charges containers conservatively; unsupported helper models
decline resident retention. This is not an allocator-page or RSS guarantee.

Input reads carry a private owned bytes/digest envelope. Replay constructs it
only after exact size/hash verification; callers cannot mutate authenticated
bytes. Engine frontend seeds now share the existing exact engine owner. Dynamic
trace labels share one immutable allocation. Annotated I/O wait bounds are
explicitly partial and do not certify complete storage blocking. Future benchmark
summaries separate numeric byte-budget acceptance from that reporting obligation;
historical summaries are unchanged.

The ordinary library run `r6-workspace-tests-20261009-083055-a0924b12.json`
compiled successfully, then failed one procedure-memo fixture: it expected four
disk hits after replay, while the new promotion path produced two disk and two
resident hits. The fixture now checks both counters, unchanged code, shifted
source origins, zero recomputation and zero pending republication. Validation of
this corrected batch passed **1,642 ordinary workspace library tests**, zero
failures, 276.150 s including compilation
(`r6-workspace-tests-20261009-083744-27dc68a4.json`). Focused release
executor/profiler validation passed **57 tests**, zero failures, 286.677 s
including compilation (`r6-workspace-tests-20261009-084254-639ac7e6.json`).
No complete release-workspace gate or DM runtime gate is claimed. No new
performance result is claimed for the integrated batch.

Subsequent source changes box only runtime expression roots, reducing the inline
size of every initializer ledger/pending slot while retaining one AST owner.
Evaluated list trees are released after const rejection before further runtime
argument preparation. Census traversal counts the boxed root and nested buffers.
Repeated positive input/folder lookups borrow stored canonical keys; aliases and
negative admission retain full canonical validation. New focused ownership,
error-order and alias fixtures are included. Ordinary library validation for
these additions passed **1,644 tests**, zero failures, 77.458 s including
compilation (`r6-workspace-tests-20261009-084755-6c2e18fd.json`). The Rust file-size
gate passed. Release all-target workspace Clippy passed with warnings denied,
64.991 s (`r6-workspace-tests-20261009-085302-4262ea53.json`), after correcting the
reference-provider fixture to explicitly select its forwarding implementation.
Six byte-budget/reporting fixtures and 22 benchmark protocol fixtures passed.
Allocation and benchmark improvements are unmeasured.

Daemon transport, cross-revision frontend/startup binding, semantic dependency
reuse and six-worktree acceptance remain unfinished. Phase 1 gates remain open;
the daemon and disk-cache activation remain deferred until those gates close.

## Next parse/source ownership migration — unvalidated source

Following committed batch `be11683d0b`, source now shares privately issued
static-declaration plans between startup and typed lowering. The producer validates
the exact current body and procedure identity before capture. The consumer retains
the existing current-startup declaration/origin comparisons and executable masks;
raw and standalone adapters retain their required fallback behavior. Startup borrows
shared plans and keeps negative-prefilter captures inline, avoiding a heap allocation
for every empty procedure. Owner-local occurrence calculation has one shared,
allocation-free tree implementation.

The body arena boxes only ready parse results, reducing the dense slot representation
for unparsed/consumed bodies. Census counts those allocations and shared plans. Source
preparation and frontend capture retain one `SourceText` owner from the decoded read
buffer, replacing the production `String` to `Arc<str>` payload copy. Retained original
source bytes are still necessary and are not claimed as a memory saving.

These changes have not been compiled or benchmarked. The file-size gate passed.
The active frozen cold comparison tests `be11683d0b` versus `1d5006992b` with matched
profiler/executor sources and excludes this newer source batch. Its control Rust
release build completed; candidate build and compiler measurements are pending.

## Priority update and completed cold comparison — 2026-10-09

The human directed functionality and correctness ahead of further cold-build
micro-optimization. This supersedes the previous throughput-before-daemon order;
the full runtime baseline remains deferred to Phase 5. Current daemon and retained
semantic/procedure integration are unvalidated source, not completed acceptance.

The frozen be11683d0b versus 1d5006992b comparison completed three cold runs per
compiler, eight workers, on captured DeepQuarry ac1af55d1a. Median launch-to-reap
wall time was 13.820 s control and 15.346 s candidate; critical CPU was 10.578 s
and 11.016 s; total CPU was 32.547 s and 32.391 s; peak private memory was
1,595,318,272 and 1,554,059,264 bytes. This batch reduced retained memory but
regressed wall time in this cohort. Measurement admission, numeric I/O budgets
and structural no-regression passed; overall stage/memory budgets failed.
Annotated blocking observations remain partial. Newer uncommitted migration
and daemon code was excluded. These results do not establish BYOND semantic
parity or incremental edit performance.

Evidence: E:/dmb-native-v2-phase0/r6-cohorts/matched-gzip-20261009-085609-fb0c242d/comparison.json.
## Integrated session/CLI prototype — compile gate

The current migration passed `cargo check --workspace --all-targets -j1`
(162 s), followed by a locked all-target recheck (19.93 s). Four focused Bun
compiler-selection fixtures passed (12 assertions); they launch no DM process.
This is compile/dispatch validation, not runtime or full compiler acceptance.

Retained hosts now own semantic-tree reuse and full-session compact symbolic
procedure contributions. Exact resolver receipts admit reuse; current source
occurrences, ABI bindings and linked-image certificates are regenerated. RichIR
hints and validated disk hits can promote through the same trusted completion.
Helper and modified-instance sidecars still take the existing lowering path.

CLI daemon transport, typed source/internal failures, publication cancellation
latches and diagnostic forwarding are connected. Daemon admission bounds workers
to eight and builds to three, with idle trimming and transport deadlines.
`DQ_COMPILER=byond|native|shadow` routes the common build entry; shadow uses an
isolated disposable store. Source errors and cancellations never trigger fallback.
No daemon transport smoke run, six-worktree acceptance, edit benchmark, full Rust
suite, DreamDaemon run or BYOND semantic parity is claimed for this batch.
## Daemon smoke and analysis contract — 2026-10-09

The first bounded smoke caught a Windows PIPE_NOWAIT false-EOF bug; the connected
pipe now checks availability before reading. The client also enforces one total
20-second startup deadline rather than a fresh budget for each retry. Rebuild
passed in 106 s. A second smoke used an invalid source fixture for tolerant
analysis and was replaced with explicit `#error`; all evidence is retained.

The final owned smoke passed nine cases in 7.805 s: help, four analysis requests
across two manifests, source error exit 2, two daemon compilations and a fresh local
compilation. The 21,950-byte DMB and empty RSC matched byte-for-byte between daemon
and local compilation. These debug tiny-fixture wall times are not DeepQuarry
benchmarks or iteration acceptance. Owned daemon and output stores were removed.
Evidence: E:/dq-cache/dmb-daemon-smoke/20261009-100001-ef381fcb/report.json.

Analysis export schema 3 uses the same normalized member occurrences as compiler
identity and emits generic Resolver answers, preserving missing versus unsupported
and wide query keys. Two focused export fixtures passed, zero failures, 15.92 s
including compilation. This supports declaration lints and documentation; executable
reference and resource query coverage remains incomplete. Five focused artifact
store fixtures also passed, zero failures, 102 s including compilation.
Fresh modified-instance replay now retains body-relative source recipes and
canonical descriptor evidence, issuing descriptors from the current authenticated
AST and current resource/type proofs. Unsupported raw/wire/helper modifier cases
retain the ordinary lowering fallback. Configuration-scoped daemon supersession
preserves independent define/output requests and removes abandoned registrations.
The integrated all-target locked workspace check passed in 21.10 s after fixing
one helper-fixture import. New focused runtime fixtures remain to be executed.
### Retained initializer migration — 9 October

The per-write initializer owner now uses the shared exact-key artifact store and
resolver-read ledger. Current-revision mode replaces prior semantic variants and
prunes removed keys; cached values rebind current syntax, ordinals and issuance.
Opaque pure-call providers decline reuse. Retained symbolic memory accounting is
an explicit diagnostic traversal, rather than work on every request. Default CLI
compilation now uses its embedded pinned engine, avoiding a build-directory dependency.

Locked all-target workspace check passed in 31.63 s. Eight focused dm-session
artifact fixtures and nine focused dmbc initializer/source-recipe/census fixtures
passed. Two initial filter strings selected zero cases; corrected direct filters
executed the intended fixtures (receipt initializer-direct-focused-20261009.json).
No DM runtime tests or new DeepQuarry performance cohort were run. Full modifier
fact admission, startup/ABI roster processing and output linking remain migration
work; these results do not establish full BYOND parity or complete incrementalism.

### Retained map output migration � 9 October

Map sources, parsed documents, geometry, descriptors and initializer code now
reuse through the retained daemon owner and common exact dependency ledger.
Descriptor entries and initializer code/debug payloads are immutable shared owners;
current-table rebinding and binary encoding still run. Source/location/resource
context and changed resolver reads invalidate reuse. The request telemetry now
reports output_hits and outputs_prepared.

Locked workspace all-target check passed (35.49 s after repairing Arc consumers).
Eleven focused map/output/source-proof/owner/census/recipe fixtures passed;
compile took 158 s and each executable group completed below 0.03 s.
Receipt: E:/dq-cache/dmb-native-v2/map-outputs-focused-20261009.json.
This is functional validation, not a new DeepQuarry timing or BYOND runtime gate.
Metadata dependency vector backing is now traversed explicitly for census;
private allocator/control overhead and conservative code-index charges remain
disclosed limitations. Human DESIGN and REVIEW documents remain untouched.


## 2026-10-09 23:35 shared-owner migration

The bounded prototype cohort at commit 9eb5b8f1d5 completed: unchanged 1.07 s, body edit 35.24 s, new proc 34.65 s; independent fresh builds 17.78-20.36 s. All four native DMB/RSC byte oracles passed. This O1/256 + dm-tree O1 profile is not acceptance evidence. Pressure still evicted whole sessions after rich-buffer release. BYOND structural semantic coverage remains incomplete with 1,834,121 baseline discrepancies.

The newer migration batch passes the workspace all-targets check and 44 focused fixtures. It shares variable/signature receipts, allocation/type rosters, selected facts, header membership layers and fresh admission ledgers. Its performance and memory effects are UNMEASURED. See phase0/migration_checkpoint_20261009.json and bench/idle-retention.md. No DreamDaemon or full runtime suite was run. Remaining conservative/static and rich helper paths and concurrency/history acceptance are open.


## 2026-10-10 retained-output oracle correction

Commit 73744c4af4 passed 55 focused checks and the all-target workspace check, but its subsequent captured DeepQuarry initial retained output failed the independent fresh-native oracle. The two 59,223,433-byte DMB files differed in 989 gender header bytes; no procedure-code byte differences were observed. The retained header recipe omitted gender. The correction is in working source, with a single shared header inheritance catalog and an expanded fresh/first-retained/warm-retained golden check. Until that correction passes the full native oracle, this batch has no admitted iteration timings. See bench/receipts/phase2-20261010-retained-gender-oracle.json.

Memory work now removes uniform unused owner payload arrays and retains only effective metadata deltas over exact current normalized rows. Nine focused owner metadata checks and two stable-key checks passed. Full memory and speed effects are still unmeasured. Current source diagnostics bind only confirmed invalid intrinsic assignments; ordinary valid builds skip expanded-origin scanning. Helper-expression replay and preprocessing receipt storage reductions are being integrated. BYOND structural/runtime, six-worktree, history and memory acceptance gates remain open.

### 10 October: shared owners and current-source query gates

Committed engine-scoped normalized declaration sharing and indexed host claim cleanup (5532ef1e16), native Input radius/center encoding (380e03669d), and shared callable anchors (328692d3d1). Focused checks pass for current invalid-field origins/status, actual selected-reference producer replies through client validation, cancellation-aware publication leases, shadow resource admission, and complete-word native list initializer receiver encoding. The selected-reference endpoint is bounded and captures only explicitly resolved procedures; it does not provide complete on-demand analysis. Full DeepQuarry fresh-native comparison and new end-to-end timings remain pending. Validation receipts are in bench/receipts/phase2-20261010-shared-pipeline-validation.json.

## 2026-10-10 shared declaration and initializer migration in progress

The captured DeepQuarry prototype cohort used d548eaffe09e, dmbc O0/256 and dm-tree O1. End-to-end retained/fresh seconds: initial 88.326/37.130, unchanged 1.697/35.027, body 62.059/34.401, new proc 48.627/32.689, new var 62.133/33.417, default 38.320/33.177, signature 62.521/34.735. All seven independent native DMB/RSC byte pairs agree; the final structural inspector exhausted its remaining 31.6-second allowance, so the cohort is not accepted. BYOND structural differences remain open (1,858,674 in the first comparison). This prototype profile is not comparable to optimized acceptance timings. See bench/receipts/phase2-20261010-prototype-iteration.json.

Current source adds engine-scoped exact source-neutral declaration contribution leases, shared authored metadata, parser-issued initializer receipts, complete nested expansion payload census, and avoids duplicate compact-eligible RichIR retention. It also corrects lexical ownership of sibling defaults and blank-line string continuations, with independently captured DreamMaker evidence. Inspector normalization uses request-local immutable-owner memoization. These changes are not included in the timings above.

Six focused inspector checks passed against binary SHA recorded in E:/dq-cache/dmb-native-v2/integration-gates/20261010-022307-6ed9d84e-focused.json. The preceding bounded test-binary build completed in 254.83 seconds. Tree and compiler focused checks, subsequent frontend index reuse, admission-weight cuts and inspector reporting changes remain under integration. No DreamDaemon or full DM suite was run. Full runtime, memory/throughput acceptance and six-worktree gates remain open.

Follow-up integration: 31 focused tree checks passed (shared contribution leases, authored leaf/index reuse, adapter ownership/error spans, normalization and diagnostic roster). Compiler-side focused groups passed: classification 6, shared expression receipts 3, sealed compact composition 1, native string continuations 3, initializer assemblies 3, fragments 4, startup artifacts 3, prepared evaluator forwarding 2, bounded fragment census 1 and startup census 2. Receipts: integration-gates/20261010-022516-de0bae99-focused.json, 20261010-023007-56fa747f-focused.json and 20261010-023024-36bf111f-focused.json under E:/dq-cache/dmb-native-v2. Existing inspector comparison groups passed 41 and 15 focused checks; reporting-buffer/hex changes await their rebuilt binary. All 13 focused build-adapter checks passed with a 60-second watchdog, Bun 1.3.14 and disabled transpiler cache. Native adapter fallback is now internal-status-70 only; unsupported pinned target macros return invalid-request status64. Shadow remains explicitly incomplete until a shared authenticated BYOND input/config closure exists.

The completed shared-declaration/initializer/reporting batch passes the bounded workspace all-target check (77.37 seconds, integration-gates/20261010-023539-cbb08339.json). Exact reporting and inspector tests passed21 checks in 20261010-023521-21849587-focused.json. The authored leaf receipt census now borrows actual descriptor backing and deduplicates payloads; its hook is covered by source integration checking. No newly optimized full build timings are claimed. Persistent cache lease removal is the next separate architecture slice; it is not part of this validated batch.

## 2026-10-10 persistent cache lease removal

Removed publication-time cache root collection, persistent lease files/APIs and lease-driven compaction from the active compiler. Explicit maintenance now expires typed-valid immutable segment/group leaves by their immutable modification age (14 days); output-pair eviction remains separate at7days. Concurrent mapped readers remain valid; Windows sharing violations defer deletion, and corrupt/unsupported/temp/legacy lease files are not repaired or removed. This is cache disposal and may cause correct misses; it does not claim access-recency retention or a speed improvement. The five focused lifecycle fixtures passed (20261010-024449-369f703d-focused.json), including real parallel publication and mapped-reader retry. The bounded all-target workspace check passed in28.93s (20261010-024507-462a1323.json).

The first optimized frozen build of b4c1ba3f80 hit its300-second watchdog after dependencies finished; owned children were reaped. No new optimized benchmark numbers are admitted from that build. The next attempt reuses completed dependencies and retains the same watchdog.

### 10 October: cache publication migration and next measurement

The lease-removal commit is 607e2c961f. A second frozen optimized compiler build also reached its 300-second watchdog; both timed-out builds reaped their owned children. The matching prototype profile (dmbc O0/256, dm-tree O1, LTO disabled) built successfully in 64.34 seconds, executable SHA256 bb2d0ae30c649d2e0c0741d7cb1dee61c66c0e8ce1e91bce7213c91f18cfc5b1. This is build-tool time, not a DeepQuarry compilation benchmark, and not the acceptance profile. A newly frozen inspector is being built before the next measured cohort.

Working source consolidates all semantic cache producers under a single request-owned spool. Payloads reside in private files, descriptor memory grows with records and variants, and completion publishes one immutable segment. Map records use versioned variant framing and validate every candidate before semantic admission. Cancellation and escaped producer handles are covered by terminal request ownership. Cache publication is optional: failure must be recorded without invalidating already admitted and installed compiler outputs. These changes and the opt-in descriptor census await their focused integration gate; they are not included in the frozen 607e2c961f measurement binary. Full BYOND/runtime, concurrency, history, memory and throughput acceptance remain open.

The next frozen cohort at 607e2c961f completed initial/unchanged/body rows with retained wall times83.371/1.941/65.849s and fresh36.741/38.030/38.520s; all native byte oracles passed. New-proc compiles also succeeded at64.392/36.887s and their final DMB/RSC hashes agree, independently checked after daemon reaping. That row was not appended by the harness: its structural inspector encountered Windows112 while writing its report. Remaining edits were not measured. The partial receipt is bench/receipts/phase2-20261010-shared-leaf-iteration.json. Initial BYOND structural differences remain1,858,610 with incomplete semantic coverage; runtime is not tested. Session pressure still causes eviction around4.6-4.9GB private memory. No acceptance gate is closed by these numbers.

Focused source integration now passes the all-target workspace check (20261010-031952-274da059.json,27.46s), five streamed-cache fixtures (20261010-032014-23a07d0b-focused.json),24 adapter fixtures plus two exact parser/shared-contribution fixtures, and six diagnostic harness fixtures. One initial fixture invocation omitted its working-directory argument; another matched no frontend filter after completing the24 adapter checks. Corrected exact filters executed the intended two frontend checks. The declaration annotation fix strips only top-level input annotations from initializer spans; it retains quoted/nested expressions. Parser sidecars share one wire Arc, and shared contribution hits retain a single current binding. Inspector report writes are now buffered with explicit flush/error propagation. These later changes await a new frozen performance cohort.

The request-batched cache and pressure-release slices now pass focused runtime fixtures: four common-request spool tests, seven typed map candidate tests, one active-spool census test, the captured direction matrix, two numeric-cache reconstruction tests and the existing rich-pressure symbolic-owner test. Generic streamed-cache tests passed5. Receipts:20261010-032701-b88b94e6-focused.json (first12 passed before a separate static-vars fixture failure) and20261010-032729-2fd50deb-focused.json (four passed). The static-vars fixture needed explicit LinkInventory spellings; its correction and the fresh/retained null-name correction remain pending a rebuilt test binary. No DreamDaemon/full runtime suite was run. Numeric-cache release clears disposable frame/list bindings while preserving symbolic recipes; saved memory is still unmeasured. Actual staging counters now use staging names/wall-time labels; final committed segment/record/variant telemetry is separate. Cache failure is nonfatal to admitted output.
