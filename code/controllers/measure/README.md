# Kernel measurement

Names what every tick's time went to and how long player input waited. Unified plan step 2; it changes nothing
about what runs or when.

## What is recorded

- **Systems** (`systems.dm`). Every unit of work is charged to a named system as it finishes. OM behaviours belong
  to a family (`life`, `machines`, `ai_brain`, ...), each firing MC subsystem is `mc_<name>`, and work nobody owns
  goes to `om_core`, `om_native`, `input` or `other`. The rule that maps a behaviour to its system is the header of
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
| `om_diagnostics()["kernel"]` | The same records as data (`km_diagnostics()`) |
| `bench` | `tick_*`, `system.<id>.*` and `input_*` metrics for every scenario; `bench-compare` gates on them |

## Cost

Charging a system is a call with two `TICK_USAGE` reads around the work: once per OM slot, wake or deadline, once per
MC subsystem run, once per click. The tables are fixed lists sized at boot; a tick allocates nothing. Only an
overrun tick builds a string.

## Adding a system

A behaviour joins a folder's system by adding its type to that folder's row in `km_system_rows()`, or by setting
`system_key`. A new folder gets a new row. `dq_km_every_behaviour_has_a_system` fails on a row naming a type no
behaviour has.
