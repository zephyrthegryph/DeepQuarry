# Runtime performance profile — 2026-07-19

This profile used the Virgo minitest world on Windows, BYOND 516.1681, a
16-logical-core host, and the local release `verdigris.dll`. DreamDaemon was
launched without a window and sampled every 100 ms. The DM build had `CBT`,
`CIBUILDING`, and `CITESTING` enabled, so absolute memory is representative of
the test process rather than a production server.

The repository's byondapi revision targets the 516.1682 ABI. The local BYOND
version is one build older, so the measurements below are useful for finding
relative costs but must be repeated on 516.1682 or newer before setting release
budgets.

## Results

| Workload | TPS | Tick avg | p95 | p99 | Worst | Overruns |
|---|---:|---:|---:|---:|---:|---:|
| Idle atmos, 120 cycles | 20.00 | 2.42% | 4.07% | 20.09% | 84.74% | 0 |
| 2,304-turf pressure storm, run 1 | 19.27 | 7.04% | 32.75% | 84.95% | 4,083.96% | 6 |
| 2,304-turf pressure storm, run 2 | 19.45 | 6.12% | 3.85% | 34.96% | 3,035.74% | 6 |
| One generated-site request | 12.85 | 6.32% | 24.04% | 80.51% | 887.05% | 3 |

At a 50 ms tick budget, the two pressure-storm maxima are approximately 2.04 s
and 1.52 s. The generated-site maximum is approximately 444 ms. Percentile
variation between storm runs is caused by the small number and timing of very
large transient ticks; the six overruns and degraded TPS reproduced.

### Atmos baseline versus pressure storm

The idle map used one 120-cycle minute:

- 2,745 maximum async active turfs;
- 2,822 snapshot mixtures;
- 126 pending turfs;
- 15 ms maximum Rust worker generation;
- 4.5% of one CPU core externally;
- private memory grew from 907.3 MB to 909.5 MB.

The pressure storm alternated 500 moles of oxygen and vacuum across a 48×48
open-turf checkerboard. Across two runs it reached:

- 10,247–12,746 async active turfs;
- 10,297–12,823 snapshot mixtures;
- 2,626–2,627 pending turfs;
- 2,335–2,339 published mixtures;
- 542–1,045 ms maximum Rust worker generation;
- 15.7% of one CPU core on average, with brief multi-core sampling peaks;
- private memory growth of 18.1 MB and working-set growth of 26.3 MB.

The event therefore expanded the worker frontier by roughly 7,500–10,000 turfs,
well beyond the 2,304 directly changed turfs. The worker is bounded to one
in-flight request, so it does not accumulate a request backlog, but a generation
can take 11–21 normal server ticks to finish.

### Generated-site request

The profiled request did not produce a playable site. It failed room synthesis
after 40.47 seconds because a required reception chair had no valid placement.
The external process used 89.6% of one CPU core on average. During the request:

- private memory grew from 905.6 MB to 974.2 MB (+68.6 MB);
- working set grew from 766.4 MB to 870.3 MB (+103.9 MB);
- dynamic-z setup took about 3.86 seconds: 0.41 s z growth, 0.79 s map load,
  and 2.66 s template-bound initialization;
- the request sustained only 12.85 TPS and produced three tick overruns before
  failing.

The existing eight-seed physical-regression test also failed its first seed
during room synthesis. It never reached the intended repeated generate/release
memory soak, so lifecycle memory stability remains unmeasured.

Enabling BYOND's native proc profiler immediately around the station-layout FFI
call terminated DreamDaemon after writing the Rust request, without a DM runtime
or panic log. The same request reached DM materialization without native
profiling. Use the master-controller tick recorder and external process sampling
for generator work until this is reproduced with the required BYOND version.

## Profile hotspots and optimization candidates

The native profile is useful for the atmos run because it completed normally.
The largest relevant DM self-costs were:

- `/turf/open/update_air_ref`: 339 ms over 42,470 calls;
- `SSmachines.wake_dirty_gas_subscribers`: 258 ms over 35 calls;
- heat-exchange pipe `process()`: 149 ms over 7,630 calls;
- auxmos finish callback: 88 ms over 209 calls;
- turf adjacency pushes: 78 ms over 27,862 calls;
- katmos equalize callback: 73 ms over 11 calls.

Recommended work, in priority order:

1. Re-run on BYOND 516.1682 or newer. The local daemon does not match the
   byondapi ABI selected by Verdigris, and the generator/native-profiler crash
   cannot be classified reliably until versions match.
2. Fix generated-room candidate exhaustion on the generator branch before
   performance tuning. Failed generation currently spends roughly 40 seconds,
   adds about 69 MB private memory, and prevents lifecycle soak testing.
3. Instrument auxmos frontier growth by cause. Record newly active seeds,
   one-hop neighbors, pressure reactivations, reaction reactivations, and rejected
   publications separately. The pressure event's frontier amplification is the
   main Rust cost multiplier.
4. Make heat-exchange pipes reactive. They remain in `SSmachines` and repeatedly
   cross the FFI boundary even when pipe and environment temperatures are stable.
   Subscribe them to gas/turf temperature revisions and hibernate after several
   no-op cycles.
5. Avoid copying every gas subscriber association list on each dirty mixture.
   `wake_dirty_gas_subscribers()` calls `subscribers.Copy()` before filtering.
   A mutation-safe deferred-removal list or stable subscriber IDs would reduce
   allocation during large atmos publications.
6. Compact async gas snapshots. `snapshot_mixtures_into()` resizes its vectors to
   the full gas-arena length even when only a subset of mixture IDs participates.
   A dense ID-to-slot table would make memory and initialization proportional to
   `snapshot_mixtures` instead of the arena high-water mark.
7. Revisit fixed Rust arena reservations with production counts. Turf gas starts
   with capacity for 400,000 nodes and 1,500,000 edges; turf heat reserves 650,250
   nodes and 1,300,500 edges; gas storage reserves 240,000 mixtures and revisions.
   The heat node reservation is notably larger than the documented roughly
   368,000 live atmospheric turfs. Record actual node/edge high-water marks on a
   full round before lowering these values.
8. Cache or incrementally maintain dynamic-z template bounds. Their 2.66-second
   initialization was the largest measured z-allocation phase.

## Reproduction harness

`code/modules/unit_tests/dq_performance_profile_tests.dm` is compiled into no
normal tests unless one of these defines is supplied:

- `DQ_PERF_ATMOS_BASELINE`
- `DQ_PERF_ATMOS`
- `DQ_PERF_GENERATION`

Each mode focuses only its profiling test and writes a single JSON result marker
to `tests.log`. DreamDaemon should be launched with `CreateNoWindow`, a hidden
window style, and `-invisible` when profiling locally.

## Generation memory ownership audit

The generation soak now records `PERF_GENERATION_MEMORY` snapshots at the start,
after generation, immediately after release, and after 60 air-subsystem fires.
Snapshots include the GC queues' highest-volume types, world atom count, machine
registries, expedition z ownership, and the auxmos arena's live/capacity counts.

The first generated expedition necessarily increases `world.maxz` from 3 to 4.
On the 512 by 512 minitest world this creates 262,144 engine-owned turf cells;
BYOND cannot reduce `world.maxz`, so that first allocation is permanent. Later
cycles reuse z4 through `SSexpedition.free_z` and do not add another level.

The repeatable growth beyond that fixed cost was dominated by dead
`/datum/gas_mixture/turf` handles. Their Rust arena slots were released in
`Destroy()`, but SSgarbage retained the otherwise inert DM handles in its
five-minute reference-check queue. One post-release snapshot contained 19,961
of these after one cycle, 39,920 after two, and 59,879 after three. Gas handles
now clear their last owned list and return `QDEL_HINT_IWILLGC`, allowing BYOND to
collect them naturally after the auxmos slot is unregistered. The same one-cycle
snapshot subsequently contained zero gas handles in the GC queues. Total queued
objects fell from 24,186 to 4,220, an 82.6% reduction.

Pipe-network teardown also now nulls its membership lists and releases the
pipeline-owned gas handle. This removed another 554 queued objects in the
controlled one-cycle comparison. Machine registries returned from 4,438 live
machines during generation to the 1,415 baseline after every release, so they
are not retaining generated machinery.

The remaining 4,220 delayed objects are predominantly generated content whose
owners and children are qdeleted together: 922 supply pipes, 787 syringes, 763
autoinjectors, and smaller reagent-container and fixture groups. They are absent
from live machine registries but fail the one-second GC filter because related
objects are still being dismantled in the same teardown. Correcting their
ownership order belongs with the generated-station lifecycle implementation;
this audit did not alter that implementation.

Auxmos is capacity-retaining rather than live-growing across reuse. After the
first z-level allocation its gas arena remained at 106,311 slots with 136,384
capacity, and its turf arena remained about 101,956 live entries with 114,688
capacity. Dirty-baseline and pending-work counts returned close to idle after
release. Those reserved Rust vectors explain part of the process high-water mark
but do not grow per reused generation cycle.

### Incremental generator integration check

The later generator work adds a resumable materialization job, production
startup z-level preallocation, and incremental teardown. With the same seed and
minitest fixture, three materializations completed in 19.11, 19.81, and 16.76
seconds. End-to-end generation completed in 26.60, 24.73, and 21.19 seconds,
roughly twice as fast as the earlier 43.84–50.99 second runs.

The tick-budget implementation is not yet sufficient to guarantee 40 TPS.
Internal telemetry reported 1,027–1,210 budget yields, but its largest
uninterrupted slices were 388.68%, 470.68%, and 785.67% of a 25 ms tick. The
worst phases were `Filtering tool-room furnishing sockets` and `Installing
emergency equipment`. The profiling test also observed only zero to three full
Master Controller cycles while each generation was active because the focused
unit-test subsystem itself remains on the active call stack. Those MC-derived
TPS samples are therefore not a valid production TPS measurement, but the
multi-tick internal slices independently prove that materialization can still
cause visible stalls. A peer `sleep(0)` latency sampler also prevented the job
from completing within several minutes, so `sleep(0)` is not a suitable basis
for the standalone latency harness.

Memory and teardown behavior remained stable relative to the post-GC fix:
machines returned from 4,438 to the 1,415 baseline and auxmos arena capacities
plateaued after z4 was allocated. The delayed GC queue remained about 4,207
objects per cycle, dominated by nested generated pipes and medical contents.

## Post-fix verification

The same host and BYOND 516.1681 installation were used after the first six
optimization measures. This remains a relative comparison because the local
BYOND build is one patch behind the Verdigris byondapi target.

The 2,304-turf pressure storm now sustained 20.00 TPS with no overruns in two
consecutive runs. The cleaner sampled run measured 2.61% average tick usage,
2.31% p95, 2.99% p99, and an 80.75% worst tick. Rust worker generation fell
from 542-1,045 ms to 45 ms, a 91.7-95.7% reduction. One-core CPU utilization
during the sampled test fell from 15.7% to 10.6%.

New frontier counters explain the remaining peak:

- 12,671 external/pending seeds were accepted at the busiest generation;
- one-hop expansion produced 12,746 active turfs;
- only 2,517 divergent turfs were retained for the next generation.

Previously each divergent turf also retained all of its neighbors, repeatedly
amplifying the next frontier. Processing now performs the one-hop expansion
once, when a generation begins.

Relevant DM profiler self-costs also declined:

- gas-subscriber wakeup: 258 ms to 132 ms (48.8% lower);
- heat-exchange pipe processing: 149 ms to 49 ms (67.1% lower);
- `update_air_ref`: 339 ms to 244 ms (28.0% lower);
- auxmos finish callback: 88 ms to 64 ms (27.3% lower).

Private memory grew 19.8 MB during the clean storm sample versus 18.1 MB before.
That workload touches most of the live arena at its peak, so the dense snapshot
change is not expected to reduce its transient high-water mark materially. Its
benefit is proportional storage on ordinary generations where only a small
subset of mixture IDs participates. A Rust unit assertion now verifies that a
one-ID snapshot stores one mixture rather than an arena-sized mixture vector.

## Extended boundary and asset-loading pass

Follow-up tests used BYOND 516.1684, satisfying the byondapi version floor. A
96x96 (9,216-turf) checkerboard sustained 20.01 TPS with zero overruns, 4.37%
average tick usage, 53.97% p99, and a 76 ms maximum Rust generation.

Expanding the fixture to the full 98x98 minitest boundary exposed two benchmark
confounders. Deferred spritesheet jobs were all launched concurrently, allowing
their completion and asset-registration phases to cluster during the atmos
window. Batched generation is now limited to two concurrent jobs. The profiler
also showed that replacing BYOND resource hashing with a direct rust-g file hash
was slower on this workload, so that experiment was reverted.

More importantly, `performance_window(seconds)` estimated the starting sample
from target FPS. When actual TPS fell, it selected more samples than the test
had produced and reached backward into fixture construction. Performance tests
now capture an exact master-controller sample index and pass it to
`performance_window`, preventing startup or fixture ticks from being reported
as workload overruns. The extreme modes remain available as
`DQ_PERF_ATMOS_HUGE` (96x96) and `DQ_PERF_ATMOS_EXTREME` (the largest square
that fits the active map).

## 40 TPS verification

The server default and `change_fps()` fallback are now 40 TPS. Isolated tests
used BYOND 516.1684 and waited for deferred asset generation and its one-time
icon-cache cleanup before opening the measurement window.

- Idle atmos control: 39.99 TPS, 3.02% average tick usage, 2.83% p95,
  3.45% p99, 72.62% maximum, and zero overruns across 2,391 samples.
- 2,304-turf pressure storm: 39.97 TPS, 3.47% average tick usage, 2.61% p95,
  3.54% p99, 80.07% maximum, and zero overruns across 2,387 samples.
- The storm's asynchronous Rust generation peaked at 39 ms. Since it did not
  block the master-controller tick, it produced no tick overrun.

An earlier control run captured a 181 ms `Asset Loading` icon-cache cleanup
after the queue appeared empty. The asset subsystem now clears its transition
state after cleanup, and performance fixtures wait for that state as well as
the queue and active-job counters. Benchmark build flags also suppress local
`dq_focus.dm` selections, so developer-focused tests cannot displace a
performance fixture.

## Full event, Southern Cross, generation, and memory audit

Follow-up runs used BYOND 516.1684 at 40 TPS. The master controller now retains
the worst tick's subsystem breakdown even when it remains below 100%.

| Workload | TPS | Average | p95 | p99 | Worst | Overruns | Worst owner |
|---|---:|---:|---:|---:|---:|---:|---|
| Large explosion (8/16/24) | 39.61 | 6.64% | 12.14% | 80.14% | 110.96% | 2 | Explosions |
| Supermatter explosion (5,000 power) | 39.44 | 7.90% | 76.27% | 81.77% | 121.45% | 1 | Explosions |
| 1,024-source plasma fire, initial | 36.15 | 33.81% | 80.68% | 112.05% | 228.51% | 27 | Atmospherics |
| 1,024-source plasma fire, optimized | 39.58 | 30.65% | 80.65% | 123.32% | 143.63% | 23 | Atmospherics |
| Isolated 64x64 decompression | 39.77 | 5.55% | 70.62% | 79.34% | 95.94% | 0 | Atmospherics |
| Southern Cross idle, initial | 39.12 | 10.56% | 73.98% | 77.22% | 213.65% | 12 | Machines |
| Southern Cross idle, optimized | 39.98 | 8.94% | 73.36% | 79.23% | 95.42% | 0 | Machines |

The supermatter fixture invokes the real supermatter detonation path with only
its cinematic pull delay removed. Its one explosion tick exceeded budget by
21%; recovery remained near 40 TPS. Isolated decompression had no overruns.

The fire fixture ignites 1,024 of 4,096 pressurized tiles simultaneously. It
grew to 13,476 hotspots and made 43,673 hotspot process calls. Removing three
duplicate coordinate lists from every fire group reduced the worst tick from
228.51% to 143.63% and restored throughput from 36.15 to 39.58 TPS. This
deliberately extreme workload still produces hotspot-processing overruns.

Southern Cross loaded four map files and reached the completed one-minute
sample in roughly 188-200 seconds on this host. Its unbudgeted dirty-mixture
subscriber drain could synchronously scan the full map's batch in one Machines
tick. The drain now retains its cursor and resumes across MC ticks, eliminating
all 12 idle overruns. Air alarms also no longer wake on unrelated atmos radio
status packets, and subsystem recovery preserves reactive subscription state.

### Generated-site lifecycle and memory

Three consecutive generate/release cycles succeeded without changing generator
implementation. They took 45.59, 45.43, and 43.84 seconds. Effective TPS was
20.88, 24.23, and 24.11 because synchronous generator work prevents the master
controller from producing ticks; recorded ticks had zero overruns after the
Machines fix.

- Pre-generation private memory: 780 MB.
- Generation result floors: 897, 925, and 941 MB.
- 30-second post-release floors: 918, 931, and 963 MB.
- Process high-water: 1,575 MB private / 1,570 MB working set.

The rising post-release floor is a retention warning, not proof of a live-object
leak: BYOND and Rust allocators can retain freed pages. Generator-branch follow-up
should record live site/turf/object and Rust layout-allocation counts at every
marker, then run more cycles to distinguish allocator reuse from objects retained
across `release_site()`.

### Generator integration and 40 TPS budgeting

After integrating the resumable generator work, station materialization is no
longer one synchronous 44-51 second master-controller stall. The normal job now
uses at most 40% of a 25 ms tick before yielding, leaving the remaining 60% for
the live game. Room-fragment searches yield within candidate and connectivity
loops, their connectivity queues no longer use quadratic front deletion, and
solver masks cover only each room's bounding box rather than the full 112x112
station grid.

Pressure-hull validation now enqueues each tile once, uses flat integer bitmaps,
reuses the global cardinal directions, and uses a fixed-capacity work queue.
Bitmap allocation is chunked across scheduler ticks. Emergency-closet contents
are also deferred through the normal budgeted `LateInitialize` path instead of
being spawned synchronously.

The original focused run used `sleep(0)` at generator checkpoints. That can
resume a sleeping proc again in BYOND's current scheduler tick, starving the
master controller and client map sending. Its 22.69-second completion and sparse
MC samples therefore did **not** establish 40 TPS; the earlier conclusion was
incorrect.

With checkpoints changed to a real `sleep(world.tick_lag)`, BYOND 516.1684
produced 2,535 genuine MC samples during a successful 70.75-second generation.
It sustained 36.00 TPS, with 3.41% average recorded MC usage, 6.72% p95, 41.68%
p99, 80.15% maximum, and zero MC overruns. This removes same-tick starvation and
the associated hard client freeze, but it does not yet meet the 40 TPS target.
The remaining loss is scheduler drift from materialization running in a sleeping
asynchronous proc outside the MC subsystem queue. Reaching a true 40 TPS while
generation is active requires converting materialization into resumable jobs
owned and budgeted directly by an MC subsystem, rather than further tuning sleep
durations.

A follow-up conservative cadence left one complete MC tick between generator
slices (`sleep(world.tick_lag * 2)`). It completed successfully in 146.69 seconds
and improved measured throughput to 37.32 TPS over 5,297 MC samples. It recorded
one 101.98% tick, with 58.87% attributed to BYOND/pre-MC work. This confirms that
sleep throttling can trade generation latency for smaller drift, but cannot meet
the 40 TPS requirement; it is a safety fallback, not the final architecture.

A follow-up experiment used BYOND's native `background` scheduling and
`sleep(-1)` backlog checks. A focused functional run completed in 32.44 seconds,
but it produced only three MC samples, so it did not measure live TPS. In a real
round, the same generator stalled after allocating its z-level: continuously
pending MC work can starve a background proc indefinitely. The experiment was
therefore rejected and removed. Native background execution is appropriate for
optional work that may be deferred, but not for this must-complete transactional
job.
