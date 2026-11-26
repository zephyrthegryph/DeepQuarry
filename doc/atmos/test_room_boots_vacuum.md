# Fixed: floors map-loaded onto a level made in play sat in vacuum reservoir cells

Found 2026-11-08 (the test room's floors read 0 mol at 2.7 K; `dq_pressure_differential_drives_flow`'s assume_air() read back 0). Fixed the
same day.

Cause: `load_new_z()` puts a template's turfs over a level made in play (the test blocks, expedition sites, generated stations). The level's
space was already registered in the Rust arena as vacuum reservoir cells (increment_max_z() registers the level whole), and the map loader
replaces turfs without unregistering them. When a loaded floor first read its air (turf_air(), from update_air_ref()), `hook_bind_turf_air`
bound its new datum to the cell it found there, the replaced space's reservoir: the floor's gas was lost, it read vacuum, and `submit_turf()`
dropped every write to it as to immutable air. The station map (loaded at boot) was not affected; a ChangeTurf in play was not either (it
unregisters the old cell first).

Fix (verdigris/ffi/src/gas/mod.rs, `hook_bind_turf_air`): a reservoir cell under a turf that is neither immutable nor planetary belongs to the
turf it replaced, so the bind is refused; the datum keeps its gas and the turf's registration moves it into the cell with the turf's own kind.
`vg_atmos_cell_info()` now reports the reservoir flag (its fifth field).

Tests: `dq_map_loaded_floor_on_new_level_holds_air` (a block floor's cell is not a reservoir and takes 50 mol written to it),
`dq_pressure_differential_drives_flow`. `dq_air_guard_judges_a_replaced_turf_by_its_current_air` now swaps the floor for another floor type
and back (the air is carried across): its old breach to space and back vents the floor's air for real, which the guard rightly reports.
