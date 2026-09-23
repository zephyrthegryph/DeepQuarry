# code/ATMOSPHERICS/

The **live and only** atmospherics engine: LINDA, vendored from /tg/ and adapted
to DeepQuarry. The old CHOMP/ZAS/XGM engine is gone, and there is no
`USE_LINDA_ATMOS` gate — this code compiles and runs unconditionally.

Gas mixtures are handles into the in-tree Rust gas world (vg-gas). Turf gas runs
on the Rust gas field (frames on their own pool), pipes on the Rust pipe network;
reactions, hotspots and device logic remain DM-owned.

## Layout

| Path | Purpose |
|---|---|
| `gasmixtures/` | `/datum/gas_mixture`, the `/datum/gas/*` registry (`gas_types.dm`), and the gas `reactions.dm` (the CHOMP reaction roster ported onto LINDA). |
| `environmental/` | `SSair`'s turf model — `LINDA_system.dm` (air-block masks and adjacency reads), `LINDA_turf_tile.dm`, `LINDA_fire.dm`. |
| `pipes/`, `components/` | Pipenets and atmos machinery (pumps, vents, scrubbers, filters, mixers, valves, …). |
| `SSair.dm` | The air subsystem controller. Registers every turf's air and air-block mask at init, drives the Rust turf processing, and publishes the multi-z links via `build_multiz_atmos_levels()`. |
| `xgm_compat.dm`, `tg_infra_compat.dm` | Load-bearing shims that expose the old XGM signatures (`assume_gas`, `update_nearby_tiles`, `CanZASPass`, `add_thermal_energy`, …) on top of LINDA for callers not yet moved to native LINDA APIs. |
| `auxmos_init_bridge.dm` | DM side of the Rust auxmos backend (see below). |

## Turf adjacency

Rust owns turf adjacency (`verdigris/domains/gas/src/turfs.rs`, `AirCells`).
DM publishes one **air-block mask** per turf: the faces
(`NORTH|SOUTH|EAST|WEST|UP|DOWN`) that the turf itself and the atoms on it block
(`/turf/open/air_block_mask()`: `blocks_air`, `can_atmos_pass` /
`CanZASPass` on each object, and `zAirIn`/`zAirOut` for the vertical faces).
Two registered face neighbours share air when neither blocks the shared face.

- A turf republishes its mask with `air_update_turf(TRUE)` whenever something
  that blocks air changes on it (doors, windows, firedoors, a moved object, the
  turf itself). `update_nearby_tiles()` and `SSair.mark_for_update()` route there.
- Round start registers every turf and its mask in chunked bulk calls
  (`SSair.setup_allturfs`); there is no DM adjacency pass.
- DM keeps **no copy** of the adjacency. Readers ask Rust:
  `T.get_atmos_adjacent_turfs()`, `atmos_adjacent_turfs_bulk(list)`,
  `SSair.air_blocked(A, B)` / `c_airblock()`. `tools/ci/check_grep.sh` rejects
  DM copies such as `atmos_adjacent_turfs`.

### Multi-z

`SSair.build_multiz_atmos_levels()` bridges the movement-multiz connectivity
(`GLOB.z_levels`, populated by `/obj/effect/landmark/map_data`) into
`SSmapping.multiz_levels` and sends Rust one `UP|DOWN` link mask per z-level
(`push_z_links()`). Rust links turfs vertically only across linked levels, and
only where neither turf blocks the face: a solid floor blocks its `DOWN` face, so
air crosses a z-boundary only through an open-space tile. It is re-run when
z-levels are added at runtime (e.g. expedition sites).

## Rust backend (vg-gas)

Gas lives in the gas world of `verdigris/domains/gas` (`world.rs`), linked into
the single Verdigris library. Every `/datum/gas_mixture` is a **handle**
(`_extools_pointer_gasmixture`, see `arena_id()`) into it, and every DM gas proc
routes through a generated `vg_*` proc, so the DM gas API (`return_air`,
`remove`, `merge`, `get_moles`, ...) is unchanged whoever owns the gas:

- **Main-owned mixtures** (handles below `GAS_HANDLE_PIPE_BASE`): tanks, lungs,
  canisters, device buffers, scratch mixtures. Read and written synchronously.
- **Turf gas** (handles from `GAS_HANDLE_TURF_BASE`): the cells of the gas
  field, an R6 field (`cell.rs`) with its own frame pool. Registering a turf
  moves its `air` datum's gas into its cell and rebinds the datum to the cell.
  DM reads the view pinned at the last SSair fire plus its own writes (the
  overlay); DM writes become commands with absolute amounts, applied in order
  at the next frame. Space's shared vacuum stays main-owned; space and planet
  cells are reservoirs (planet cells relax back to their atmosphere).
- **Pipe gas** (handles from `GAS_HANDLE_PIPE_BASE`): region payloads of the R7
  pipe network (`pipes.rs`). `rust_pipenets.dm` sends topology batches; the
  network pools, splits by volume and releases removed ports' shares itself,
  and each region's air datum is bound to its region handle (`vg_bind_handle`).

**SSair.** Each fire runs `vg_gas_tick()`: pin the newest frame, start the next
on the gas pool (never waiting), and return the frame's events, which
`process_gas_events()` dispatches: `GAS_EVENT_REACT` (`air.react(turf)`),
`GAS_EVENT_VISUAL` (`set_visuals()`) and `GAS_EVENT_PRESSURE` (spacewind). A
frame is 0.5 s of gas. Tests step the field deterministically with
`SSair.run_gas_frames(n)` (`vg_gas_run_frames`) instead of waiting on the clock.

**Air-block masks are geometry.** A mask change is one geometry command, seen at
once by DM's adjacency reads (the overlay) and by the next frame. There are no
topology barriers or transactions: an explosion or a shuttle move is a run of
commands applied in order.

- **Gas IDs are integers.** Each gas has a fixed ID in `verdigris/domains/gas/src/gas/ids.rs`,
  generated into DM as `GAS_ID_*` and set as `/datum/gas/var/idx`. Gas binds take
  only these numbers; the DM wrappers accept a `GAS_ID_*` number or a
  `/datum/gas` path and convert with `GAS_IDX()`. `GLOB.gas_path_by_idx` is the
  id -> path table for admin tools and UI. Specific heats are fixed with the IDs
  (`cell.rs` `SPECIFIC_HEATS`); the registry checks DM's values at boot.
- **Batched reads.** `read_gas_mixtures(list)` returns pressure, temperature,
  volume, total moles, heat capacity and every gas's moles for many mixtures in
  one call (`GAS_READ_*` layout); `get_gases()` is one call too.
- **Reactions** run in DM. The field's `local` step checks registered reaction
  requirements per cell and reports `GAS_EVENT_REACT`.
- **Watches.** Gas is a reactor domain: `REACT_ON` / `REACT_WHEN` on
  `REACT_GAS(mixture)` (a turf's air or a main-owned mixture) with the
  `CH_GAS_*` channels.

`xgm_compat.dm` and `tg_infra_compat.dm` keep the older XGM-style call
signatures working on top of LINDA. New code should use the native LINDA API.

## See also

- `TG_UPSTREAM.md`: provenance of the vendored /tg/ atmos code.
- `verdigris/README.md`: building and testing the Rust extension.
