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

Primary `cpu_s`, `max_thread_cpu_s`, `exclusive_cpu_s`, folded CPU stacks and
`critical_path_cpu_s` retain calibrated `QueryThreadCycleTime` measurements as
required by DESIGN. An independent process crosscheck disagreement leaves these
estimates uncertified; `cpu_precision_scope` states that limitation.

Separately named `coarse_thread_cpu_s`, `coarse_max_thread_cpu_s`, and
`coarse_exclusive_thread_cpu_s` use independent `GetThreadTimes` kernel plus user
CPU at the same logical boundaries. `coarse_covered_thread_cpu_s` and
`coarse_cpu_crosscheck_ratio` aggregate only this audit clock. Approximately
15.625 ms accounting ticks limit precision: short spans can report zero, which
is not evidence of no work. Coarse audit fields **must not substitute** for
primary CPU in DESIGN acceptance or the benchmark harness. No metric is scaled
to another clock or to process totals. Failed samples invalidate only their
own clock's measurements.

Cycle intervals remain raw and retain their thread identity until finalization.
Each thread's naturally observed paired cycle/coarse envelope supplies its own
rate: no startup busy loop, worker busy loop, global fallback, or process-total
normalization. Stability requires at least two disjoint observed intervals with
500 ms coarse CPU each, therefore at least 1 s in the envelope. A single window
cannot certify itself. `thread_calibrations` retains status, observed CPU,
checked-window count, rate drift and quantization uncertainty. Insufficient,
failed, backwards or unstable threads leave affected stage CPU null.

Subinterval drift greater than 5% **plus** conservative coarse uncertainty
invalidates the rate. Two nominal 15.625 ms ticks bound each observed interval's
duration uncertainty; the subinterval/envelope ratio propagates both errors.
At 1 s the envelope duration uncertainty is 3.125%; a 500 ms window is 6.25%,
and the combined comparison uncertainty is larger. This is not a claim of 5%
measurement accuracy. Sub-500ms frequency changes may remain unobserved. The
independent process CPU crosscheck retains its own acceptance threshold.

`cpu_conversion_complete` is false when any observed thread cannot be converted.
`cpu_folded_omitted_threads` identifies threads excluded from the CPU folded
artifact; that artifact is partial when this list is nonempty. Chrome interval
arguments use `cpu_raw` and `cpu_raw_units` (Windows cycles or Linux native ns),
not falsely labelled converted nanoseconds. Older frozen reports used one
startup rate across all threads: their CPU metrics remain estimates requiring
their original crosscheck and must not be relabelled as per-thread measurements.
Linux uses `CLOCK_THREAD_CPUTIME_ID`.
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

Summary scope labels are additive JSON fields; existing numeric fields retain
their meanings. Reports from older frozen binaries lack these labels and must
be interpreted using the same rules:

| Metric | Scope |
| --- | --- |
| Report `wall_s` | Elapsed wall time of the profile interval. |
| Stage `wall_s` | Sum of outermost same-name intervals on each participating thread. Concurrent intervals add, so this is **not phase elapsed time**. Use the coordinator span in the Chrome trace for elapsed phase time. |
| Stage `allocations`, `allocated_bytes` | Sum of thread-local inclusive interval counter deltas. Same-name nesting counts only the outermost interval; differently named parents and children overlap. A root stage observes its own thread, not all workers, so a child worker stage may exceed the root. There is no process allocation-count total in this report. |
| Stage `peak_live_bytes` | Maximum process-wide requested live allocation bytes observed at allocations on participating stage threads. This is neither stage-owned memory nor a complete process peak during the stage. |
| Stage `sampled_peak_private_bytes` | Current process private bytes sampled while the stage is active; overlapping stages share samples. Short stages and between-sample peaks can be missed. |
| Report `peak_allocator_live_bytes` | Process-lifetime peak requested live allocation bytes recorded by the allocator, including allocations outside the profile interval. |
| Report `peak_private_bytes` | OS process-lifetime private-memory peak, including work outside the profile interval. |

For example, eight simultaneous worker intervals of four seconds contribute
roughly 32 seconds to stage `wall_s`, even if the phase finishes in four seconds.
Stage totals must not be summed to reconstruct whole-build wall time or
allocation totals. Allocation counts include successful reallocations as events;
requested byte totals count their new sizes, rather than net live-byte growth.

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

### No-elevation operation evidence and the remaining gate

The existing synchronous wrappers already provide the obtainable operation
measurements without an elevated tracing session:

| Evidence | What it establishes | What it does not establish |
| --- | --- | --- |
| Successful read/write/copy return counts | Logical bytes returned or accepted by annotated operations | Physical disk traffic, durability, or bytes transferred before an opaque error |
| Call elapsed duration and call/failure counts | Time inside the annotated synchronous operation and observed outcome | Time specifically blocked waiting for storage |
| Process I/O counter deltas | OS-reported process transfer activity, including profiler output | Exclusive stage attribution or exclusively disk-device traffic |

Cached reads and buffered writes can count logical bytes without corresponding
physical device traffic. Copy wrappers count both logical input and output;
their duration is one operation interval, not two separate storage waits.
`dm-cache` reads/writes and its lease operations still bypass these wrappers;
the report therefore cannot claim complete compiler operation coverage.

Neither `GetThreadTimes`, `QueryThreadCycleTime`, process I/O counters, nor
ordinary Rust filesystem return values identify the storage wait portion of a
call. No additional truthful blocked-storage counter follows from combining
these measurements. The blocked-I/O acceptance gate remains unavailable until
an independently validated wait/event source and its coverage are supplied.
This limitation is not resolved by renaming elapsed time or by using its
difference from thread CPU.

Process coverage bounds use `covered_cpu_bounds_method = participating_thread_interval_union`: observed inclusive intervals are unioned independently per thread, merging overlap and exact contiguity only. Missing or inconsistent paired clocks invalidate coverage. Exclusive stage bounds remain conservative per-segment bounds; their sum is correlated and can be much wider than the coverage union. No process scaling or gap filling is performed.
