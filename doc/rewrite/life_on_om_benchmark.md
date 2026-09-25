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
