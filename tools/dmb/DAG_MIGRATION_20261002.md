# Disk-backed compiler migration checkpoint — 2026-10-02

Worktree branch: `codex/compiler-architecture`. Implementation is in progress.
No Rust tests, DM tests or DreamDaemon runs were performed in this iteration.
Cargo builds and real-project compiler benchmarks are the verification used.

## Implemented data flow

1. Source discovery retains immutable metadata and content-addressed authored files.
   Eviction drops decoded text while retaining disk handles, include context and proofs.
   Expansion pieces are individually addressed, shared and persisted; changed generations
   write only new source/expansion content. Disposable cache writes avoid per-file fsync;
   published output generations remain durable.
2. Segmented syntax produces immutable local AST fragments and source offsets. The
   native compiler consumes borrowed declaration fragments; structural skeleton misses
   materialize only their declaration projection. Procedure body text is fetched on misses.
3. Symbolic owners use persistent maps and per-owner recipe nodes. Defaults save exact
   positive and negative observations. The same observations feed shared typed Salsa
   inputs and persisted candidate validity, refreshed once per immutable model generation.
4. Procedure candidates use compact interned facts, values and reverse dependency edges.
   Requested headers/payloads load in source order. Decoded residency is independent of
   validity; output fragments replay ordered allocation recipes and typed relocations.
5. Resource inventories persist independently of source retention. Named asset entries
   are immutable files; new archives stream their active deterministic sequence through
   bounded buffers. Unchanged archives publish by verified identity and hardlink without
   payload loading. New physical entries accumulate; historical inactive entries are not
   included in generated RSC bytes.
6. Cache metadata uses redb with short cross-process ownership. Grouped requested reads
   amortize database opening while preserving per-group and aggregate memory bounds.
   No database handle is retained during semantic processing or output generation.
7. Analysis JSONL schema 2 uses shared syntax fragments and native owner/field/value
   queries. General expression-reference resolution and resolved parameter types remain
   explicitly unavailable; consumers must inspect coverage.

## Measurement evidence, before the latest fixes

All runs used the real DeepQuarry fixture, `CBT`, `CIBUILDING`, `CITESTING`, two
workers and a 3 GiB process limit. OS caches were not flushed.

- Run A was stopped after 961.9 seconds before completing a cold baseline.
- Run B failed at resource archive creation because a Windows strong-stamp check
  occurred while the source reader was open. Readers are now closed before that check.
- Run C timed out at the 600-second phase limit. It is a failed/incomplete benchmark,
  not a successful cold compilation timing. Its trace measured source preparation
  27.117 s, resource discovery 1.973 s, resource hashing 3.367 s, streamed archive
  creation 10.580 s, symbolic owner model 123.983 s, and declaration allocation
  226.970 s. It reached about 30,720 of 68,411 authored procedures before timeout.

The latest, not yet benchmarked fixes batch owner/default reads, directly consume
parallel owner plans, eliminate whole symbolic namespace scans and empty loose-file
probes, replace constant-cache linear eviction scans with an ordered recency index,
reuse lexical passes, and optimize the new persistent-map/query/storage dependencies
in development compiler executables. These changes require a new build and measurement;
no speedup or runtime correctness is claimed for them yet.

Raw failed-run receipts: `target/deepquarry-dag-iteration-20261002-{a,b,c}`.
The earlier successful timing report remains `ITERATION_TIMINGS_20261002.md`.

## Remaining acceptance work

Measure the rebuilt compiler on cold, unchanged, body, structural, resource and restart
cases; identify and remove remaining observed bottlenecks. Source fallback batching,
analysis reference coverage, and six-worktree performance acceptance are still open.
Runtime parity and deterministic replay gates remain deferred by the current instruction
not to run correctness suites. This checkpoint is not a declaration of 100% completion.

## Next checkpoint: measured run D and subsequent implementation

Run D completed cold compilation in 393.906 s, unchanged output in 0.208 s,
and one body edit in 443.275 s. Reverting the body took 26.987 s through a
cached output pair. The benchmark was stopped during the structural case;
these are individual successful measurements, not a completed benchmark.

The owner model stage fell from 123.983 s in C to 10.028 s in D. Detailed
traces exposed repeated database opens for already-derived owner frames,
flattened inherited-field inventories exceeding retention budgets, missing
initializer graph headers, and invocation syntax reads falling out of the
bounded decoded cache. Subsequent implementation removes those owner reads,
shares persistent parent maps, releases transient owner generations, restores
initializer headers before fact validation, and batches invocation reads in
source-order consumption windows. Expansion blobs are now lazy disk handles;
source journal coverage survives combination with independently checked assets.
Initial resource discovery repairs damaged expansion caches once and retries.

These subsequent changes still require a rebuilt benchmark. No Rust or DM
correctness tests were run. The overnight continuation remains active.

## Run E interim measurements

Rebuilt prototype: cold 250.837 s; unchanged 0.270 s; one procedure edit
86.147 s (68,410 authored procedures reused, one lowered; 13,921 generated
initializers reused with none lowered). The run is still in progress, so these
are interim successful cases. Cold compiler stage: 210.378 s. Edit compiler
stage: 72.347 s. Edit header restoration: 24.720 s for 82,438 headers, including
19.302 s requested disk reads. Metadata retention remains above the 512 MiB
pool budget and evicts the frontend; compact retention is the next target.
No runtime correctness tests were run.

Run E completed successfully as a compiler benchmark (not runtime tests):
new proc 179.523 s; new var 181.604 s; default edit 130.399 s;
asset edit 104.383 s; add resource 152.177 s; fresh cached process 0.235 s;
fresh process with body edit 87.479 s. All cases reported successful native
compilation. Compact certificates, compressed skeleton indexes, one-pass
unit hashing, and independent bytecode catalog caching were implemented after
this executable and remain unmeasured until the next build.

## Failed run F and following migration

Run F failed at cache publication with `invalid artifact key`; its 210.348 s
request is not a successful cold compilation measurement. The new independent
bytecode key incorrectly appended a plaintext world name to digest fields;
this now uses SHA-256. Its compiler stage completed in 172.902 s and showed
compact graph metadata at192.0MB versus278.4MB in E, still slightly over the
retention budget. Subsequent code replaces reverse-edge tree nodes with u32
pages, releases duplicate invocation caches, compresses source origins into
immutable affine runs, and uses MessagePack fragment metadata. Default plans
now run in bounded parallel owner windows, respecting configured worker limits.
The byte export API now materializes an archive when callers request bytes
instead of a generation, including after independent bytecode reuse.

No correctness tests were run. These following changes require run G.
