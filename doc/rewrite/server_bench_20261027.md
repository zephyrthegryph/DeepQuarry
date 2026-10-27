# Live server benchmark and idle fixes, 2026-10-27

Production world (`build.sh server`, Southern Cross, `config/example`, 0 players) on a shared machine: other agents' cargo/dmbc/test
worlds ran throughout (machine CPU 46-72 %, free RAM 9-25 GB) and the user was gaming, so wall times carry about ±20 %. dd.exe ran at
Normal priority while measured. Tool: `tools/ci/server_bench_sample.py` (`sample` + `protocol`) reading the new localhost probes
`kmticks`, `kmsystems`, `churn`, `markprobe` (code/game/world.dm); each run is boot, 60 s settle, 10 min idle (lobby, then the
round that auto-starts at 2 min).

## Before / after (10 min idle, 0 players)

| | base (514a7b5 + probes) | + idle polling | + datum refresh (master e9fb35fefe) |
|---|---|---|---|
| TPS / TiDi | 37.7 / 5.7 % | 38.6 / 3.4 % | 38.5 / 3.8 % |
| tick usage mean / p50 / p95 / p99 | 19.6 / 5.0 / 81.4 / 85.9 % | 11.9 / 4.4 / 50.0 / 82.2 % | 12.9 / 4.5 / 59.4 / 82.5 % |
| scheduler core (om_core) | 93 ms/s | 41 ms/s | 43 ms/s |
| presentation (om_appearance) | 32 ms/s | 16 ms/s | 13 ms/s |
| timers fired / 10 min | 125.8 k | 46.6 k | 46.3 k |
| refreshes (draw drain) / 10 min | 152.8 k | 133.3 k | 21.3 k |
| dd.exe CPU (% of one core) | 69 | 59 | 63 (machine 66 % busy) |
| RSS idle | 1959 MB, flat | 1993 MB, flat | 2013 MB, flat |

Earlier long run (round-05.08.40): RSS 1925 MB at ready, 1971 MB after a 13 min round soak (+0.5 MB/min); Rust heap 97.6 -> 98.4 MB;
GC 19.5 k collected, 0 hard deletes, queue [70, 0, 0]. Runtime errors in dd.log: 0 (dd.log now written: `dd_log=1`).

## Boot (not improved)

Init 254-330 s (launch to lobby 312-400 s); Atoms 214-276 s of it, Atmospherics 17-24, Lighting 10-12, Assets 5-51 (load-bound).
Boot moved with machine load only. Profiled boot (AUTO_PROFILE, inflated ~2x): InitAtom 328 s over 502 k atoms; setup_run 104,
caps_init 77, engine_holder_init 70, state_changed 45 (884 k calls during map load), rel_view_set 41, datum_signature 23 (885 k),
shared_cache misses 31, emissive_blocker_attach 16 (91 k), turf/space table_initialize 20 (310 k).

## Top idle hotspots found

1. Polled every() work: vendors' slogan frame every 2 s (45 k fires), empty sleepers/cryo (capability-key gates never parked),
   started_work gate procs, external airlocks off-planet. Fixed (perf/idle-polling).
2. Every tracked write on a non-atom datum queued a full refresh (kernel histograms each tick: 49 k; lighting/material/tick meter).
   Fixed (perf/datum-refresh).
3. Each timer fire redraws its owner (`refresh_dispatched`): turrets, power monitors, sensors (code/engine/change/refresh.dm). Open.
4. `/datum/material_service` service_due: ~258 services every 10 s, synchronized (15.5 k fires), plus create/destroy churn
   (code/modules/materials/engineering/material_service.dm). Open.
5. verdigris threads burn 25-60 % of a core spread over the 14 frame-pool threads at idle while Rust frame work is ~10 ms/s.
   Running light frames off the pool (driver thread) and capping the global rayon pool did not change it: the waker is elsewhere. Open.

## Next fixes

- Stop `refresh_dispatched` redrawing after every timer (tracked writes already publish); jitter material_service schedules.
- Find the verdigris pool waker (thread names / stack sampling); then cap `SimConfig::threads`.
- Boot: skip state_changed work for writes on atoms still in map load; cache emissive blocker appearances.

Landed: perf/idle-polling and perf/datum-refresh (with the probes) in master e9fb35fefe.
