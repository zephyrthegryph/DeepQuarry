# Native compiler status - 7 October 2026

[DESIGN.md revision 5](DESIGN.md) governs the work. Phase 0 close-out is **open**. Phase 1 stage throughput is queued behind its exit gates. Disk-cache feature work is frozen; its existing code must keep compiling and passing correctness checks. The daemon and later disk caching have not met acceptance.

## What is demonstrated

- Full cold compilation and publication of a deterministic DMB/RSC pair. Corrected probes 40-42: test defines 33.139 s at two workers, 39.087 s at one; server defines 35.014 s at two. Test pair hashes match across worker counts. These are wall times with warm OS caching, not CPU acceptance results.
- Snapshot-fed `--verify` compares output bytes and diagnostics with a fresh compilation. Cohorts C, F, G, I, J and K separately compared edited and fresh DMB/RSC bytes. Historical manual output comparisons do not establish complete diagnostic-oracle coverage.
- Source-aware debug operands are emitted. Static coverage checks prove decoded boundaries, not runtime error attribution or control-flow domination.
- Existing focused gates pass where recorded in the archived receipts. A complete release workspace test result is pending; no full-suite pass is claimed here.

## What remains open

Offline normalization replay reproduced the preserved normalized report byte-for-byte (SHA256 `1e39336baf63c6a2e9132a66dbff9666c712eba0348d61b5019d45aaf14c95c2`). Evidence: `E:/dmb-native-v2-phase0/review-baseline-audit/REPORT.md`. The preserved comparison has 40 stable differing test signatures and 79 variable signatures; native blank-origin raw errors remain unassigned, and two BYOND observations ended in access violations. This is saved-channel reanalysis, not a new runtime reproduction.

Runtime parity is unresolved. The frozen baseline contains stable differences and variable observations; unlocated runtime errors remain comparison evidence. Fewer errors or more passing tests do not prove equivalence. See [phase0/POWER_RUNTIME_AUDIT.md](phase0/POWER_RUNTIME_AUDIT.md) and the frozen baseline records.

Throughput and memory targets are unmet. Historical disk-cache cohorts took 64-110 s for body edits and 56-83 s cold; sampled peak private memory was 3.0-3.5 GB. Revision 5 judges performance by critical-path CPU, total CPU and I/O at eight workers, median of three. Historical wall times at two workers are context only.

## Current close-out checklist

- [ ] Tree persistence and skip-on-limit paths are removed in the draft; post-change build and output-identity checks remain pending.
- [ ] Record full release workspace test counts and every failure.
- [ ] Produce full-project cold and body-edit traces with per-stage CPU, allocations, memory and I/O; write up their ten heaviest spans.
- [ ] Record an oracle-verified eight-worker CPU baseline, median of three; keep two-worker regression rows.
- [ ] Reproduce normalized runtime baseline and explain deterministic differences, including unlocated errors.
- [ ] Bring stages within revision 5 budgets and private memory within 1.5 GB.

## Current review implementation

The Phase 0 draft removes tree persistence, queues every computed disk-cache record and propagates population errors. Resident memo limits evict entries rather than discard population. The Windows default cache is `E:/.dmbd/cache`; population checks available space.

The no-elevation profiler writes Chrome traces, CPU/wall folded stacks and SVGs, plus CPU, allocator and process-memory summaries. The CLI counting allocator is feature-gated. Per-stage process I/O windows overlap; attributed operation bytes are partial and blocked-I/O duration is not yet measured, so complete I/O acceptance remains unevaluable.

The cleaned-up source passes `cargo check --release -p dmbc --features allocation-counting`. The full release workspace tests are running with one Cargo worker, two test threads and `CARGO_PROFILE_RELEASE_LTO=false` for this test command only. Evidence: `E:/dmb-native-v2-phase0/review-full-release-tests-cleaned.log`. The preceding LTO test build was stopped during integration-executable linking; it has no test counts and its log is preserved. Earlier compilation attempts exposed and fixed a stale symbolic-test call signature. Benchmark binaries retain the normal release LTO profile. No full-suite pass or post-change compiler performance is claimed yet.

## Benchmark records

[bench/results.jsonl](bench/results.jsonl) holds receipt-backed historical rows. Unknown critical-path CPU and I/O are `null`; total process CPU is imported only when explicitly present in the receipt. Missing metrics are not passing gates.

[bench/README.md](bench/README.md) documents the new `dmb-bench` protocol. The harness does not stop competing processes, infer CPU from wall time, or launch DreamDaemon. Its full-project acceptance run is pending profiler integration and root execution.

Historical narratives: [prior status](archive/STATUS-20261007-pre-review.md), [disk-cache cohorts](archive/PHASE2_PROGRESS-20261007-pre-review.md). Neither closes a phase.
