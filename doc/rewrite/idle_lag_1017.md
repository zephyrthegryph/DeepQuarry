# Idle station lag, 2026-10-17

Scenario: `build.sh bench --scenario=idle --profile --arg=seconds=240 -DCITESTING_FULL_MAP` (Southern Cross, no clients). The
window starts right after init, so it includes the post-boot backlog. New scenario `power_idle` samples regions, SMES and APCs over time.

## Findings

1. **Every mapped SMES was unwired, so the station had no supply.** Maps place the base `/obj/machinery/power/terminal` beside an SMES;
   since 2c17f8e3c7 the SMES adopts only `terminal/smes_input`, so `add_nearby_terminals()` found none, `unwired` became TRUE, STAT_OPERABLE
   and `working` went false and Rust was told `output_enabled = 0`. About 25 s after init all 318 APCs went from status 2 to status 0
   (`avail` 0 in every region), ran on their cells, and drained, dropped channels (flapping) and cascaded has_power re-evaluations
   (the live server's 20-30 APC_REPORT/min, POWER_DEMAND lines, STATS drain overruns and L3 shedding spikes in tidi).
2. **`refresh_sweep_track` called `REF()` for each of ~100k drawn atoms** (23.9 s self over 103k calls in the 240 s idle window, 53 s
   on a loaded machine): the top self-cost proc. The sweep list it fed only does anything when a client is in range.
3. Remaining top costs are boot backlog: `refresh_drain` / `refresh_one_inner` (first draw of ~100k atoms, drained under the lane budget
   for the first minutes), `vg_frame`, `pool_release`, `add_overlay`, `look/apply_to`.

## Fixes

- `SMES.adopt_mapped_terminals()` (late pass): a base terminal beside the unit, facing it, with no master is replaced (`replace_with`)
  by an input terminal and the unit is wired; logs `SMES_WIRED`. Test `mf_mapped_plain_terminal_wires_the_unit`.
- Production builds no longer register atoms in `refresh_sweep_list`; `refresh_sweep_step` collects the swept atoms in range of clients
  once per cycle (`refresh_sweep_collect`). Test builds keep the strict global sweep.

## Before / after (same scenario, shared loaded machine)

| | before (ff1f1a5cb0) | after |
|---|---|---|
| idle tick avg / p50 | 94.3 % / 84 % | 36.6 % / 10 % |
| idle TPS | 27.5 | 39.6 |
| overruns in window | 1042 | 124 |
| om_appearance ms/s | 368 | 165 |
| REF() self time | 23.9 s | not in top |
| APC_REPORT after init settles | 20-30/min continuing | 207 in the first 4 min, then none |
| last 1200 ticks avg usage | 22 % (powerless) | 18.9 % |

## Not done

- Cheaper channel-flip fan-out and dropping has_power from zero-draw machinery: with supply fixed an idle station no longer flips, so
  this only matters in real outages; left for a lane with a census of zero-draw types. The boot-time first-draw backlog is still the
  largest remaining idle cost.
