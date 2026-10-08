# Native compiler status — 7 October 2026

[DESIGN.md revision 5](DESIGN.md) governs this work. Phase 0 close-out is **open**: the cleanup and release-suite repairs are implemented, but accepted CPU evidence and runtime parity are unresolved. Phase 1 throughput, the daemon and later disk-cache acceptance remain unfinished. New disk-cache features are frozen.

## Current evidence

- Full release workspace suite: **1,400 passed, zero failed, 92 target result rows**, in `E:/dmb-native-v2-phase0/review-per-thread-final-workspace.log`. One Cargo worker, two test threads, allocation-counting enabled; LTO disabled for tests only. This run includes parser-wire version 4, the test-module split and the per-thread profiler regressions.
- Full release workspace/all-target Clippy passed with `-D warnings` in `E:/dmb-native-v2-phase0/review-per-thread-final-clippy.log`. Formatting checks pass for every changed Rust file.
- Python Phase 0 regressions: **30 passed**, in `E:/dmb-native-v2-phase0/review-python-regressions-final.log`.
- All eighteen DeepQuarry benchmark builds (three scenarios, three repetitions, eight and two workers) passed fresh-output and diagnostic oracles. The harness completed with exit 1 because acceptance gates failed. All compiler/oracle invocations have a 285-second watchdog; full snapshot validation runs outside compiler timing.

## DeepQuarry benchmark

Frozen normal-release, thin-LTO, allocation-counting compiler SHA256: `90d504672598e67ffd5c4919edc03c5dfecefa85ed8d2891235cf2cad2665e52`. Inputs are the isolated 20,085-file snapshot documented in [bench/DEEPQUARRY.md](bench/DEEPQUARRY.md). Evidence: `E:/dmb-native-v2-phase0/review-traces-20261007-b/` and [bench/results.jsonl](bench/results.jsonl).

Eight workers, medians of three, seconds:

| Scenario | End-to-end wall | Cycle-derived critical CPU | Process CPU | Peak private memory |
|---|---:|---:|---:|---:|
| Cold | 50.68 | 38.34 | 79.41 | 3.21 GB |
| One body edit | 72.73 | 44.23 | 82.47 | 3.60 GB |
| Unchanged | 4.02 | 2.65 | 2.50 | 45.7 MB |

**The cycle-derived CPU figures are not accepted measurements.** Covered-stage CPU differs from process CPU by more than 5%; one unchanged sample reports critical CPU greater than process CPU. The profiler applies one startup-thread conversion rate to all workers. Independent thread CPU audit counters are implemented. The user approved replacing the single startup rate with per-thread calibration. The implementation retains raw thread-tagged cycles until finalization, requires two natural stability windows, and keeps insufficient or unstable measurements unknown; final compilation and fresh traces remain pending. No process-total scaling or tolerance relaxation is permitted. I/O byte budgets fail; complete blocked-I/O duration is also unavailable. Two-worker wall medians were 67.68 s cold, 83.31 s body edit and 3.72 s unchanged; these are regression context only and use the same flawed global cycle conversion. Oracle success establishes fresh-versus-cached agreement, not equivalence with BYOND runtime behavior. No performance improvement is established.

Historical 33.139-second test and 35.014-second server compilations at two workers were wall measurements with warm OS caching, not CPU acceptance results. Historical disk-cache cohorts took 64–110 seconds for body edits and 56–83 seconds cold.

## Implemented review repairs

- Removed tree persistence and skip-on-limit paths in base `988c369274`. Computed cache records are queued or evicted, never silently dropped to meet an admission budget. Population errors propagate. Default Windows cache is `E:/.dmbd/cache`, overridden by `DMB_CACHE_DIR`; free space is checked.
- Fixed declaration-fact serialization of evaluated scalar constants. Schema is 2; parser payload version is 4 so independent fragment keys cannot reuse the old representation. Added scalar round-trip and old-version rejection regressions.
- Restored the missing 303-byte embedded RSC fixture with payload-hash provenance. Restored 31 captured CRLF files only when their original receipt hashes matched; fixture attributes preserve exact bytes. Existing bytecode assertions remain strict.
- Fixed the twelve original release-suite failures. Remaining stale assertions concerned resolved global-storage identities, const parameter modifiers, discarded-call opcodes, missing-resource stage reporting and memo publication. All affected tests now pass.
- Repaired Clippy findings, preserving all worker joins and error propagation. Added nested linking spans; no linking algorithm optimization is claimed. Moved all 202 inline lowering tests into 11 modules (largest 834 lines); production `simple.rs` remains oversized and requires further trace-guided splitting.
- Profiler realloc accounting applies one atomic live-byte delta. Same-name nested spans count only outermost inclusive intervals while retaining individual trace events. CPU/wall folded stacks, Chrome traces, allocator counters and sampled process private memory need no elevation.
- Comparison helpers retain diagnostic ordering and unknown messages, reject unknown compile-error formats, and require capture-time source hashes for an oracle receipt. Snapshot validation hashes every input with two bounded workers and eight pending tasks. All benchmark assets/cache/temp files are on E:.
- Raw runtime normalization now counts blank-origin errors as unlocated evidence rather than dropping them. Historical normalized artifacts were preserved.

## Trace interpretation and queued throughput work

First cold trace, provisional maximum-thread cycle CPU for the ten heaviest declared sequential stages: resources/maps 10.92 s; symbolic linking 7.51; procedure lowering 3.93; initializers 3.34; composition 2.76; input scan 2.45; tree resolution 1.81; publication 1.53; declaration parsing 0.95; startup capture 0.92. These values identify investigation candidates but cannot certify budgets until clock accounting passes its crosscheck.

The first body edit reused 77,563 procedure records and recompiled one. It still reruns resources/maps, linking and initializer work. Resource capture performs an all-lookups scan for every literal and repeats demand discovery; these are identified candidates, not implemented savings. Linking candidates include serial freezing, debug-source maps and repeated relocation lookups. New nested spans will distinguish these costs.

Stage wall values sum entered intervals across workers, not elapsed pipeline duration. Allocation counters are thread-local inclusive deltas; worker sums can exceed the coordinator build count. Allocator-live and private-memory peaks are process observations, not memory attributable to a stage. I/O process windows overlap and include profiler writes; explicit operation duration is not blocked-storage time.

## Reduced-overhead per-thread clock audit (single cold run)

The completed eight-worker, no-cache audit used frozen compiler `305c82f867fece66385a92690368284bad7892a8368784b5bfae494a0476c2e6`. Its measured child wall time was **41.2735 s** (profiler interval 40.8399 s). The separate snapshot-fed oracle passed output and diagnostic equality. DMB SHA256 remained `50d27a3294589e482baf7eedb279cdb7a589630550ab7ba7a06d36eae044cdce` and RSC SHA256 remained `bd29b5132edfdb697b53c4666733a99a1d3a7f49083576e6023926b041ab3585`, identical to the prior c audit. Evidence: `E:/dmb-native-v2-phase0/review-batched-clock-audit-20261007-d/receipt.json`.

Trace output is smaller: Chrome JSON fell from 182,940,728 bytes in c to 62,235,708 bytes in d; tracing folded output fell from 127,606,821 to 28,448,243 bytes. The c child wall was 76.9486 s. These are single observations on a shared machine, not a compiler performance median or an acceptance claim; reduced profiler output does not establish a throughput improvement.

**CPU measurement remains invalid.** Nine observed threads lacked usable per-thread conversion, so critical-path CPU and covered primary CPU are correctly null. Process CPU was 79.2031 s. The independent coarse audit covered 70.4219 s, ratio 0.88913: about **11.1% remains uncovered**, beyond the unchanged 5% gate. Short-lived workers cannot certify two natural calibration windows; they are not assigned zero or another thread's rate. The oracle closes reduced-profiler output equivalence only. Phase 0's valid CPU baseline and median acceptance remain open.

## Runtime parity remains open

See [phase0/POWER_RUNTIME_AUDIT.md](phase0/POWER_RUNTIME_AUDIT.md). Offline replay of the historical normalizer reproduced SHA256 `1e39336baf63c6a2e9132a66dbff9666c712eba0348d61b5019d45aaf14c95c2`; that hash does not describe the corrected parser. The preserved comparison has 40 stable differing signatures and 79 variable signatures, plus two BYOND access violations. Native blank-origin errors cannot be assigned to a proc from those logs.

The preserved `nuke_cinematic` window contains native list-bounds runtime errors despite PASS; both producers report 134 runtimes. The selected pair has eight power-line-154 failure tests, rather than the review's broader nine. Frozen runtime cooldown behavior can suppress test failure reporting when blank source origins share one key. This is a concrete reporting mechanism, not proof of the actual failing receiver/index or runtime equivalence. Gameplay opcode shapes agree after ID renaming and removal of debug markers. The old native power dump lacks file/line debug instructions present in BYOND; current source emits them and its string/line binding chain is coherent. Initializer timing, current runtime repair and event ownership remain unproved. No DreamDaemon or DM tests were launched in this review run.

## Remaining gates

Worker profiling now covers expansion, startup capture and ABI preparation at worker entry. Input scanning and procedure lowering also use one worker span rather than a span per item. These coverage repairs follow the recorded single cold audit and are not represented by its timings. Short-lived ABI workers still cannot meet two 500 ms CPU calibration windows; their precise CPU contribution remains unknown. Complete acceptance requires sufficient same-thread calibration history or a documented uncertainty treatment, not a relaxed process crosscheck.

- Retain the completed eighteen-run baseline; its clock-quality failure is preserved.
- Release suite, Clippy, Python regressions and changed-file formatting gates pass; reduced-overhead profiler output/diagnostic equivalence passed its separate oracle. CPU validity remains open.
- Obtain honest high-resolution CPU measurements with independent audit counters and the unchanged 5% crosscheck; record accepted eight-worker medians.
- Complete blocked-I/O accounting or explicitly retain that gate as unevaluable.
- Resolve frozen runtime semantic differences through controlled evidence; fewer reported failures is not correctness.
- Begin worst-stage throughput work only after close-out evidence is usable; each optimization requires before/after traces. Split oversized `simple.rs` while working in its measured lowering boundaries.

Historical narratives: [prior status](archive/STATUS-20261007-pre-review.md), [disk-cache cohorts](archive/PHASE2_PROGRESS-20261007-pre-review.md). Neither closes a phase.
