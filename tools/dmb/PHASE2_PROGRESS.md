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
