# The power grid, redone (rewrite/power-grid)

Status: stage 1 landed (area demand from contributions, area channel single writer, tests, SMES fixes); stage 2 (machines read the channel as a stat) waits on the NOPOWER conversion. See section 6. Owner: the power-grid worker. Companion to `final_api.html` section 3 (`every`), section 5
(stats, `contributes`, `hold`), section 11 (capabilities, `powered`, `powered_by`) and the Machines note; `framework_gaps.md` F7;
`intended_changes.md` (Machines, Power grid); `rust_architecture.md` step 3 and `verdigris/README.md` "M3 notes".

The decision (2026-10-06) is to redo the grid properly, not adapt it. This document inventories what is there, names what is wrong
with it, states the model that replaces it, and lists the steps, the player-visible changes and the risks.

## 1. Inventory of the current grid

### 1.1 Files

| Area | Files | Role |
|---|---|---|
| Wires | `code/modules/power/cable.dm`, `cable_ender.dm`, `cable_heavyduty.dm`, `terminal.dm`, `breaker_box.dm` | `/obj/structure/cable` pieces (d1/d2), knots, enders; terminals; breaker boxes. A piece is bound to Rust with `vg_power_bind_cable`. No DM topology code. |
| The bridge | `power_bridge.dm`, `power_grid.dm`, `power.dm` | Dirty-area flush, the power step, `power_topology_edited`, region caches (`SSmachines.power_grids`), reads (`power_avail`, `power_load`, `power_draw`, ...), the detached test grids, the engineered-conductor overlay (`material_power_graph.dm`). |
| Storage and distribution | `apc.dm`, `smes.dm`, `smes_construction.dm`, `smes_prefabs.dm`, `batteryrack.dm`, `cell.dm`, `grid_checker.dm` | APC (cell, channel settings, area push), SMES (charge, I/O levels, terminals), the rack, cells. |
| Producers | `port_gen.dm`, `generator.dm` (TEG), `solar.dm`, `tracker.dm`, `turbine.dm`, `antimatter/`, `fusion/`, `singularity/`, `supermatter/`, `tesla/` | `set_power_supply()` for steady supply, `add_avail()` for pulses (`code/domains/power/supply.dm`). |
| Area accounting | `code/game/area/areas.dm`, `code/game/machinery/machinery_power.dm` | `static_equip/light/environ` tallies, `oneoff_*`, `power_equip/light/environ`, `power_use_change`, `use_power_static`, `retally_power`, `area.powered()`, `power_change()`, the `power_machines` subscriber list. |
| Adapters | `code/domains/power/powered.dm`, `supply.dm` | `powered(channel)` (a `STAT_OPERABLE` contribution through the NOPOWER bit), `powered_by(system, role)`, the supply book. |
| Rust | `verdigris/domains/power/src/{components,kind,laws,lib}.rs`, `verdigris/ffi/src/power.rs`, `material_power.rs` | Cable graph (`Cables` network kind), the per-region ledger, `ApcTick`, SMES laws. |

About 270 files declare `use_power` and 340 set `idle_power_usage` / `active_power_usage`; 71 read an area channel var outside areas.dm
and apc.dm (lights, the AI, the electric chair, the cell charger, admin secrets).

### 1.2 Data flow today

1. **Topology.** A cable or power machine binds a node to Rust (`vg_power_bind_cable` / `vg_power_bind_machine`); every edit calls
   `power_topology_edited()`. Rust's `Cables` kind (union-find regions, merge keeps the larger id, split keeps the parent id for one
   side) owns the graph. DM keeps `power_region` on each machine, refreshed after an edit, and `SSmachines.power_grids` (a flat state
   list per region: avail, load, brownout, warning, member machines).
2. **Loads in.** Every machine reports its draw to its area as a running tally: `set_use_power`, `update_idle_power_usage`,
   `update_active_power_usage`, `update_power_channel`, `area_changed`, `Initialize`, `on_destroy` all call
   `REPORT_POWER_CONSUMPTION_CHANGE` -> `area.power_use_change(old, new, channel)` -> `use_power_static()` -> `static_*` += delta.
   One-off draws (`use_power_oneoff`) add to `oneoff_*`. Both mark the area dirty; once per power step `power_flush_areas()` writes
   `static_*` and `oneoff_*` into the area's APC component (`NATIVE_APC_STATIC_LOAD`, `NATIVE_APC_ONEOFF`) and zeroes the one-offs.
   `retally_power()` / `check_static_power()` exist because the tallies drift.
3. **The step.** The native frame (`vg_frame()`) runs Rust's laws: reset, producer credit (`supply + pulse`), SMES output offer, SMES
   input ask, `ApcTick` per APC (the cell covers what the grid cannot, the shedding ladder moves channels, charge mode), settle
   (brownout), SMES apply (pro-rata discharge and charge). DM's `process_power_begin()` (every `MACHINE_SERVICE_INTERVAL`) flushes
   area loads, commits topology (`vg_power_commit`), re-reads every region's numbers (`power_grid_refresh`) and, after an edit, every
   machine's region. `poll_power_storage()` reads each APC and SMES back (`power_poll()`), yielding over budget.
4. **Channels out.** `apc.power_poll()` copies Rust's channel settings to `equipment/lighting/environ`; when one changed
   `apply_area_power()` writes the area's `power_equip/light/environ` and calls `area.power_change()`, which tells every subscribed
   machine to `power_change()`: `set_powered(area.powered(channel))` writes the NOPOWER bit and publishes. Lights listen on the area key.
5. **Draws on the net.** `power_draw(region, amount, consumer)` (Rust `vg_power_region_draw`, never above `avail - load`) for machines
   that take from cables directly (emitters, powersinks via `drain_power`, the electrocution code).

### 1.3 Who reads and writes what

| State | Writer | Readers |
|---|---|---|
| `static_*` per area | every machine, via `REPORT_POWER_CONSUMPTION_CHANGE` (deltas) | `power_flush_areas`, `area.usage()`, tests, `check_static_power` |
| `oneoff_*` per area | `use_power_oneoff` callers (about 30) | flush, `usage()` |
| `power_equip/light/environ` | the APC (`apply_area_power`), admin secrets, the electric chair (saves and restores), APC `on_destroy` | `area.powered()`, lights, AI life, cell charger |
| NOPOWER bit | `set_powered()` | `has_stat(NOPOWER)`, `STAT_OPERABLE` via `stat_bits_allow` |
| `power_region` | `power_bind()` after a topology poll | every consumer of `power_avail` etc. |
| APC / SMES charge | Rust laws; DM adjusts with conserved deltas (`adjust_charge`) | UIs, `power_poll()` |

### 1.4 The Rust bridge's role

Rust carries real weight here and keeps it:

* **The cable graph.** Regions over thousands of pieces with batched edits (an explosion is one commit), incremental merge and split,
  ender links, vertical pieces. This is graph work DM did with flood fills before; it must not come back.
* **The ledger.** `avail`, `load`, `smes_offer_total`, brownout, settled each frame, with a conservation check (`power_apc_charge`,
  `power_smes_charge` ledger lanes) that is a property test.
* **The distributor.** `ApcTick` and the SMES laws are tiny numeric rules, but they run for every APC every frame in the same pass as
  the ledger they draw from. Moving them to DM would put a DM-side per-APC step back on the tick for no gain; they stay.

What the bridge carried that it should not: the **static-load push** (`NATIVE_APC_STATIC_LOAD` written from DM-maintained tallies) and
the DM `power_equip/...` writeback as a bare-var protocol. Those are the parts this redo replaces.

### 1.5 Hot paths

* `process_power_begin()` every service interval: flush of dirty areas, `vg_power_commit`, one `vg_power_region_read` per region, the
  region re-poll of every power machine (only after a topology edit).
* `poll_power_storage()`: one read-back per APC and SMES that Rust reported changed (a settled one costs nothing).
* A machine changing mode: one tally delta. A machine on a moving area: two deltas.
* An area channel flip: `power_change()` over `power_machines` (the `apc_flip_50` bench measures exactly this).

### 1.6 What is wrong

* The tallies are **bookkeeping that drifts**: a missed `REPORT_POWER_CONSUMPTION_CHANGE` (a subclass writing `use_power` directly, a
  machine whose channel changes before init, a move between areas while `power_init_complete` is false) corrupts the area's demand until
  `retally_power()` is run by hand. Nothing detects it.
* Draw is a number pushed by 340 call sites' worth of setters instead of a fact the machine states (`use_power` is `USE_POWER_ACTIVE`,
  `active_power_usage` is 120): the same fact is stored in the machine and again in the area.
* `power_equip/...` are untracked vars written from four places; `power_change()` is a per-machine push on every flip.
* `power_grids` is a hand-built mirror of Rust's region numbers with its own change channels (`CHANGE_POWER_GRID_*`).

## 2. The model

Three facts, each stated once, each a computed read for everything downstream.

### 2.1 A machine states its draw

`/obj/machinery` declares, once, three contributions to its area (`contributes_to(nameof(power_area), ...)`), one per channel:

```
STAT(/area, demand_equip,   SUM)      // watts the area's machines ask of the equipment channel
STAT(/area, demand_light,   SUM)
STAT(/area, demand_environ, SUM)

CAPABILITIES(/obj/machinery)
	contributes_to(nameof(power_area), STAT_DEMAND_EQUIP,   PROC_REF(draw_equip),   reads = list("use_power", "idle_power_usage", "active_power_usage", "power_channel"))
	contributes_to(nameof(power_area), STAT_DEMAND_LIGHT,   PROC_REF(draw_light),   ...)
	contributes_to(nameof(power_area), STAT_DEMAND_ENVIRON, PROC_REF(draw_environ), ...)
```

`draw_equip()` is `power_channel == EQUIP ? current_draw() : 0` where `current_draw()` is idle, active or 0 from the tracked `use_power`.
The `power_area` relation is `links(/obj/machinery::power_area, /area::power_machines)` and is the one place that follows a move: leaving
an area releases the contribution, entering one places it. There is no `REPORT_POWER_CONSUMPTION_CHANGE`, no `use_power_static`, no
`retally_power`, no `static_*`: the area's demand **is** the SUM of its members' contributions, so it cannot drift and a recount is
meaningless. `use_power`, `idle_power_usage`, `active_power_usage` and `power_channel` are `TRACKED`, so the setter is the contribution's
trigger; the `set_use_power()` / `update_*_power_usage()` / `update_power_channel()` procs stay as thin setters (callers unchanged) and lose
their bookkeeping bodies. The collection edge makes the area stats **marked**, recomputed in the next marked drain (the area's
power-in-flight is at most one drain late, well inside the machine service interval).

One-offs (`use_power_oneoff`) are not state, they are a pulse: the area keeps one accumulator per channel, handed to the APC with the
step's demand and zeroed, exactly as today. They do not become stats.

`STAT_POWER_DRAW` (the existing virtual SUM on `/obj/machinery`) is the machine's own draw read, `current_draw()`, shared with the
power monitors.

### 2.2 The APC reads demand and supplies; the area holds channel state

The APC (still stepped by Rust) receives per channel `demand_*` + one-off as its load whenever the area's demand stat changes
(`on_change` on the area stat, one `native_write` per channel; no dirty list, no flush loop). Rust's `ApcTick` supplies from the net or
the cell and moves the shedding ladder as today.

What the APC publishes is one thing: the **channel energized** facts of its area, `power_equip`, `power_light`, `power_environ`, now
`TRACKED` vars on `/area` with one writer (`area.set_channels()`, called by `apc.apply_area_power()` and the few admin and event
callers, replacing four direct writers). A machine's power is then not pushed at it: `powered(channel)` contributes
`STAT_OPERABLE` from `power_area.power_<channel>` (a one-hop read through the collection edge, marked and settled in the drain), and
`area.powered(chan)` stays for legacy callers as a read of the same vars.

**Deviation from the approved wording, and why.** The brief said the APC holds `powered` per channel on each machine (one hold per
channel, released on outage). The doc's own worked example (final_api.html section 7, "An example": an APC's equipment channel turns off) is
the read form: the area's tracked channel var is the input, the machines' stat reads it through the membership edge and the drain
recomputes them. A hold per machine would put N hold rows, N sources and a release pass per outage where one tracked write on the area
does the same work, and a hold must be released on every path (deleted APC, moved machine, rebuilt area) while a read cannot go stale.
The effect for machines is identical (they learn power via a stat, not a push) and the number of writers is one.

Until the other machine worker finishes converting NOPOWER to the powered stat, `set_powered()` is the sink: the marked recompute of
`powered` calls it (the one adapter), so `has_stat(NOPOWER)` and `STAT_OPERABLE` stay as they are for readers.

### 2.3 Generators and storage

* **Generators contribute supply to their powernet.** Unchanged in shape: `set_power_supply()` (steady) and `add_avail()` (pulse) are
  the book; Rust's `ProducerCredit` sums them per region. The producers' own state (a PACMAN's `active`, a solar's output) is their
  tracked state and the supply is derived from it by one write on change (already the case for the steady ones).
* **SMES** charge, input and output flow are Rust's tracked state (`Smes.charge/output_used/input_used`), stepped by the frame, not by a
  DM loop; DM reads them back when Rust reports a change (`power_poll`). They stay on the native frame because their charge is part of the
  conserved ledger (SMES input is the leftover after APCs, output pays what supply did not cover): that ordering is the ledger's.
* **The net's numbers** (`avail`, `load`, brownout) are read on demand with `vg_power_region_read` and cached per step; the DM region
  list (`power_grids`) shrinks to the cache plus the monitor warning and member list, with its change channels deleted in favour of
  `on_change` on the stat that matters (below).

### 2.4 Keep Rust for solving

Yes. The reasons are in 1.4: graph incrementality, one ledger with conservation properties, laws that must share a pass with it. The
DM side after this redo contains no per-machine bookkeeping, no tally, no flush loop and no recount; what remains in the bridge is
topology edits, one demand write per changed area channel, producer supply writes and storage read-back.

## 3. Migration steps

1. This document.
2. Behaviour tests on the legacy grid (committed before any change): APC discharge and charge, channel cut-offs, the area going dark and
   coming back, idle vs active draw on the APC load, SMES charge/output/terminal, generator supply, a cut splitting a net, a powersink,
   a heavy draw, the light channel. The 20 failing `dq_p2_smes/*` tests are diagnosed and fixed or rewritten.
3. The area gets `demand_*` stats and `set_channels()`; machines get the `power_area` link and the three contributions. The tallies are
   kept in step with the stats for one commit and a test asserts they agree (this is the proof the contributions are complete), then:
4. The APC takes its load from the stats (`on_change`), `power_flush_areas` loses the static half; the tallies, `retally_power`,
   `check_static_power`, `use_power_static`, `power_use_change`, `REPORT_POWER_CONSUMPTION_CHANGE` and `static_*` are deleted with
   their last callers (tests and `dq_machine_state_tests.dm` move to the stat read).
5. `power_equip/light/environ` become tracked and single-writer; the machines' `powered` contribution reads them; `power_change()`'s
   per-machine loop becomes the marked recompute (kept for subclasses that override `power_change()` until converted).
6. Codemod where mechanical: direct writes of `use_power =` / `idle_power_usage =` outside the setters in code (not type defaults) go
   through the setters; callers of the deleted procs are rewritten.
7. Docs: `intended_changes.md`, `framework_gaps.md` F7, `final_api.html` Machines note, a changelog stub.

## 4. What changes for players

Nothing intended, with these exceptions (recorded in `intended_changes.md`):

* An area's power draw is exact at every moment: a machine that skipped its tally report (a rare subclass or a move during init) now
  draws, so a few areas show a slightly higher load than before, on the APC and the power monitor.
* A machine whose power channel is switched at runtime moves its draw between channels at once.
* A move between areas moves the draw and the powered state in the same step, in all cases.

## 5. Risks

* **Marked recompute latency.** Area demand and machine powered state settle at the next marked drain, not inline. A test that reads the
  stat straight after a write must call the drain (`stat_drain_marked`) or read through `stat_value`. The Rust step already runs at
  `MACHINE_SERVICE_INTERVAL`, so no player-visible delay is added.
* **Cost of three contributions per machine.** 270 types, a few thousand machines on the live map; contributions are evaluated on a
  `use_power` / usage / channel write, which are rare for settled machines. The `apc_flip_50` bench and the 1,000 idle machines bench
  are the measurements (not run until the end of the rewrite, per standing instruction).
* **Membership.** `power_machines` today holds only subscribers; every machine must be a member for demand to count. Lights, which are
  not subscribers, already join through their own `power_area`; they move to the shared link.
* **Rust protocol.** The static-load native write is kept (its field names do not change); only its source changes, so no Rust change is
  needed for this stage. A Rust change would require `cargo test --package verdigris`.
* **The other worker.** `set_powered()` and the machine stat bits are being converted on the same branch; the powered contribution
  calls `set_powered()` until that lands, then reads the converted stat. Merge `origin/rewrite/machine-stats` often.

## 6. Status and what was decided while building it

Landed (all tests under `dq_grid_*`, `dq_p2_smes/*`, `dq_p2_apc/*`, `dq_power_*`, `dq_p2_chargers/*`, `dq_p2_lights/*` pass):

* **Demand.** `STAT(/area, demand_equip|light|environ, SUM)`; every machine `links` `power_area` to `/area::power_machines` and contributes
  through three `when(draws_<channel>, contributes_to(nameof(power_area), ...))` entries, so a machine holds one contribution row (its own
  channel's). `contributes_to` settles the target's stat inline, so `area.demand(chan)` is current the moment a machine's `use_power`,
  idle or active draw, channel or area changes (no marked-drain latency, which section 5 predicted). `use_power` / `idle_power_usage` /
  `active_power_usage` / `power_channel` are the tracked inputs. Deleted: `static_*`, `power_use_change`, `use_power_static`,
  `retally_power`, `check_static_power`, `REPORT_POWER_CONSUMPTION_CHANGE`, `power_subscribe`, `area.lights` (now `lights_here()`).
  `dq_grid_demand_equals_a_recount` proves every area on the test map equals a recount over its machines.
* **The push to Rust is level-triggered.** The first draft marked dirty areas from an `on_change` hook. Map load evaluates contributions
  silently (no change event), so an APC would have started with no standing load until some machine next changed. `power_flush_areas()`
  now compares each APC's area demand with what it last sent (`pushed_demand`) every step and writes the difference, logging
  `POWER_DEMAND`. One-offs still use the dirty set (they are pulses).
* **Channel state.** `power_equip/light/environ` are tracked and written only by `area.set_channels()` (the APC, the event that darkens an
  area, the area's own setup, the chilling-wind secret); machines still hear a flip through `area.power_change()`.
* **APC cells.** Everything that drained or charged an APC's cell with a bare `cell.use()` (power sink, solar grub, shocks sourced at an APC,
  the APC's lighting overload) had its change handed back by the next poll, because Rust's charge is authoritative. They go through
  `set_cell_charge()`.
* **SMES / battery rack.** Their screwdriver and crowbar lost to the window's `ui_open` (a hand input answers a held tool); the hatch ops
  now outrank it. The 20 `dq_p2_smes/*` failures on master were this one cause (16 on the branch base; 20 counting the rack and the
  coil and cable ones behind the hatch).

Not done, and why:

* **Machines read the channel as a stat instead of `power_change()` pushing `set_powered()`.** The machine worker is converting the NOPOWER
  bit to stats behind `set_powered()` on the same branch; the read would be a contribution to `STAT_OPERABLE` from
  `power_area.power_<channel>`, one hop through the collection edge, and it replaces `power_change()`'s per-machine loop. Doing it
  before their conversion lands would put two writers on the same state. Everything it needs is in place: the relation, the tracked channel
  vars and their single writer.
* **The one hold per channel.** See the deviation in 2.2: the read form replaces it.
* **`power_grids` change channels** (`CHANGE_POWER_GRID_*`) and the DM region cache stay; they are the monitor's, not the area's.

## 7. Stage 2: the grid's reading is a contribution (rewrite/power-grid)

* **The writer is gone.** `/obj/machinery` declares `contributes(STAT_HAS_POWER, area_gives_power, key = "area_power", reads = power_channel and the
  area's three tracked channel vars through power_area)`, and `contributes(STAT_OPERABLE, STAT_HAS_POWER, key = "power_operable")`. A machine's power is
  whatever its area's channel says, with no hold and nothing pushed. `power_change()` no longer writes: it compares the current reading with the last
  one it acted on (`power_seen`), publishes `stat`, the lost/restored notices and the heat update on a flip, and returns TRUE on a flip (the 65 overrides
  and the conveyor/airlock style `if((. = ..()))` callers keep working).
* **Where the area's reading is settled.** `area.power_change()` settles every machine's `has_power` (`stat_settle_def`) before it tells it, so the reading
  is current whatever wrote the channel vars (the tracked writer, or a test's direct write). `set_channels()` marks the same stat through the hop; the later
  marked drain finds it unchanged. **No `GLOB.stat_force_settle` is used**: the explicit settle in the one loop that already visits every machine does what
  forcing the hop inline would, without a global switch (the spike's global is for measuring, not for play).
* **The 65 `power_change()` overrides stay as effect procs, deliberately.** Converting them to `on_change(STAT_HAS_POWER, ...)` would not cover how they
  are used: `area.power_change()` is also the area's "something about my power or light switch changed" event (the light switch, map templates, generated
  stations, the holodeck, the expedition emergency area call it with no channel flipping), and about forty machines call their own `power_change()` after
  construction. Lights re-read their switch and bulb there. A flip-only hook would drop those. The dispatch is therefore still the area's loop, over a
  reading that is now a stat; the machines' bodies are unchanged. If a type's reaction is only to a flip it can move to `on_change(STAT_HAS_POWER, ANY, ...)`
  one file at a time with no engine change.
* **Self-powered types drop the area's reading by key.** `machine_basics(powered = FALSE, area_power = FALSE)` (the APC, the SMES) and `wall_machine(...)`
  with it drop `area_power` and `power_operable`. The RCD turret (`/obj/machinery/porta_turret/rcd`) says its own supply: area power never stops it
  (BROKEN and EMPED still do): fixed, `dq_machine_rcd_turret_ignores_power` passes.
* **Declared delays on the type's side.** A turret's capacitors: its `area_gives_power()` is TRUE and it contributes `power_held`, which its
  `power_change()` moves (at once on restore, after 0 to 1.5 s on loss). A jukebox contributes `anchored`. Neither is a second writer of the grid's state.
* **`set_powered()` and `stat_add/stat_remove(NOPOWER)` are a compatibility shim.** A caller that forces a machine dark holds `has_power` FALSE (source
  SRC_GRID); one that clears NOPOWER on a dark machine sets `power_forced`, which `area_gives_power()` honours. Both are for tests and the benchmark's old path.
* **A machine created in a dark area is dark at once** (before, it kept power until some later area event). Tests that built machines in a dark area and
  relied on that now power the machine's area or force it with the shim.
