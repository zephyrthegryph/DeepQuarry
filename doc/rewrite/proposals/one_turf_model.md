# One turf model

`/turf/unsimulated` is gone. Every turf is an open turf (`/turf/open`, with `air`, registered in the Rust gas field) or a
wall-like open turf (`blocks_air`). What the old split meant is now two separate, named things.

## What the split meant

1. "Has gas data": `/turf/simulated` and `/turf/space` had `air` and were in the gas field; a plain `/turf` had none, so gas
   treated it as a wall.
2. "Fixed fabric": the 59 unsimulated types (CentCom, beach, planet edge, overmap, fake space, the supermatter wall) were
   indestructible: the RCD, occult rites and acid refused them, nothing was built on them.

## The model

- `/turf/open/fixed` (`code/content/turfs/fixed.dm`, `code/content/turfs/fixed/`) is the map's fixed fabric. It is a `/turf/open`
  with `flags = TURF_ACID_IMMUNE | TURF_INDESTRUCTIBLE` and `blocks_air = TRUE`. Old `/turf/unsimulated/X` is `/turf/open/fixed/X`
  (map update script: `tools/UpdatePaths/Scripts/one_turf_model.txt`).
- `blocks_air` keeps today's behaviour exactly: gas neither enters nor leaves the turf, and a reading of it is the shared vacuum.
  `immutable_atmos` was rejected for these turfs: they border real turfs on the live map (CentCom against space, simulated floor and
  docked shuttles, the deck-edge `mask` turfs, the beach holodeck), and an immutable reservoir would exchange with its neighbours
  and become an infinite source or sink. A subtype that wants its own air (an isolated area) sets `blocks_air = FALSE` and gets a
  real mixture like any open turf.
- `TURF_INDESTRUCTIBLE` (`code/defines/base/turfs.dm`) is read through `turf_indestructible(T)`: the base `/turf` `rcd_values`,
  `rcd_act` and `occult_act` refuse it, and blob growth, the dimensional anomaly, the clang rod, the plastique and the RPD ask it.
- `turf_buildable(T)` (`code/library/helpers/turfs.dm`): station fabric people build, break and clean (an open turf that is not space
  and not indestructible). Blueprints, the build-mode room fill, the turf-change multiz walk, the wristwatch and security-uniform
  atmospherics readout and the generated-station air seed ask it.
- `skip_init` is deleted. Nothing read it; the cheap initialization is the `init_from_table` rows in `atom_type_table.dm`.

## Left as it is

`istype(x, /turf/simulated)` where the site means "a floor/wall that can be dirtied, wet, cleaned, mopped" (bots, cleaning reagents,
mops, fuel, bellies, the climb-wall verb and similar) is a question about the simulated floor family and stays a type check; those
sites are not gas or buildability questions. `/turf/simulated` remains the station floor/wall family. The planetary wall keeps its
air-blocking behaviour (it was never in the gas field).
