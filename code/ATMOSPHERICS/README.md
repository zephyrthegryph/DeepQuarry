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
| `environmental/` | `SSair`'s turf model — `LINDA_system.dm` (adjacency), `LINDA_turf_tile.dm`, `LINDA_fire.dm`. |
| `pipes/`, `components/` | Pipenets and atmos machinery (pumps, vents, scrubbers, filters, mixers, valves, …). |
| `SSair.dm` | The air subsystem controller. Builds turf adjacency at init, processes active turfs, and (re)builds the multi-z vertical-adjacency table via `build_multiz_atmos_levels()`. |
| `xgm_compat.dm`, `tg_infra_compat.dm` | Load-bearing shims that expose the old XGM signatures (`assume_gas`, `update_nearby_tiles`, `CanZASPass`, `add_thermal_energy`, …) on top of LINDA for callers not yet moved to native LINDA APIs. |
| `auxmos_init_bridge.dm` | DM side of the Rust auxmos backend (see below). |

## Multi-z atmos

Vertical atmos adjacency is wired at init by `SSair.build_multiz_atmos_levels()`,
which bridges the movement-multiz connectivity (`GLOB.z_levels`, populated by
`/obj/effect/landmark/map_data`) into `SSmapping.multiz_levels` — the table
`init_immediate_calculate_adjacent_turfs` reads to decide UP/DOWN turf adjacency.
It is re-run when z-levels are added at runtime (e.g. expedition sites).
Whether gas actually flows vertically then follows turf density: sealed rock
blocks it, an open shaft passes it.

## Rust backend (auxmos)

Gas math and turf diffusion run in auxmos, vendored under `verdigris/atmos/`
and linked into the single Verdigris library (`verdigris.dll` /
`libverdigris.so`). There is no separate `libauxmos`.

- `auxmos_init_bridge.dm` is the hand-written DM side. It registers the gas
  registry and reaction tables with Rust at `SSair` init and routes lifecycle
  calls through `call_ext(VERDIGRIS, ...)`. Gases are registered under their
  type-path text (`"/datum/gas/plasma"`), because LINDA keys gases by type.
- Each `/datum/gas_mixture` is a handle into the Rust gas arena. The handle is
  stored in `_extools_pointer_gasmixture` and is null until registered.
- auxmos is built with `turf_processing`, `fastmos`, `explosive_decompression`
  and `superconductivity` (see `verdigris/verdigris/Cargo.toml`).
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
