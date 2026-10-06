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
	/// grids) -> its flat state list (power_grid.dm). An alist: the ids are
	/// numbers, and a plain list would treat them as positions.
	var/alist/power_grids = alist()
	/// Region id -> /datum/material_power_overlay, for regions holding an engineered conductor.
	var/alist/power_material_overlays = alist()
	/// Last id handed to a detached test grid (counts down from 0).
	var/power_test_grid_serial = 0
	/// Areas whose static or one-off loads changed since the last step.
	var/list/power_dirty_areas = list() // SSmachines singleton (M3 power); one instance
	/// Cables with an engineered conductor; their regions run the material overlay.
	var/list/power_material_cables = list() // SSmachines singleton (M3 power); one instance
	/// The APCs and SMES the current power step still has to poll, while a budgeted step is yielded between
	/// ticks; null when no poll is in progress (poll_power_storage()).
	var/list/power_poll_queue
	var/power_poll_index = 1

/// Queues an area's loads for its APC.
/area/proc/power_loads_changed()
	SSmachines.power_dirty_areas[src] = TRUE

/datum/system/machines/proc/power_flush_areas()
	stat_drain_point() // the on_change hooks that mark an area dirty run at a drain: take them before reading the set
	for(var/area/A as anything in power_dirty_areas)
		var/obj/machinery/power/apc/apc = A.apc
		if(apc?.vg_entity)
			native_write(apc, NATIVE_APC_STATIC_LOAD, A.demand(EQUIP), 0)
			native_write(apc, NATIVE_APC_STATIC_LOAD, A.demand(LIGHT), 1)
			native_write(apc, NATIVE_APC_STATIC_LOAD, A.demand(ENVIRON), 2)
			if(A.oneoff_equip || A.oneoff_light || A.oneoff_environ)
				native_write(apc, NATIVE_APC_ONEOFF, A.oneoff_equip, 0)
				native_write(apc, NATIVE_APC_ONEOFF, A.oneoff_light, 1)
				native_write(apc, NATIVE_APC_ONEOFF, A.oneoff_environ, 2)
		A.oneoff_equip = 0
		A.oneoff_light = 0
		A.oneoff_environ = 0
	power_dirty_areas.Cut()

/// One power step: send area loads, commit topology, refresh every known
/// region's numbers and the machines/material overlay that read them.
/// Rust's own tick (the native frame) runs independently -- this only
/// publishes its results to DM's cache (`power_grids`) and drives the
/// machinery-tick-cadence bookkeeping (SMES icons, APC displays) that isn't
/// itself simulated in Rust.
/// The rest of the power step: the engineered-conductor overlays.
/datum/system/machines/proc/process_power_finish()
	for(var/obj/structure/cable/cable as anything in power_material_cables)
		if(QDELETED(cable))
			power_material_cables -= cable
			continue
		var/id = cable.get_power_region()
		if(id && !power_material_overlays[id])
			power_material_overlays[id] = new /datum/material_power_overlay(id)
	for(var/id in power_material_overlays)
		var/datum/material_power_overlay/overlay = power_material_overlays[id]
		if(!power_grids[id] || !overlay.process_material_network())
			power_material_overlays -= id
			spent(overlay)

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

/// Clears every DM-side power cache and re-registers every cable, power
/// machine, APC and SMES (admin repair): unbinds and rebinds every
/// `vg_entity` a power object holds, so a divergence from Rust's own state
/// cannot survive it.
/datum/system/machines/proc/power_reregister_all()
	for(var/id in power_material_overlays)
		spent(power_material_overlays[id])
	power_material_overlays = alist()
	power_grids = alist()
	power_regions_stale = TRUE
	for(var/obj/structure/cable/cable as anything in REGISTRY_MEMBERS(REGISTRY_CABLES))
		cable.power_unregister()
		cable.power_register()
	for(var/obj/machinery/power/machine in world)
		if(istype(machine, /obj/machinery/power/apc))
			continue
		if(machine.vg_entity && isturf(machine.loc))
			machine.power_send_node(force = TRUE)
	for(var/obj/machinery/power/apc/apc in world)
		apc.power_send_node(force = TRUE)
	for(var/area/A in world)
		A.power_loads_changed()
	process_power()

/// Registers every cable and power machine again (admin repair, and after
/// bulk moves that bypass Moved()).
/datum/system/machines/proc/power_reregister(list/turfs)
	for(var/turf/T as anything in turfs)
		for(var/obj/structure/cable/cable in contents_of(T))
			cable.power_register()
		for(var/obj/machinery/power/machine in contents_of(T))
			if(!istype(machine, /obj/machinery/power/apc))
				machine.power_send_node(force = TRUE)
