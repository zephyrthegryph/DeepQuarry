# Proposal: docking and airlocks on the scheduler core

Status: approved by the task (2026-11-02), implemented in slices on `rewrite/docking-om`.

## 0. Why

Docking spans four layers today: the shuttle state machine (`shuttle_autodock.dm`), a radio handshake between docking programs
(`docking_program.dm`, `docking_program_multi.dm`), a per-airlock cycle program on one sensor tile (`airlock_program.dm`), and radio wake
filtering (`signal_requires_processing()`), so a controller steps only for packets naming its own devices. Every docking bug of
November 2026 came from a seam between them:

- children of a multi-airlock port never woke for the master's radio commands (e2ae7bfad6);
- the cycle judged the chamber from one sensor tile and stalled when the rest of the chamber settled elsewhere (41348618ec);
- undocking raced the hatch, because the port acted on the door state it last heard by radio (e2ae7bfad6).

Each of these is a message that could be missed or a reading that could go stale. The new shape has no messages between parts of one
machine and no copies of state that some other entity owns.

## 1. Entities and relations

| Entity | What it is | Holds by relation |
|---|---|---|
| airlock (`/obj/machinery/embedded_controller/radio/airlock`) | the controller machine; the cycle state lives on it | `exterior_doors`, `interior_doors` (doors), `pumps` / `dp_pumps` (the chamber vents), `pumps_out_internal` / `pumps_out_external` (external-air airlocks), `chamber_sensor`, `exterior_sensor`, `interior_sensor`, `mech_sensors` |
| docking port (`/datum/docking_port`) | one per docking console; the handshake state | `console` (its machine), `peer` (the port it docks with), its airlocks (below), its `hatches` (doors) |
| shuttle (`/datum/shuttle/autodock`) | unchanged state machine | `shuttle_docking_controller`, `active_docking_controller` (now ports) |

The port's airlocks: a hatch port (simple, escape pods) has none and holds its hatch doors; an airlock docking port is its own one airlock;
a multi-airlock port's console holds its child airlocks (`child_airlocks`).

**Mapped content.** Tags on maps keep pairing things. Every relation above is a keyed view (`ref_one/ref_many(by =, target_key =)`), so the
map's tags resolve to relations when the machines materialize, and a multitool retag re-links through `keyed_set_id()`. Defaults the
program used to compute (`"[id_tag]_outer"`, `"[id_tag]_pump"`, `"[id_tag]_hatch"` ...) are written into the tag vars at setup, before the
keyed views link. A multi port's children are found by their own `master_tag` (the master holds `ref_many(child_airlocks, by = id_tag,
target_key = master_tag)`), not by its `child_tags_txt`, which is kept only for the children's display names. Ports still register by tag in
`SSshuttles` (landmarks and shuttles name them by tag in map data).

## 2. The handshake: direct calls between linked ports

The client (the shuttle's port) resolves the server by tag once and calls it; from then on the two ports are linked (`peer`) and talk by
direct procs on each other. Nothing is broadcast, nothing is resent, nothing can be missed.

```
client.initiate_docking(server_tag)  -> server.dock_requested(client, code)   server: DOCKING, prepare; -> client.dock_accepted(server)
client (DOCKING, prepare; step)      -> when ready: server.peer_ready(client)
server (step)                        -> when ready and peer_ready: DOCKED, finish; -> client.dock_completed()   client: DOCKED, finish
client.initiate_undocking()          -> UNDOCKING, prepare; server.undock_requested(client)   server: UNDOCKING, prepare
client (step)                        -> when ready: server.peer_ready(client)
server (step)                        -> when ready and peer_ready: finish, reset; -> client.undock_completed()   client: finish, reset
force_undock() / a refused code      -> peer.dock_error(src); both reset
```

The states and modes are the old ones (`undocked/docking/docked/undocking`, client/server), so the shuttle code, the consoles' windows
and the docking codes behave as before. The port's step runs in its console's work loop while a dock or undock is in flight (the readiness
it waits on is its airlocks' cycle and its hatch's swing), and stops once the port is docked or undocked.

Prepare/ready/finish are one table for every port:

| | each airlock (unless overridden) | each hatch (unless overridden) |
|---|---|---|
| prepare docking | mark docked, cycle in | - |
| ready to dock | cycle done | yes |
| finish docking | mech sensors on, both doors open | open and bolt |
| prepare undocking | stop cycling, close and bolt both doors, mech sensors off | close and bolt |
| ready to undock | either door shut and bolted | shut and bolted (read from the door, every step) |
| finish undocking | mark undocked | - |

An escape pod berth is a port subtype that overrides the hatch rows (doors open only when armed; undocking waits out the eject delay).

## 3. The airlock cycle: a state on the airlock, driven by the chamber's pressure

The cycle states are the old ones (idle, prepare, depressurize, pressurize; targets none, inner open, outer open). What changes is where
the readings come from and how commands go out:

- **Chamber pressure** is the median pressure of the chamber region: the turfs atmos-connected to the chamber sensor's turf (the pump's
  when there is no sensor), never crossing the airlock's own doors, at most 40. While the chamber pumps, the airlock holds one gas watch per
  region mixture (`gas_watch_many(chamber_watches, GAS_DEPENDENCY_PRESSURE)`); a reported change wakes its step, and the step after the
  pumps start judges once without waiting (a chamber already in its band never changes). Out of a pumping state the watches are dropped.
  The region replaces the one sensor tile: the vent drains the tiles nearest it first. The median, not the mean: the atmos sim can leave a
  static pocket of a tile or two beside vacuum (21 kPa on the AEG stern airlocks), which held a mean out of the band forever.
- **Inside and outside pressure** are read from the interior and exterior sensors' air when a cycle starts (the shuttle exterior sensor still
  reads the turf in front of it); with no sensor, outside is vacuum and inside one atmosphere, as before.
- **Door and pump state** are read from the doors and vents themselves (`density`, bolted, `use_power`, `pump_direction`). There is no
  remembered status to go stale: the hatch race of e2ae7bfad6 cannot happen.
- **Commands** are direct calls: a door takes `airlock_command("secure_open" ...)` (the same command set and retry its radio handler ran);
  a vent takes `airlock_pump(power, direction, pressure)`. The "resume pumping when the chamber leaves the band" rule of 41348618ec stays.

The airlock steps while a cycle is preparing (its doors swinging) or a pressure change was heard; a pumping chamber with no change sleeps.

## 4. Radio that stays

Only the player-facing devices with their own text protocol keep the radio: access buttons and airlock sensors' "cycle" button (a
programmable command to a programmable tag), and the doors' own command receiver, which those buttons can address directly. An airlock
console still listens for the `cycle`, `cycle_interior`, `cycle_exterior` commands addressed to its own `id_tag`, and nothing else. Door
status broadcasts, sensor pressure broadcasts, pump commands, mech sensor commands, docking messages and every wake filter are gone.

## 5. What gets deleted

- `/datum/embedded_program` and every subtype: `embedded_program_base.dm`, `airlock_program.dm`, `docking_program.dm`,
  `docking_program_multi.dm` (master and child programs), `/datum/embedded_program/docking/airlock`, `/datum/embedded_program/airlock/docking`,
  `/datum/embedded_program/docking/simple`, the escape pod berth program (replaced by the port subtype).
- The radio handshake: `send_docking_command()`, `broadcast_docking_status()`, the `recipient`/`command` packet protocol, `response_sent`,
  `resend_counter`, `MESSAGE_RESEND_TIME`, `received_confirm`'s radio path, `send_signal_to_master()`, `broadcast_override_status()`.
- Radio wake filtering: `signal_requires_processing()`, the controller's per-packet `work_start()`.
- The airlock's radio device protocol: `signalDoor()`, `signalPump()`, `signal_mech_sensor()`, `toggleDoor()` on remembered status, the
  `memory` list (`chamber_sensor_pressure`, `exterior_status` ...), `get_all_tags()/get_tag()/set_tag()` switch tables.
- Sensor pressure broadcasts (`airlock_sensor.sample_pressure()`'s packet), door `send_status()` and `last_reported_*`, the mech sensor's
  radio receiver.

## 6. Slices

1. This document.
2. The docking port entity and the direct handshake; the docking programs deleted.
3. The airlock on its devices by relation, direct door and pump commands, the chamber region watch; the airlock program, the device radio
   protocol and the wake filters deleted.

After each: `dq_docking_end_to_end`, `dq_airlock_cycle_end_to_end` (`--full-map`), and the docking and airlock unit tests pass.
