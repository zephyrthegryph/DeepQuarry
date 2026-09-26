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
//     `/datum/powernet` instead of pushed by an event stream (a
//     `POWER_EV_REGION` per step is gone with `PowerHost`).
// There is no DM topology code: no flood fills, merges or rebuilds, and no
// `power_key`/edit queue -- a bound atom's `vg_entity` (or, for a cable,
// the entity `vg_power_bind_cable` hands back) is the only identity Rust
// needs.

/// Entity handle -> the cable that placed it (the material power overlay's
/// only use for this: `vg_power_region_members()` hands back entities,
/// and only cables need mapping back to an atom -- every other power
/// machine already knows its own `vg_entity`).
GLOBAL_LIST_EMPTY(power_cable_by_entity)

/datum/controller/subsystem/machines
	/// Region id (Rust's raw handle bits + 1) -> its /datum/powernet. An alist:
	/// the ids are numbers, and a plain list would treat them as positions.
	var/alist/power_regions = alist()
	/// Areas whose static or one-off loads changed since the last step.
	var/list/power_dirty_areas = list()
	/// Cables with an engineered conductor; their regions run the material overlay.
	var/list/power_material_cables = list()

/// The /datum/powernet for region `id`, made on first use.
/datum/controller/subsystem/machines/proc/power_facade(id)
	if(!id)
		return null
	var/datum/powernet/network = power_regions[id]
	if(network)
		return network
	network = new(id)
	power_regions[id] = network
	network.refresh()
	return network

/// The region an already-bound entity's node is on, or null.
/datum/controller/subsystem/machines/proc/power_region_of(entity)
	if(!entity)
		return null
	var/id = vg_power_region_of(entity)
	return id ? power_facade(id) : null

/// Queues an area's loads for its APC.
/area/proc/power_loads_changed()
	SSmachines.power_dirty_areas[src] = TRUE

/datum/controller/subsystem/machines/proc/power_flush_areas()
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
/// publishes its results to DM's own cache (`/datum/powernet`) and drives
/// the machinery-tick-cadence bookkeeping (SMES icons, APC displays) that
/// isn't itself simulated in Rust.
/datum/controller/subsystem/machines/proc/process_power()
	power_flush_areas()
	vg_power_commit()
	for(var/obj/structure/cable/cable as anything in power_material_cables)
		if(QDELETED(cable))
			power_material_cables -= cable
			continue
		cable.get_powernet()?.material_candidate = TRUE
	for(var/id in power_regions)
		var/datum/powernet/network = power_regions[id]
		network.refresh()
	for(var/obj/machinery/power/apc/apc as anything in REGISTRY_MEMBERS(REGISTRY_APCS))
		apc.power_poll()
	for(var/obj/machinery/power/smes/storage as anything in REGISTRY_MEMBERS(REGISTRY_SMES))
		storage.power_poll()
	for(var/id in power_regions)
		var/datum/powernet/network = power_regions[id]
		if(network.material_candidate || network.material_graph)
			network.process_material_network()
		if(network.is_empty())
			power_regions -= id
			qdel(network)

/// Clears every DM-side power cache and re-registers every cable, power
/// machine, APC and SMES (admin repair): unbinds and rebinds every
/// `vg_entity` a power object holds, so a divergence from Rust's own state
/// cannot survive it.
/datum/controller/subsystem/machines/proc/power_reregister_all()
	for(var/id in power_regions)
		qdel(power_regions[id])
	power_regions = alist()
	GLOB.power_cable_by_entity = list()
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
/datum/controller/subsystem/machines/proc/power_reregister(list/turfs)
	for(var/turf/T as anything in turfs)
		for(var/obj/structure/cable/cable in T)
			cable.power_register()
		for(var/obj/machinery/power/machine in T)
			if(!istype(machine, /obj/machinery/power/apc))
				machine.power_send_node()
