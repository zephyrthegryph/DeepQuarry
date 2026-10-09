# Native compiler status

Updated 9 October 2026. Binding plan: DESIGN.md revision 6.

## Latest admitted measurement

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

The next batch passed release all-target Clippy (160.24 s), receipt
`E:/dq-cache/dmb-native-v2/r6-workspace-tests-20261009-004411.json`, and 1,516
ordinary workspace library checks (147.41 s), receipt
`E:/dq-cache/dmb-native-v2/r6-workspace-tests-20261009-004828.json`.
These ordinary-profile tests are not the outstanding release-profile gate.
Optional file-backed RSC publication is implemented with request-owned resource
pins held through final pair publication; sink I/O failures retain the memory
fallback and source diagnostic precedence. Generic callers retain memory output.
Its focused checks passed in that batch; full captured-project census is running
and its optimized acceptance comparison has not run. The corrected self-cohort
above does not measure this newer streamed-resource implementation.

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
