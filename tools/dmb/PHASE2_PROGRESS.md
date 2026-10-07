# Phase 2 implementation checkpoint — 2026-10-07

Phase 2 is in progress, not accepted. Phase 1's corrected full compile results
remain the uncached baseline: test 33.139 s and server 35.014 s externally at
two workers, with a warm OS file cache. No new DeepQuarry incremental timing is
claimed here. The first Phase 2 prototype uncached run completed but regressed;
see the measurement below. Newer integration changes have not been benchmarked.

## New integration checkpoint

Parser fragments now replay compact declaration/settings/body-range records with
current provenance. Declaration executable groups use the same recorded-read
disk memo as procedures. Resource-only manifests validate current demands,
positive/negative asset facts and archive identity; source-only changes can retain
the RSC without loading asset payloads. Cold resource capture releases original
payload ownership after projection. CLI/session wiring passes `cargo check -j1`.
Fourteen focused checks passed for the connected cohort: four nontext pipeline
checks (including retained source-only resources with a failing asset reader),
three input facts, two sessions, one manifest proof, one anonymous executable
memo, one resource projection, one metadata resolver, and one parser-fragment replay. Phase 2 remains
incomplete. No full test suite was run.

## First prototype measurement

Release `fccb1b2e35`, two workers, uncached full DeepQuarry plus one trivial probe
proc: **246.202 s external / 241.099 s driver**, exit 0. Peak sampled private
memory: 3,449,393,152 bytes. Frontend 41.535 s; nontext 69.617 s (asset capture
64.319 s); compilation 121.945 s (procedure lowering 86.251 s, linking 9.157 s,
composition 14.397 s); publication 3.931 s. RSC is 217,623,051 bytes and matches
the Phase 1 archive hash; DMB is 64,190,292 bytes with the added probe.

Evidence: `E:/dmb-native-v2-phase0/phase2-20261007-a-cold`. Other unrelated
Cargo/rustc builds were active. Contention is observed, but has not been proved
to explain this regression. No speedup is claimed; attribution and a controlled
repeat are required before comparing iteration performance. The run stayed under
the 285-second watchdog. No DreamDaemon or runtime tests were run.

## Regression investigation and next cohort

Release `a54bdbea0a` measurements on the same probe manifest:

| Run | External seconds | Sampled process CPU seconds | Private bytes |
| --- | ---: | ---: | ---: |
| Uncached | 80.663 | 64.422 | 2,969,776,128 |
| Initial cache population | 133.180 | 101.531 | 3,467,124,736 |
| Unchanged fresh process | 12.745 | 4.953 | 50,917,376 |
| One probe body edit | 173.260 | 104.484 | 3,365,142,528 |

All exited 0. The uncached and initial-cache artifacts match the earlier cold
hashes exactly. Body edit changes DMB to SHA256
`89360DA06712447115C3F4BCC5C7874FB8EC74A5A38400D282D07D42806848F1`;
RSC stays identical. Evidence directories use the `phase2-20261007-b-` prefix
under `E:/dmb-native-v2-phase0`. The machine was heavily loaded: a sample
observed 100% total CPU across 16 logical processors with a game, existing
DreamDaemon processes, and unrelated builds. None were stopped by this work.

The body-edit run had only 11,601 disk hits and 65,963 recomputed groups. This
exposed the pending-budget admission problem: an initial build persisted only
part of its results. The next cohort connects bounded streaming publication,
shares one mapped snapshot across consumers, removes duplicate procedure parse/
ABI preparation and per-token origin key traversal, replays relative debug and
backend diagnostics, and adds directive-interval replay. It also skips decoded
engine construction on session hits, refreshes racy output proofs, and uses bulk
NTFS directory proofs. This cohort passes `cargo check -j1`; its focused gates
are in progress and it has not been benchmarked. No target is claimed met.

The snapshot-fed `--verify` oracle journals consumed bytes and folder membership
to disk, runs a fresh child against that journal, and compares output bytes and
diagnostics. `stats`, `explain`, `gc`, configured cache leases, bounded multi-
segment compaction, and locked output eviction are now connected prototypes;
their acceptance gates remain open.

## Implemented foundation

- `dm-cache`: immutable mapped segments, independent indexes, checksums, bounded
  parsing and caller payload validation, atomic batched publication, corruption
  fallback and locked compaction. Default shared Windows cache:
  `%LOCALAPPDATA%/dmbd/cache`.
- Input facts: exact consumed source/asset content, stable Windows file identity,
  conditional stamp reuse, exact rehash mode, negative candidate evidence and
  resource folder membership. Parent folders are scanned once per capture and
  rechecked before saving a session.
- Worktree sessions under `.dmbc/input-sessions`: configured identity includes
  manifest, defines, compiler executable, engine and policy; immutable records
  are validated before reuse. Existing worktree build lock spans publication.
- CLI: `--no-cache` cold route, `--exact-inputs` rehash route, unchanged session
  reuse with pair authentication and conventional output repair.
- Lowering: one recording resolver, mandatory ancestry/override reads, complete
  semantic answer encoding and production memo wrappers. Shared disk entries
  validate exact keys and all recorded answers before reconstruction.
- Expansion: include-region text reuse with actual positive/negative macro reads,
  executed location reads and current source/definition origin replay. Directive
  interpretation and joined grammar parsing still run fresh.
- Maps: persistent syntax and symbolic geometry reuse with exact keys, recorded
  resolver answers and current occurrence rebinding. Disk admission is independent
  of resident model admission; no resource payload enters map records.
- Admission: bounded pending/resident storage and a shared compact binary variant
  envelope. Output digest capture/validation streams large files in 64 KiB buffers.
- Output pairs: first-use authentication, same-process stamp memo, exact verify;
  installation authenticates staged copies against the verified manifest.

## Checks at the foundation checkpoint

`cargo check -j1 -p dmbc` passed. Twenty-four focused tests passed: five cache
storage/framing/corruption/concurrency tests; three input snapshot tests; two session
tests; two resolver-read tests; three actual frontend procedure restart/default/
arena-shift tests; four map tests; three expansion tests; one semantic read-wire
test; one pair corruption test. No full Rust suite,
DreamDaemon, DM runtime suite or administrative profiler was run.

## Still required

- Broader declaration-fragment coverage within the expansion memo. Directive
  planning must remain authoritative until incoming conditional/include/FILE_DIR
  state and ordered effects have complete replay semantics.
- Relative procedure debug/diagnostic rebasing. Current provenance-shift misses
  are safe but over-invalidate; arena-offset moves alone now reuse. Error diagnostics
  still recompute; helper/modified descriptor results currently miss on disk.
- Benchmark resource metadata/unchanged archive reuse on source-only edits and
  prove cold/incremental output equivalence for the connected paths.
- Same-snapshot cold verification, explain/stats, eviction reachability and
  six-worktree acceptance, then real DeepQuarry unchanged/body/structural timings.

The Phase 2 speed and correctness gates in DESIGN.md have not passed yet.

## Current regression-fix cohort (not yet benchmarked)

Procedure population now flushes bounded batches rather than discarding the
majority of a full project's lowered results. Expansion and map publication are
being migrated to the same path. Executable, preprocessing, parser and map DTOs
use the shared bounded `dm-wire` binary framing, with new cache schema versions;
old records safely miss. Private helper and modified-instance issuers reconstruct
against current semantic proofs. Verification now explicitly rejects crashes and
compares streaming reads without assuming equal read chunk boundaries.

The previous body-edit regression is still the latest measured result. These
changes must pass focused replay checks and a complete build measurement before
claiming it is fixed. Phase 2's targets and history/concurrency gates remain open.
### Focused checks on the regression-fix cohort

The unified procedure disk admission passed five procedure memo tests and four
private/executable wire tests. Captured policy preparation, seven map memo tests,
two streaming expansion tests, two verification comparison/filter tests, and the
Windows alternate-name negative-proof fixture passed. Eight preprocessing memo
checks passed, including exact streaming-key equivalence, directive effects,
macro-read invalidation and current-origin replay. No full suite or DM runtime
was launched. Session/used-root checks after their newest edits and real complete
CLI benchmarks remain pending. One Cargo process, `-j1`, is building the release
snapshot; unrelated system processes are left running.

Added binary session schema 2 (`.bin` receipts): old sessions safely miss. An
observed validation path reads an authenticated receipt once rather than twice.
Cache leases now retain accessed records plus newly published keys, with bounded
used-key accounting; corruption-driven supersedes sets refresh only when a new
segment rejection occurs. Production hit paths admit typed records once,
retaining decoded candidates instead of repeated deserialization and byte copies.
## Regression-fix release measurements, 2026-10-07 C cohort

Executable SHA-256 `175C5583516DAE770F8B82C6385647CFF52D0D6ABA09276C4A7AEB59FEE97DAB`.
Same owned DeepQuarry probe manifest, workers 2, fresh CLI processes, warm OS
filesystem cache, 285-second per-run watchdog. External times through conventional
output installation (artifact hashing outside timer):

| Scope | Seconds | Sampled CPU s | Peak private bytes |
|---|---:|---:|---:|
| Populate compiler caches | 106.474 | 87.438 | 3,364,589,568 |
| Unchanged session hit | 5.168 | 3.313 | 37,994,496 |
| One procedure body edit | 84.243 | 67.266 | 3,104,772,096 |

Population recomputed 77,564 groups, unsupported_disk=0. Body edit reused 77,563
and recomputed one; pending_dropped=0 and publication_failed=0. The incomplete
population defect is repaired. Relative to B-cohort observations, population
133.180→106.474, unchanged12.745→5.168, body173.260→84.243. Competing Cargo/rustc
process count was 10–11; they were left untouched. These are whole CLI timings,
not isolated causal speedups or met design targets.

Body stage seconds: frontend12.347, resources/maps7.148, ABI3.144,
initialization4.772, lowering10.656, link8.784, composition4.883,
publication11.683; driver total78.928. Aggregate key preparation3.183 and
lookup7.387 (worker-scope times). Body DMB SHA-256
`3D257867FF0A759E117FA32C35E12DA54E2D97EB39DC8A6E46B4F3193F825CE3`,
RSC `BD29B5132EDFDB697B53C4666733A99A1D3A7F49083576E6023926B041AB3585`.
Receipts under `E:/dmb-native-v2-phase0/phase2-20261007-c-*`.

Next cohort adds single linked-image reuse, bulk publication freshness proofs,
and session validation breakdown counters. It is not included in these numbers.
Cold same-input comparison is running. Phase2 remains incomplete.
C cold (`--no-cache`, fresh CLI, warm OS cache) completed in53.267s external,
51.508s driver,56.531 CPU s,2,995,015,680 peak private bytes. Its DMB and RSC
hashes match the body-edit run exactly. This is one controlled same-input cold
comparison, not the required300-commit oracle or BYOND runtime parity.

Actual CLI `--verify` passed a tiny source fixture against its disk-journal cold
oracle; six actual compiler processes passed cold/warm/body-edit/cold-oracle and
same-session serialization on tiny independent projects. `stats` and `explain`
were exercised: the normal tiny compile reported one disk hit and its exact
procedure path. Tiny concurrency establishes contract plumbing only, not six
DeepQuarry worktrees' performance/memory acceptance.
## E cohort regression investigation

Release SHA256 90D8190DA5592A9E350F1AB194F944422F5F685B5CEA3E7CCB1F197583F94ABB.
Population110.444s, unchanged4.521s, bodyedit122.407s external, workers2,
watchdog285s, warm OS cache. Competing Cargo/rustc13-21, left alone.
Unchanged receipt1.200s, bulk capture0.918s, input validation1.859s,
pair verification0.144s, output validation0.000s; rehashed0.
Body disk46291/recomputed31273, all recorded misses NoExactVariant;
Body-run publication had no failures or pending drops; population failures
were found afterward as documented below. No end-to-end target met.
Artifacts E:/dmb-native-v2-phase0/phase2-20261007-e-*.

Following source cohort adds bounded worker declaration adaptation, certified
opcode feature reuse, private structural-validation receipts, exact path proof
indexes and parent-membership missing-directory proofs. Boot-scoped output
verification receipts implement D22 and require strong identities/stamps;
exact mode remains hashing. These changes are not in E measurements.
Root cause of E partial reuse: population reported publication_failed31272,
published45728, eight bounded StorageFull OS112 errors. Missing records account
for all31273 body recomputations (31272 lost records plus changed probe).
Earlier body-run publication_failed0 does NOT prove population completed.
DMB_CACHE_DIR now permits explicitly selecting a spacious cache drive; errors
are surfaced in CLI diagnostics. Isolated follow-up cache must be on D:, not
crowded C: or E:. No measured speed claim for this unbuilt cohort.
