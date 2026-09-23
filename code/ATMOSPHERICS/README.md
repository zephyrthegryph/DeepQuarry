# code/ATMOSPHERICS/

The **live and only** atmospherics engine: LINDA, vendored from /tg/ and adapted
to DeepQuarry. The old CHOMP/ZAS/XGM engine is gone, and there is no
`USE_LINDA_ATMOS` gate — this code compiles and runs unconditionally.

Gas mixtures are handles into the in-tree Rust **auxmos** arena. Gas math and
turf diffusion run there; reactions, hotspots, and pipenets remain DM-owned.
Diffusion runs asynchronously against a private generation snapshot. Publication
is atomic and rejected if a synchronous mutation changed an input mixture.

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

## Rust backend (auxmos)

Gas math and turf diffusion run in auxmos, vendored under `verdigris/atmos/`
and linked into the single Verdigris library (`verdigris.dll` /
`libverdigris.so`). There is no separate `libauxmos`.

- `auxmos_init_bridge.dm` is the hand-written DM side. It registers the gas
  registry and reaction tables with Rust at `SSair` init. Every call into Rust goes
  through a generated `vg_*` proc (`code/__defines/verdigris/_bindings.dm`).
- **Gas IDs are integers.** Each gas has a fixed ID in `verdigris/domains/gas/src/gas/ids.rs`,
  generated into DM as `GAS_ID_*` and set as `/datum/gas/var/idx`. Gas binds take
  only these numbers; the DM wrappers accept a `GAS_ID_*` number or a
  `/datum/gas` path and convert with `GAS_IDX()`. `GLOB.gas_path_by_idx` is the
  id -> path table for admin tools and UI.
- **Batched reads.** `read_gas_mixtures(list)` returns pressure, temperature,
  volume, total moles, heat capacity and every gas's moles for many mixtures in
  one call (`GAS_READ_*` layout); `get_gases()` is one call too.
- Each `/datum/gas_mixture` is a handle into the Rust gas arena. The handle is
  stored in `_extools_pointer_gasmixture` and is null until registered.
- auxmos is built with `turf_processing` and `superconductivity` (see
  `verdigris/verdigris/Cargo.toml`).
- Reactions, hotspots and pipenets stay in DM. auxmos's own reaction hooks are
  disabled, and the gas roster is the inherited XGM set (oxygen, nitrogen,
  phoron, carbon dioxide, nitrous oxide), not /tg/'s.
- The vendored commit and every local modification are recorded in
  `verdigris/atmos/UPSTREAM.md`. Update it whenever auxmos is bumped.

`xgm_compat.dm` and `tg_infra_compat.dm` keep the older XGM-style call
signatures working on top of LINDA. New code should use the native LINDA API.

## See also

- `TG_UPSTREAM.md`: provenance of the vendored /tg/ atmos code.
- `verdigris/README.md`: building and testing the Rust extension.
