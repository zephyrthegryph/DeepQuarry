# Life on the object model: benchmark

Measured 2026-09-25 on the development machine (Windows 11, BYOND 516.1687),
comparing mob Life on the object-model scheduler ([life_on_om.md](life_on_om.md),
branch `rewrite/life-om`) with master's SSmobs scheduler.

## Setup

**Old side** (`rewrite/life-bench-base`): master's Life scheduler with only its
quota bug fixed, so that the comparison is of scheduling, not of a bug. SSmobs
fires every tick (`SS_TICKER`, wait 1) and gives each fire a fixed share of the
cycle's run list (a carried fractional quota), so every mob runs exactly once
per `LIFE_NOMINAL_SECONDS` = 2 s, spread over every tick. The shipped
scheduler instead recomputed the quota from the shrinking remainder of the run
list, which is what made its real cycle 5-10 s (life_on_om.md §3).

**New side** (`rewrite/life-om`): compiled with `-DLIFE_CYCLE_DS=20`, a 2 s
cycle, so both sides run the same Life content at the same rate. The same
branch at its production cycle (6 s) is reported in the last column for
reference; it delivers a third of the frames by design.

**Both:** `-DLIFE_NO_PROFILE` (the per-system sampler compiled out on both;
the old side's `MOB_PROFILE` sampling too). Both branches contain the same
non-Life code (the new side merges the same `rewrite/om-core`), including the
object-model core fixes, so only the Life scheduler differs.

**Scenario** `life_sweep` (`code/modules/benchmarks/life_sweep.dm`, identical
on both branches; each side supplies three adapter procs): one boot measures
four configurations in turn on a 26x26 fixture floor with station air. For
each: spawn, settle 12 s, measure a 40 s window, delete.

| config | mobs |
|---|---|
| h32 | 32 humans |
| h128 | 128 humans |
| h512 | 512 humans |
| mix | 64 humans, 96 busy mice (a long sleep keeps their status systems running), 288 idle mice (hibernate) |

Humans have `low_priority` cleared (the fixture z-level has no players).

**Boots:** interleaved (old, new, old, new, ...), 7 per side; the first pair is
a warm-up and is dropped, leaving **n = 6 per side**, plus 3 boots of the new
side at 6 s. Runs: `data/bench/runs/` in each worktree, old
`20260925T154115`...`164333`, new `154718`...`164940`, production
`165546`...`170752`.

**Statistics:** mean ± 95% confidence half-width (Student t, n - 1 degrees of
freedom). Ratios: new/old of the means, with the half-width from the
propagated relative CIs.

**Metrics:** `tick_*` is the whole server's tick usage over the window (from
the MC's per-tick samples). `life_frames_per_mob_s` counts Life frames
delivered to living mobs (old: `Life()` calls; new: `life_frame()` calls),
per mob per second. `life_ms_per_s` is time spent inside the subsystem that
runs Life (old: SSmobs.fire; new: SSbehaviours.fire, which also includes the
wakes, deadlines and status expiries Life now drives). `life_us_per_frame` is
their ratio. Memory is the DreamDaemon process's private bytes after spawning
minus before (external sampler).

## Results

### 32 humans

| metric | old (2 s) | new (2 s) | new/old | new (6 s, production) |
|---|---|---|---|---|
| tick avg (%) | 4.57 ± 0.06 | 4.66 ± 0.11 | 1.02 ± 0.03 | 3.35 ± 0.02 |
| tick p95 (%) | 8.2 ± 0.4 | 8.3 ± 0.5 | 1.02 ± 0.09 | 7.3 ± 1.4 |
| tick p99 (%) | 10.2 ± 0.8 | 10.8 ± 0.4 | 1.07 ± 0.09 | 10.3 ± 1.4 |
| frames per mob per s | 0.500 | 0.547 | 1.09 | 0.191 |
| Life ms per s | 19.3 ± 0.4 | 22.0 ± 0.6 | 1.14 ± 0.04 | 9.0 ± 0.2 |
| µs per frame | 1204 ± 23 | 1255 ± 36 | 1.04 ± 0.04 | 1477 ± 31 |

### 128 humans

| metric | old (2 s) | new (2 s) | new/old | new (6 s) |
|---|---|---|---|---|
| tick avg (%) | 9.92 ± 0.23 | 10.50 ± 0.25 | 1.06 ± 0.04 | 5.40 ± 0.14 |
| tick p95 (%) | 14.0 ± 0.7 | 14.3 ± 1.1 | 1.02 ± 0.09 | 8.7 ± 1.4 |
| tick p99 (%) | 16.2 ± 0.8 | 16.8 ± 1.2 | 1.04 ± 0.09 | 10.7 ± 1.4 |
| frames per mob per s | 0.500 | 0.512 | 1.02 | 0.169 |
| Life ms per s | 70.7 ± 1.6 | 79.0 ± 1.7 | 1.12 ± 0.03 | 28.9 ± 1.0 |
| µs per frame | 1104 ± 24 | 1205 ± 26 | 1.09 ± 0.03 | 1337 ± 45 |
| memory after spawn (MB) | 0.6 ± 0.6 | 0.4 ± 0.3 | - | 0.2 ± 0.4 |

### 512 humans

| metric | old (2 s) | new (2 s) | new/old | new (6 s) |
|---|---|---|---|---|
| tick avg (%) | 29.70 ± 0.52 | 28.71 ± 0.11 | 0.97 ± 0.02 | 13.48 ± 0.11 |
| tick p95 (%) | 37.0 ± 1.6 | 35.0 ± 0.0 | 0.95 ± 0.04 | 18.0 ± 0.0 |
| tick p99 (%) | 42.0 ± 2.1 | 40.0 ± 0.0 | 0.95 ± 0.05 | 21.7 ± 1.4 |
| frames per mob per s | 0.500 | 0.488 ± 0.007 | 0.98 ± 0.01 | 0.168 |
| Life ms per s | 263.6 ± 4.5 | 258.4 ± 0.5 | 0.98 ± 0.02 | 107.6 ± 1.0 |
| µs per frame | 1030 ± 17 | 1034 ± 16 | 1.00 ± 0.02 | 1251 ± 12 |
| memory after spawn (MB) | 14.7 ± 1.6 | 14.6 ± 1.5 | 1.00 ± 0.15 | 14.2 ± 2.5 |
| life ring: dropped frames (breaches) | - | 304 ± 114 | - | 0 |

### Mix: 64 humans, 96 busy mice, 288 idle mice

| metric | old (2 s) | new (2 s) | new/old | new (6 s) |
|---|---|---|---|---|
| tick avg (%) | 7.29 ± 0.30 | 8.21 ± 0.31 | 1.13 ± 0.06 | 4.95 ± 0.05 |
| tick p95 (%) | 26.8 ± 1.7 | 11.5 ± 0.6 | **0.43 ± 0.03** | 9.0 ± 0.0 |
| tick p99 (%) | 32.7 ± 3.4 | 13.7 ± 0.9 | **0.42 ± 0.05** | 11.7 ± 1.4 |
| frames per mob per s | 0.227 | 0.230 | 1.02 | 0.093 |
| Life ms per s | 43.8 ± 1.9 | 56.3 ± 2.2 | 1.28 ± 0.08 | 23.8 ± 0.4 |
| µs per frame | 431 ± 19 | 546 ± 22 | 1.26 ± 0.08 | 573 ± 10 |
| hibernating mobs | 288 | 288 | 1.00 | 209 ± 5 |

The h32 memory delta is unusable (the first mark of a boot still includes the
boot-time peak, which the process returns during h32); memory for the mix is
below the sampler's resolution.

## Reading it

- **Tick distribution.** At 32-512 humans the tails are equal within the CIs,
  and at 512 slightly better (p99 0.95x). In the mix the new scheduler's p95
  and p99 are **less than half** of the old one's: the old SSmobs walks the
  whole `GLOB.mob_list` every cycle, hibernating mobs included (it skips them
  one by one after popping them), and a cycle's refill makes a periodic spike;
  hibernating mobs are simply not on the object-model ring.
- **Cost per frame.** Equal at 512 humans (1.00x), 4-9% higher at 32-128
  humans, and 26% higher in the mix. The fixed cost per frame (the ring
  dispatch, the fixed-step accumulator, the frame's runlevel and z checks) is
  a few µs; what remains is wake traffic that the old scheduler handled
  inline: in the mix every busy mouse's frame decrements its sleep counter,
  which raises a status change, which queues an `on_wake` for the life and
  derive behaviours, and the derive behaviour then runs `canmove` (the old
  frame ran `canmove` inline). Repeated changes within a pass are already
  coalesced to one test (om core commit 6309dc2bf9, which took the human
  frame's overhead from +12-15% to +0-9%).
- **Frames delivered.** At 32 and 128 humans the new side delivers 2-9% more
  frames than the nominal rate: a mob's first frame arrives within one
  interval of joining the ring, and the window starts 12 s after the spawn,
  when the step accumulators of freshly spawned mobs are still catching up.
  At 512 humans it delivers 2% fewer: spawning 512 humans in one burst stalls
  the server for several seconds, the ring falls more than a whole interval
  behind, and `max_catchup = 2` drops the frames beyond two per mob (304
  breaches). The old scheduler never drops frames; it just runs them late. At
  the production cycle there were no breaches.
- **Memory.** The same within the sampler's resolution: ~14.6 MB for 512
  humans on both. The per-mob Life state is a handful of vars and lazy lists
  on both sides; the object model adds one record per mob.
- **Production cycle.** At 6 s the new scheduler costs 2.4-2.9x less Life
  time per second than either side at 2 s, which is the point of keeping the
  cycle at the old effective rate (life_on_om.md §3). Per-frame cost is 15-20%
  higher there because fixed per-pass costs (wakes, derive, deadlines) are
  spread over a third of the frames.

## Diagnostics

- The object-model scheduler's per-behaviour counters (`om_diagnostics()`) are
  recorded per configuration (`<config>_scheduler` details). They are
  cumulative since boot; in these runs every deferral and breach came from the
  512-human configuration.
- The Windows process sampler recorded nothing before this work: PowerShell's
  `-Command` does not bind trailing arguments to `$args`. Fixed in om-core
  commit e57cb32457; every earlier benchmark's memory and CPU figures are 0.

## Reproducing

```sh
# old side
cd E:/projects/dq-wt/lifebase   # rewrite/life-bench-base
tools/build/build.sh bench --scenario=life_sweep -DLIFE_NO_PROFILE
# new side, same cycle
cd E:/projects/dq-wt/lifeom     # rewrite/life-om
tools/build/build.sh bench --scenario=life_sweep -DLIFE_NO_PROFILE -DLIFE_CYCLE_DS=20
```

Alternate the two, one boot at a time, and never run anything else on the
machine meanwhile (two overlapping runners contaminated an earlier attempt).


## Rerun after the Life perf fixes and the status/immunity rewrite (commit 612d0d463e)

Same scenario and build flags; cut down on request: **3 boots per side**, interleaved
(old, new, old, ...), no warm-up dropped, and only the 128-human and mix configurations
reported (the scenario still measures all four). Old side: `rewrite/life-bench-base`
(67664975d5). Plus **one** boot each of master's scheduler *as it ran* (new branch
`rewrite/life-bench-master`, 001660e596: 0.25 s wait, `ceil(remaining / 8)` quota) and of
the new side at the production 6 s cycle.

Caveat: the machine was much noisier than in the first run (the old side's h128 Life cost
was 88.5 ms/s here vs 70.7 before, with one new-side boot an outlier), and n = 3, so the
CIs are wide; only large differences are meaningful.

Mix note: the new side now has **384** hibernating mobs, not 288. The 96 "busy" mice kept
Life running only because their sleep counter was decremented every frame; sleep is now a
timed status, so they hibernate. Frames per mob per second drop accordingly (0.139 vs
0.224) and µs per frame rises because only the 64 humans still run frames.

### New (2 s) vs old (2 s)

#### h128

| metric | old (2 s) | new (2 s) | new/old | new (6 s) |
|---|---|---|---|---|
| tick avg (%) | 12.47 ± 0.30 | 13.14 ± 4.99 | 1.05 ± 0.40 | 17.02 |
| tick p95 (%) | 18.0 | 18.7 ± 7.6 | 1.04 ± 0.42 | 57.0 |
| tick p99 (%) | 20.3 ± 1.4 | 21.7 ± 10.0 | 1.07 ± 0.50 | 86.0 |
| frames per mob per s | 0.500 ± 0.000 | 0.512 ± 0.001 | 1.02 ± 0.00 | 0.164 |
| Life ms per s | 88.5 ± 2.9 | 99.8 ± 38.8 | 1.13 ± 0.44 | 51.5 |
| us per frame | 1382 ± 46 | 1522 ± 592 | 1.10 ± 0.43 | 2453 |
| memory after spawn (MB) | 0.3 ± 0.4 | 0.3 ± 0.5 | 1.00 ± 2.41 | 0.2 |
| hibernating mobs | 0 | 0 | - | 0 |
| life ring: dropped frames (breaches) | - | 0 | - | 0 |


| metric | old (2 s) | new (2 s) | new/old | new (6 s) |
|---|---|---|---|---|
| tick avg (%) | 33.95 ± 3.86 | 28.70 ± 0.24 | 0.85 ± 0.10 | 27.13 |
| tick p95 (%) | 45.0 ± 17.4 | 38.3 ± 1.4 | 0.85 ± 0.33 | 56.0 |
| tick p99 (%) | 54.3 ± 31.6 | 43.0 ± 6.6 | 0.79 ± 0.48 | 83.0 |
| frames per mob per s | 0.499 ± 0.004 | 0.318 ± 0.106 | 0.64 ± 0.21 | 0.172 |
| Life ms per s | 296.7 ± 32.5 | 252.1 ± 9.1 | 0.85 ± 0.10 | 183.1 |
| us per frame | 1161 ± 136 | 1568 ± 502 | 1.35 ± 0.46 | 2079 |
| memory after spawn (MB) | 15.9 ± 3.4 | 14.0 ± 8.3 | 0.88 ± 0.56 | 13.5 |
| hibernating mobs | 0 | 0 | - | 0 |
| life ring: dropped frames (breaches) | - | 2842 ± 1583 | - | 0 |
#### mix

| metric | old (2 s) | new (2 s) | new/old | new (6 s) |
|---|---|---|---|---|
| tick avg (%) | 12.96 ± 19.02 | 9.97 ± 3.64 | 0.77 ± 1.16 | 6.76 |
| tick p95 (%) | 45.3 ± 61.9 | 15.0 ± 6.6 | 0.33 ± 0.47 | 13.0 |
| tick p99 (%) | 58.3 ± 89.9 | 18.7 ± 7.6 | 0.32 ± 0.51 | 18.0 |
| frames per mob per s | 0.224 ± 0.011 | 0.139 ± 0.000 | 0.62 ± 0.03 | 0.089 |
| Life ms per s | 57.1 ± 34.8 | 65.4 ± 24.8 | 1.15 ± 0.82 | 31.1 |
| us per frame | 572 ± 380 | 1050 ± 398 | 1.84 ± 1.41 | 781 |
| memory after spawn (MB) | 0.0 | 0.0 | - | 1.5 |
| hibernating mobs | 288 | 384 | 1.33 | 329 |
| life ring: dropped frames (breaches) | - | 3066 ± 1733 | - | 0 |

### Master as it ran vs new at 6 s (one boot each)

#### h128

| metric | master (as it ran) | new (6 s) | new/master |
|---|---|---|---|
| tick avg (%) | 12.62 | 17.02 | 1.35 |
| tick p95 (%) | 62.0 | 57.0 | 0.92 |
| tick p99 (%) | 84.0 | 86.0 | 1.02 |
| frames per mob per s | 0.150 | 0.164 | 1.09 |
| Life ms per s | 32.7 | 51.5 | 1.57 |
| us per frame | 1704 | 2453 | 1.44 |
| memory after spawn (MB) | 0.4 | 0.2 | 0.50 |
| hibernating mobs | 0 | 0 | - |
| life ring: dropped frames (breaches) | - | 0 | - |
#### mix

| metric | master (as it ran) | new (6 s) | new/master |
|---|---|---|---|
| tick avg (%) | 7.78 | 6.76 | 0.87 |
| tick p95 (%) | 33.0 | 13.0 | 0.39 |
| tick p99 (%) | 71.0 | 18.0 | 0.25 |
| frames per mob per s | 0.092 | 0.089 | 0.97 |
| Life ms per s | 18.3 | 31.1 | 1.70 |
| us per frame | 443 | 781 | 1.76 |
| memory after spawn (MB) | 0.0 | 1.5 | - |
| hibernating mobs | 288 | 329 | 1.14 |
| life ring: dropped frames (breaches) | - | 0 | - |

Reading it: at 128 humans the two schedulers cost the same within noise. In the mix the
tails stay far lower on the object model (p95 15 vs 45 %, p99 19 vs 58 %), as before.
Against master as it actually shipped, the 6 s cycle delivers about the same frames per
mob (master's shrinking quota gave ~6.7 s at 128 humans) with a much lower mix tail
(p99 18 vs 71 %); the single-boot human rows are within this session's noise.
