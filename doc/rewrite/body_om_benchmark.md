# Body object-model benchmark

## Comparison

The control is a separate worktree at `d58f79336c` with the current worktree's
surrounding game and FFI code overlaid, but with the prior `code/modules/body/`
implementation. The current tree has the body relationships, tracked changes,
and derived views. Both measurements use the original Life timer path; the
attempted owned reactor timer was reverted after it increased reactor wakes.
The control has baseline-only compatibility methods needed by unrelated newer
callers and old unit-test definitions. These do not run in the measured body
workload. The same benchmark source and Verdigris DLL were used on both sides;
the DLL SHA-256 was
`CCA00C601D045DFFF2BCB393724A87775685656037BD5ACDE467DAC7E114B637`.

The scenario is `mob_life_body_pipeline` (64 humans, eight Life cycles per
phase). It measures idle, normal, monitored-normal, and monitored-heavy phases
with injuries, treatment, changing affliction and modifier factors, and
external reads. It also measures spawn, teardown, process memory and Rust heap.
Each comparison has one warm-up plus five measured boots on the same host.
The workload checks each producer's immediate factor effect and checks event
and read counts. All measured boots completed with zero runtimes and the same
320 changes, 144 monitor reads, and 7,540 factor checksum.

Raw runs:

- Control: `E:/projects/CHOMPStation2-body-baseline/data/bench/runs/20260924T235753_d58f79336c_body-pre-om.json`
- Current body, original Life timer: `data/bench/runs/20260925T002905_d58f79336c_body-post-om-no-owned-life-timer.json`
- Current body plus attempted owned Life timer: `data/bench/runs/20260925T001310_d58f79336c_body-post-om.json`

| Median metric | Prior body | Object-model body |
| --- | ---: | ---: |
| Idle tick average / p95 / p99 | 6.16% / 31% / 79% | 5.73% / 29% / 76% |
| Normal tick average / p95 / p99 | 6.87% / 39% / 83% | 6.70% / 38% / 83% |
| Monitored-normal tick average / p95 / p99 | 7.17% / 45% / 83% | 7.83% / 54% / 82% |
| Monitored-heavy tick average / p95 / p99 | 7.55% / 49% / 84% | 7.49% / 46% / 81% |
| Spawn / teardown | 0.95 s / 0.67 s | 0.99 s / 0.81 s |
| Private memory after spawn / soak | 1051 / 1046 MB | 1055 / 1053 MB |
| Rust heap after spawn / soak | 109.10 / 105.27 MB | 109.10 / 105.31 MB |

Both versions held 40 TPS and had zero tick overruns. Most changes are within
run-to-run spread. Monitored-normal p95 and teardown crossed the comparison
tool's noise threshold. The p95 increase did not correspond to more total
`Life()` work in a one-run BYOND proc profile (1.05 s before, 0.99 s after in
that window), so phase scheduling may be involved. Teardown has a measurable
relationship cost: the profiled current run spent 0.28 s in 2,228 `om_unlink`
calls, versus almost none in the control. The profile totals include child
time; they are diagnostic, not additive timing components.

The attempted owned Life timer raised the *reactor* wake counter from 40 to
about 155 in heavy traffic and raised FFI traffic. It was reverted. This wake
counter does **not** count the original `SStimer` callbacks, so the increase
does not establish that Life ran more often. With the original timer, the median
reactor-wake totals across the four workload phases sum to 237 on both sides;
differences within individual 16-second windows are boundary effects.

### Why the owned Life timer cost more

`life_wake_in()` coalesces all sleeping systems on one timer per mob: an
existing earlier deadline absorbs later requests and their bits. Its current
`addtimer` callback calls `life_timer_fired()` directly. The attempted `After`
replacement kept the Life scheduling intent but routed each expiry through a
new owned `/datum/object_model/schedule_entry`: `om_claim` plus sparse states,
ownership publication, a deleting signal, reactor subscriber registration,
`vg_react_at`, reactor wake dispatch, callback invocation, `qdel`, signal and
ownership cleanup, and `vg_react_clear` from base `/datum/Destroy()`.

The five-run medians across the four 16-second workload windows were 620
reactor wakes and 15,795 FFI calls with the owned timer, versus 237 wakes and
15,061 FFI calls with `addtimer`. The extra ~383 reactor wakes closely match
the added schedule-entry timer dispatches; the original callbacks were simply
outside this counter. Roughly 734 extra FFI calls are consistent with the
per-entry reactor registration and clearance. The five-run tick medians do not
show a consistent slowdown: idle and normal average tick cost rose slightly,
while monitored-normal and monitored-heavy fell. Spawn, teardown, and memory
were similar. Thus the timer layer has demonstrable bookkeeping/FFI overhead,
but these runs do not prove a meaningful Life throughput regression.

For Life, keep the existing one-timer-per-mob path until an alternative has a
clear benefit. If all timers must use the reactor, use one persistent reactor
subscriber/token per mob and rearm its earliest deadline instead of creating
and destroying an owned schedule entry on every firing. A common benchmark
should count actual `life_timer_fired()` callbacks, `Life()` calls, timer
registrations/cancellations, and both timer backends; reactor wakes alone are
not a comparable work metric.

The Windows process sampler was repaired before these runs. Its old PowerShell
argument passing recorded zeros for memory and CPU. The corrected sampler is
the same in both worktrees. Private-memory checkpoints vary with collection
timing; the five-run steady-state difference of roughly 6 MB should not be
interpreted as an exact per-mob allocation cost.

### Native build integrity discovered during validation

A later full-suite run exposed a stale linked `vg-heat` crate: the oven energy
test failed reproducibly with the newly copied DLL, then passed after a clean
heat-crate rebuild. The earlier source/sidecar hash could stamp a Cargo output
that still contained an old local dependency. Verdigris now embeds the source
hash at compile time, verifies it and the generated export set before installing
or reusing a DLL, and cleans local workspace crates whenever provenance is
stale. The matched five-run comparison above used the same DLL bytes on both
sides and remains an internally valid comparison; it does not measure the
later lifetime fast-path change.
