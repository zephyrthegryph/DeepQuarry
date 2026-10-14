// machines system operations moved from code/modules/power/power_bridge.dm.

/datum/system/machines/proc/power_flush_areas()
	stat_drain_point() // the on_change hooks that mark an area dirty run at a drain: take them before reading the set
	// Only the areas whose loads changed: an area is marked when a demand stat of it changes, when its APC changes, when its APC's node is
	// bound again (Rust lost its copy) and when a one-off is booked (power_loads_changed()). An idle station sends nothing and walks nothing.
	for(var/area/A as anything in power_dirty_areas)
		var/obj/machinery/power/apc/serving = A.apc
		if(serving?.vg_entity && serving.area == A)
			var/equip_load = A.demand(EQUIP)
			var/light_load = A.demand(LIGHT)
			var/environ_load = A.demand(ENVIRON)
			var/list/sent = serving.pushed_demand
			if(!sent || sent[1] != equip_load || sent[2] != light_load || sent[3] != environ_load)
				native_write(serving, NATIVE_APC_STATIC_LOAD, equip_load, 0)
				native_write(serving, NATIVE_APC_STATIC_LOAD, light_load, 1)
				native_write(serving, NATIVE_APC_STATIC_LOAD, environ_load, 2)
				serving.pushed_demand = list(equip_load, light_load, environ_load)
				log_world("POWER_DEMAND: [serving] ([A]) now carries [equip_load] W equipment, [light_load] W lighting, [environ_load] W environment")
			// The one-offs: a pulse, handed over once and cleared.
			if(A.oneoff_equip || A.oneoff_light || A.oneoff_environ)
				native_write(serving, NATIVE_APC_ONEOFF, A.oneoff_equip, 0)
				native_write(serving, NATIVE_APC_ONEOFF, A.oneoff_light, 1)
				native_write(serving, NATIVE_APC_ONEOFF, A.oneoff_environ, 2)
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
			rel_remove(src, nameof(power_material_cables), cable)
			continue
		var/id = cable.get_power_region()
		if(id && !power_material_overlays[id])
			rel_add(src, nameof(power_material_overlays), new /datum/material_power_overlay(id), id)
	for(var/id in power_material_overlays)
		var/datum/material_power_overlay/overlay = power_material_overlays[id]
		if(!power_grids.lookup(id) || !overlay.process_material_network())
			rel_remove(src, nameof(power_material_overlays), overlay) // owned: removing it disposes of it

/// Clears every DM-side power cache and re-registers every cable, power
/// machine, APC and SMES (admin repair): unbinds and rebinds every
/// `vg_entity` a power object holds, so a divergence from Rust's own state
/// cannot survive it.
/datum/system/machines/proc/power_reregister_all()
	rel_clear(src, nameof(power_material_overlays))
	power_grids.clear()
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
	for(var/obj/machinery/power/apc/apc in world)
		apc.pushed_demand = null // Rust lost its copy of the standing load with the rebind
		apc.area?.power_loads_changed()
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
