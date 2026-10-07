# Compiler span profiler

`dm-profile` records instrumented compiler stages without a sampling service,
administrator permission, or external profiler. It does not change compilation
or cache decisions. This document describes the implementation, not a passing
performance or correctness gate.

## CLI and artifacts

Pass `--trace E:/profiles/cold.trace.json` to `dmbc compile`. To count allocations,
build the executable with `--features allocation-counting`; `dmbc` forwards that
feature and installs `dm_profile::CountingAllocator` as its global allocator.
The allocator delegates to `System`. Without the feature, allocation totals are
not evidence of zero allocation. A counting build retains allocator overhead
even when `--trace` is absent.

For a trace named `cold.trace.json`, artifacts are:

| File | Contents |
| --- | --- |
| `cold.trace.json` | Chrome trace: stage names, threads, wall intervals, CPU and allocator span arguments |
| `cold.trace.report.json` | Schema 1 summary, calibration, stage metrics, coverage limitations |
| `cold.trace.cpu.folded` / `.cpu.svg` | Exclusive CPU duration in nanoseconds, grouped by entered stage stack |
| `cold.trace.wall.folded` / `.wall.svg` | Exclusive entered-stack wall duration; worker durations are not end-to-end wall time |
| `cold.trace.tracing.folded` | Raw `tracing-flame` output, retained separately |

Suffixes replace the trace's final extension. Open the Chrome JSON in
[Perfetto](https://ui.perfetto.dev/), and open SVGs in a browser. Empty measured
stacks produce an SVG explicitly saying measurements are unavailable.
`--verify` traces the compiler children separately; the cold child's trace path
adds `.cold.json` to the requested path. The verification coordinator is not
included in those traces.

## API and lifecycle

```rust,ignore
let profile = dm_profile::initialize(trace_path)?;
{
    let _stage = dm_profile::stage("input_scan");
    // Instrument participating worker threads with the same stage name.
    // record_io(bytes_read, bytes_written, None) records byte counts only.
}
let report = profile.finish(&["input_scan"])?;
```

Initialize once per process; this installs the global tracing subscriber.
Stage guards are thread-bound, must nest in stack order, and must be dropped
before `finish`. With profiling inactive, stage guards skip platform clock
queries. `has_stage(name)` checks for a completed stage so a caller can select an
explicit alternate pipeline. Dropping the profile on an early error flushes
artifacts with no selected critical path. Call `finish` before `process::exit`,
which does not run destructors. Artifact write errors are reported.

## CPU accounting

Windows uses `QueryThreadCycleTime`, converted by a 250 ms startup-thread
calibration against `GetThreadTimes`. Core/frequency differences and the coarse
calibration clock can bias that rate. Linux uses `CLOCK_THREAD_CPUTIME_ID`.
Unavailable or backwards samples invalidate the affected stage's CPU metrics;
wall time is never substituted.

Entering or leaving a stage takes one CPU boundary sample shared by its frame,
inclusive interval, and parent transition. Exclusive segments therefore partition
nested CPU intervals. Each stage reports CPU summed across participating threads,
maximum accumulated CPU on one thread, and exclusive CPU. Nested inclusive
totals must not be added together.

`finish` sums per-stage thread maxima only for the caller's explicit sequential
stage list, stored in `critical_path_stages`. Missing stages or duplicate names
produce a null critical-path result. The caller must exclude overlapping parents
and children; this is a stage approximation, not automatic dependency-chain
reconstruction. Same-named worker spans contribute to the same stage maximum.

Process CPU is measured independently. `cpu_crosscheck_ratio` compares covered
exclusive thread CPU with process CPU; inspect it with the calibration and
uninstrumented-work coverage before accepting measurements. Initialization and
calibration precede the report interval, while an external process timer includes
them. Their setup time is reported separately. Profiling bookkeeping is included
in entered intervals; uninstrumented threads, including trace writers, are not
covered by the folded CPU stacks.

## Allocations, memory, and I/O

Allocation counts and requested bytes are thread-local deltas accumulated across
stage participants. They include nested work and profiler overhead. Stage
`peak_live_bytes` observes process allocator live bytes during allocations on
participating threads; it is not private memory attributable to that stage.
`peak_allocator_live_bytes` is the allocator's process-lifetime peak. Windows
`peak_private_bytes` is the OS process-lifetime peak committed private/pagefile
usage, including setup; Linux private peak is currently unavailable.

On Windows one background thread queries current `PrivateUsage` nominally every
20 ms. `sampled_peak_private_bytes` is the largest observed **process-wide** value
while the named stage was active on at least one thread. Nested and concurrent
stages share the same observation; the value is neither additive nor memory owned
by a stage. No extra OS query is made on stage entry/exit. The sampler holds the
active-stage registry lock for the single memory query so entry/exit cannot race
that observation. It wakes on shutdown and is joined before report assembly.

`private_memory_samples` counts successful observations and
`private_memory_failed_samples` counts unavailable OS queries during that stage.
A stage shorter than the sampling interval can have no observations: its sampled
peak stays null, never zero or the allocator peak. Between-sample peaks can be
missed, and sampling is subject to scheduling delay. Other platforms leave these
stage values unavailable. `private_memory_sample_interval_ms` describes the
nominal Windows cadence, not an exact measurement-resolution guarantee. Sampler
CPU and allocation overhead are included in process totals.

Stage `read_bytes` and `write_bytes` are overlapping process-wide I/O windows,
including trace writes: they are not additive or exact stage attribution.
`record_io(read, write, Option<Duration>)` separately accumulates explicitly
annotated leaf-stage bytes and an optional supplied blocked duration. These are
partial coverage. Unmeasured blocked duration stays null; a byte count does not
prove blocking time. Inspect `io_scope` and coverage notes alongside all totals.

`io_call(operation, byte_counts)` measures the wall duration of an actual
synchronous operation and records successfully returned bytes on the active leaf
stage. `io_call_elapsed_s`, `io_calls` and `io_failed_calls` describe only these
annotated calls. Elapsed time includes scheduling, kernel CPU and copying; it is
**not** storage-blocked time, and never populates `io_blocked_s`. Calls returning
errors can transfer partial bytes that their error does not expose; those bytes
are unknown, not recorded as successful transfers. With profiling disabled the
operation executes directly without clock sampling or byte-count evaluation.

Compiler coverage currently includes engine-template reads, captured filesystem
payload reads, file-hash/authentication reads, DMB/RSC writes, JSON publication
writes, and publication/install copies. Metadata/open/close/sync operations,
hardlink/rename calls, non-text asset reads and cache-store operations are not
completely covered. No complete-I/O acceptance claim follows from these samples.
Exact blocked-I/O accounting would require an OS event or scheduler wait source;
subtracting thread CPU from call wall time also includes unrelated preemption and
is insufficient. The current compiler leaves blocked duration null.
