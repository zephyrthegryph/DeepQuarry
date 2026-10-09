# Native compiler status

Updated 9 October 2026. Binding plan: DESIGN.md revision 6.

## Latest admitted measurement

Phase 1 was opened under the user's D36 decision. Structural traversal remains
complete; a new parallel-worker phase attribution gap requires a corrected
measurement rerun. Phase 1 exit targets are **not met**. Full migration,
incremental edit performance and production readiness are not claimed.

Eight-worker cold compilation, empty compiler cache and warmed captured inputs:

| Measurement | Previous A median | Candidate B median | Budget |
| --- | ---: | ---: | ---: |
| End-to-end compiler child wall | 19.09 s | **13.97 s** | Context; CPU judged |
| Critical-path CPU | 15.625 s | **11.594 s** | ≤ 15 s |
| Critical-path CPU uncertainty upper bound | 17.50 s | 13.50 s | ≤ 15 s |
| Total process CPU | 34.141 s | 31.922 s | ≤ 40 s |
| Peak private memory | 2.588 GB | **2.280 GB** | ≤ 1.5 GB |
| Bytes read | 1.623 GB | 550 MB | ≤ 400 MB |
| Bytes written | 616 MB | 625 MB | ≤ 600 MB |

ABABAB, three runs per compiler. All six passed the then-current automatic
measurement checks, fresh native DMB/RSC/diagnostic equality and structural
no-regression. Wall median fell 26.85%. Critical CPU and stage-budget rows are
**provisional**: an audit found parallel output workers missing their parent
phase guards. Global process CPU, wall and private-memory measurements are
unaffected. Corrected phase attribution must be rerun before CPU improvements
or CPU-budget conclusions are promoted. Overall acceptance still fails memory,
I/O and several stage budgets. No allocation-counting data is attributed to this
release/mimalloc acceptance binary. Stage CPU upper bounds below use the same
canonical mapping as the automated gate; nested totals must not be added again.

| Stage | Critical CPU upper | Total CPU upper | Critical / total budget |
| --- | ---: | ---: | ---: |
| Input | 0.766 s | 3.750 s | 0.5 / 1 s |
| Frontend | 2.672 s | 7.359 s | 3 / 12 s |
| Tree and captured facts | 0.906 s | 1.156 s | 1 / 2 s |
| Resources/maps | 2.453 s | 2.453 s | 2 / 6 s |
| ABI/initializers | 1.109 s | 2.500 s | 1.5 / 4 s |
| Lowering | 1.391 s | 9.813 s | 3 / 16 s |
| Link | 1.500 s | 1.500 s | 1 / 2 s |
| Composition/publication | 2.797 s | 2.797 s | 1.5 / 3 s |

Scope: historical DeepQuarry `ac1af55d1a9a8e023e46bd058be59ed82c503f52`, captured
`comparison.dme`, test defines, no daemon. This is not current master, server
defines or a minimal-edit measurement. Previous self-comparison noise was 9.8%
critical CPU and 8.0% wall. Warm-up/oracle/inspection time is outside child wall.
Evidence: `E:/dmb-native-v2-phase0/r6-cohorts/compare-throughput-20261008-221855/`.
Candidate SHA-256: `d867a0eec45ad9e40e2254c750cb9f19700a94092d8c6fe96a017613fa402f1f`.
Source archive: `4248f477056941768dde1cd50e6a4e266bc76ad5329d0dea94cf0e06f4b8ebb9`.

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
The corrected source has not yet been frozen into a new optimized candidate.
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
Regenerated optimized traces remain required before critical CPU or stage-budget
claims. Shared lexical arenas, typed statement-model reuse and immutable resource
CRC changes have no accepted benchmark yet. Typed statement reuse retains the
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
identity hashing. These implementations have no accepted
post-context-fix critical CPU benchmark; neither memory targets nor Phase 1 exit
are claimed from their presence in source.

## Open correctness and architecture items

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
