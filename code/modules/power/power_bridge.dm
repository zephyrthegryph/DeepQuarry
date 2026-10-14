// M3 (rust_architecture.md step 3): the DM side of the Rust power domain
// (verdigris/domains/power; binds in verdigris/ffi/src/power.rs, generated
// accessors in code/__defines/verdigris/_bindings_types.dm).
//
// Rust owns the cable graph, the per-region ledger, the APC distributor and
// SMES charge, run as ordinary `vg_core::world::World` laws -- the native system's
// frame (`vg_frame()`, code/datums/native/system.dm) already feeds them elapsed time
// and dispatches their events (`vg_dispatch_notice()`),
// exactly as gas's laws are. DM:
//   - every power machine (APC, SMES, producer/generator/solar/...) is a
//     `#[vg::component]` on `/obj/machinery/power` or a subtype, bound
//     automatically by `on_materialize()`'s `vg_bind()` -- there is no
//     per-machine registration call;
//   - a cable or a machine's own network node is placed with
//     `vg_power_bind_cable`/`vg_power_bind_machine` (topology is not a
//     component: it is a network node's cell, not a field);
//   - a region's numbers are read with `vg_power_region_read`, polled by
//     `power_grid_refresh()` (power_grid.dm) instead of pushed by an event stream (a
//     `POWER_EV_REGION` per step is gone with `PowerHost`).
// There is no DM topology code: no flood fills, merges or rebuilds, and no
// `power_key`/edit queue -- a bound atom's `vg_entity` (or, for a cable,
// the entity `vg_power_bind_cable` hands back) is the only identity Rust
// needs.

/datum/system/machines
	/// Region id (Rust's raw handle bits + 1; negative for detached test
	/// grids) -> its tracked state datum (power_grid.dm). An alist: the ids are
	/// numbers, and a plain list would treat them as positions.
	VAR_PRIVATE/datum/power_grid_registry/power_grids
	/// Region id -> /datum/material_power_overlay, for regions holding an engineered conductor.
	var/alist/power_material_overlays = alist()
	/// Last id handed to a detached test grid (counts down from 0).
	var/power_test_grid_serial = 0
	/// Areas whose static or one-off loads changed since the last step.
	var/list/power_dirty_areas = list() // SSmachines singleton (M3 power); one instance
	/// Cables with an engineered conductor; their regions run the material overlay.
	var/list/power_material_cables = list() // a relation list: a deleted cable leaves it
	/// The APCs and SMES the current power step still has to poll, while a budgeted step is yielded between
	/// ticks; null when no poll is in progress (poll_power_storage()).
	var/list/power_poll_queue
	var/power_poll_index = 1

CAPABILITIES(/datum/system/machines)
	owns_one(nameof(power_grids), /datum/power_grid_registry, starts = /datum/power_grid_registry)
	owns_many(nameof(power_material_overlays), /datum/material_power_overlay)
	ref_many(nameof(power_material_cables), /obj/structure/cable)

/// Queues an area's loads for its APC.
/area/proc/power_loads_changed()
	SSmachines.queue_area_power_load(src)

/// The cable network's topology was edited (a node bound or unbound): regions may split, merge or gain members at
/// the next commit, so the next power step re-reads every machine's region. Every vg_power_bind_* and
/// vg_power_unbind_* call is followed by this; nothing else changes a region. `source` (the object or type that edited
/// it) is counted for the churn metrics: an idle grid should make none.
/proc/power_topology_edited(source)
	var/datum/source_datum = source
	CHURN_COUNT(power_edits, istype(source_datum) ? source_datum.type : source)
	var/datum/system/machines/service = SSmachines
	if(service)
		service.power_regions_stale = TRUE
