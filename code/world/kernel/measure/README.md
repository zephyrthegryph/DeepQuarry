# Kernel measurement

Names what every tick's time went to and how long player input waited. Unified plan step 2; it changes nothing
about what runs or when.

## What is recorded

- **Systems** (`systems.dm`). Every unit of work is charged to a named system as it finishes. behaviours belong
  to a family (`life`, `machines`, `ai_brain`, ...), each firing MC subsystem is `mc_<name>`, and work nobody owns
  goes to `sched_core`, `native_step`, `input` or `other`. The rule that maps a behaviour to its system is the header of
  `systems.dm`: `system_key` on the type, else a row of `km_system_rows()`, else the family of its type path.
- **Per-system histogram** (`histogram.dm`). 32 log-spaced bins of ms per tick, so p50 / p95 / p99 need no sort and
  no allocation. Only ticks in which the system was charged count.
- **Overrun attribution** (`meter.dm`). On a tick over 100% the top three systems, the maptick and the input cost
  are recorded, the streak counts up, each system's `overrun_share` grows, and one admin-log line names them.
  The last 1200 ticks (usage, maptick, input cost, top systems) are the **flight recorder**.
- **Input latency** (`meter.dm`, `verb_manager.dm`, `router.dm`). A queued verb is stamped when it is queued and
  when it runs; a click is stamped in `/atom/Click` and again as `ClickOn()` begins. Clicks are not queued yet
  (step 5), so today a click's wait is its event emit; the run depth says how far into the tick it ran.
- **BYOND reserve** (`TICK_BYOND_RESERVE`). The peak of `world.map_cpu`, decaying slowly. Nothing subtracts it from
  the MC's budget; it is measured for the kernel that will.

## Where to read it

| Surface | What |
|---|---|
| Stat panel, MC tab, **Kernel** view | Systems by overrun share, the input row, the streak (`km_panel_data()`) |
| Admin verb **Tick Report** | The flight recorder as a table, overruns only or all ticks |
| `km_diagnostics()["kernel"]` | The same records as data (`km_diagnostics()`) |
| `bench` | `tick_*`, `system.<id>.*` and `input_*` metrics for every scenario; `bench-compare` gates on them |

## Cost

Charging a system is a call with two `TICK_USAGE` reads around the work: once per scheduler slot, wake or deadline, once per
MC subsystem run, once per click. The tables are fixed lists sized at boot; a tick allocates nothing. Only an
overrun tick builds a string.

## Adding a system

A behaviour joins a folder's system by adding its type to that folder's row in `km_system_rows()`, or by setting
`system_key`. A new folder gets a new row. `dq_km_every_behaviour_has_a_system` fails on a row naming a type no
behaviour has.

## Attribution inside sched_core and appearance_drain

`attribution.dm` keeps one bounded table of rows (owner type, proc / declared entry / redraw reason) for timer callbacks,
change reactions and redraws, noted around the existing dispatch points with two `TICK_USAGE` reads and no allocation or
string building once a key exists. An overrun's TICK line ends with the top three rows behind `sched_core` and
`appearance_drain`; `PERF_PROFILE` carries `attribution` (top 20 callbacks, top 20 redrawn types, the post-init settle table);
`SETTLE:` summaries are logged about 2 and 10 minutes after "Initializations complete".

## Slow-tick trace

`slow_tick.dm`: work items (`run_item`), the loop's fast update and the scheduler's slow step add spans to a fixed ring as they finish
(spans of 0.25 ms or more; a full ring keeps the heaviest). A tick that closes over `slow_tick_trace_percent` (default 200, 0 = off)
is joined with the meter's systems, the timer callbacks / reactions / redraws and the native frame's parts, ranked, and written as one
`SLOW_TICK` line to the debug log (at most 12 a minute). Each phase's time that its itemised work does not cover is its own row
("phase N time not itemised"), as are the time before the MC, between phases and after `kernel.tick()`: that is what the overrun
record calls "MC other".

## The tick ledger

`ledger.dm` keeps one exclusive timeline for the kernel's iteration (from the start of the BYOND tick to `record_performance_tick()`, the
interval the performance windows average). Work sites bracket what they do with `km_ledger_enter(category, owner, proc)` /
`km_ledger_leave(token)`; entering charges the time since the last switch to the category that was current, so a Move inside a timer
callback, or an on_change hook inside a drain, takes its time out of the region around it. The categories therefore add up to the window by
construction, and `KM_CAT_UNATTRIBUTED` (time in the kernel loop outside any bracket) is the residual the old breakdown called "Not attributed".

Sites: loop top (`begin`), `record_performance_tick` (`finish`), each kernel phase and the scheduler's pass begin/end, work items by owner
(`km_ledger_item_category()`), timer callbacks and after_init fires, stat drain / stat evaluations / on_change hooks / late notices, change
reactions and redraws, the native frame and its delivery records, and `Move()` (`movement.dm`). BYOND's own time after the iteration and the
map send are noted from `/datum/tick_frame/frame_end()`.

Surfaces: the MC Health panel's "Where the tick goes" card (bars are the moving average, a row opens to its heaviest names), the Tick Report
verb, and `ledger` in PERF_PROFILE. Cost: one TICK_USAGE read and a few list writes per bracket; no string is built (names are type paths,
proc names and entries); rows are bounded per category (`KM_LEDGER_ROWS`).
