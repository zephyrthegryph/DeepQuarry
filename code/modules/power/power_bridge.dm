// M3 (rust_architecture.md step 3): the DM side of the Rust power domain
// (verdigris/domains/power; binds in verdigris/ffi/src/power.rs, generated
// accessors in code/__defines/verdigris/_bindings_types.dm).
//
// Rust owns the cable graph, the per-region ledger, the APC distributor and
// SMES charge, run as ordinary `vg_core::world::World` laws -- `SSvg.fire()`
// (code/controllers/subsystems/vg.dm) already feeds them elapsed time via
// `vg_world_tick()` and dispatches their events via `vg_drain_events()`,
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

/datum/world_service/machines
	/// Region id (Rust's raw handle bits + 1; negative for detached test
	/// grids) -> its flat state list (power_grid.dm). An alist: the ids are
	/// numbers, and a plain list would treat them as positions.
	var/alist/power_grids = alist()
	/// Region id -> /datum/material_power_overlay, for regions holding an engineered conductor.
	var/alist/power_material_overlays = alist()
	/// Last id handed to a detached test grid (counts down from 0).
	var/power_test_grid_serial = 0
	/// Areas whose static or one-off loads changed since the last step.
	var/list/power_dirty_areas = list() // ALLOW(instance_list): d: SSmachines singleton (M3 power); one instance
	/// Cables with an engineered conductor; their regions run the material overlay.
	var/list/power_material_cables = list() // ALLOW(instance_list): d: SSmachines singleton (M3 power); one instance

/// Queues an area's loads for its APC.
/area/proc/power_loads_changed()
	GLOB.machine_service.power_dirty_areas[src] = TRUE

/datum/world_service/machines/proc/power_flush_areas()
	for(var/area/A as anything in power_dirty_areas)
		var/obj/machinery/power/apc/apc = A.apc
		if(apc?.vg_entity)
			apc.set_static_load(0, A.static_equip)
			apc.set_static_load(1, A.static_light)
			apc.set_static_load(2, A.static_environ)
			if(A.oneoff_equip || A.oneoff_light || A.oneoff_environ)
				apc.set_oneoff(0, A.oneoff_equip)
				apc.set_oneoff(1, A.oneoff_light)
				apc.set_oneoff(2, A.oneoff_environ)
		A.oneoff_equip = 0
		A.oneoff_light = 0
		A.oneoff_environ = 0
	power_dirty_areas.Cut()

/// One power step: send area loads, commit topology, refresh every known
/// region's numbers and the machines/material overlay that read them.
/// Rust's own tick (`SSvg.fire()`) runs independently -- this only
/// publishes its results to DM's cache (`power_grids`) and drives the
/// machinery-tick-cadence bookkeeping (SMES icons, APC displays) that isn't
/// itself simulated in Rust.
/datum/world_service/machines/proc/process_power()
	power_flush_areas()
	vg_power_commit()
	for(var/id in power_grids)
		if(!power_grid_refresh(id))
			power_grids -= id
			continue
		power_grid_sync_problem(id)
	// Every power machine's `power_region` is polled here, not pushed --
	// a deferred `connect_to_network(FALSE)` (map load, and every
	// `power_autoconnect()`) relies on this to eventually resolve.
	for(var/obj/machinery/power/machine as anything in REGISTRY_MEMBERS(REGISTRY_POWER_MACHINES))
		if(!QDELETED(machine))
			machine.power_refresh_network()
	for(var/obj/machinery/power/apc/apc as anything in REGISTRY_MEMBERS(REGISTRY_APCS))
		apc.power_poll()
	for(var/obj/machinery/power/smes/storage as anything in REGISTRY_MEMBERS(REGISTRY_SMES))
		storage.power_poll()
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
			qdel(overlay)

/// Clears every DM-side power cache and re-registers every cable, power
/// machine, APC and SMES (admin repair): unbinds and rebinds every
/// `vg_entity` a power object holds, so a divergence from Rust's own state
/// cannot survive it.
/datum/world_service/machines/proc/power_reregister_all()
	for(var/id in power_material_overlays)
		qdel(power_material_overlays[id])
	power_material_overlays = alist()
	power_grids = alist()
	for(var/obj/structure/cable/cable as anything in REGISTRY_MEMBERS(REGISTRY_CABLES))
		cable.power_unregister()
		cable.power_register()
	for(var/obj/machinery/power/machine in world)
		if(istype(machine, /obj/machinery/power/apc))
			continue
		if(machine.vg_entity && isturf(machine.loc))
			machine.power_send_node()
	for(var/obj/machinery/power/apc/apc in world)
		apc.power_send_node()
	for(var/area/A in world)
		A.power_loads_changed()
	process_power()

/// Registers every cable and power machine again (admin repair, and after
/// bulk moves that bypass Moved()).
/datum/world_service/machines/proc/power_reregister(list/turfs)
	for(var/turf/T as anything in turfs)
		for(var/obj/structure/cable/cable in T)
			cable.power_register()
		for(var/obj/machinery/power/machine in T)
			if(!istype(machine, /obj/machinery/power/apc))
				machine.power_send_node()
