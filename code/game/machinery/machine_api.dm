// The machine system's API (code/game/machinery/machine_service.dm declares the system).
//
//   SSmachines.queue_pump_transfer(...)                   a pump queues its gas transfer for the batched commit

/datum/system/machines/proc/queue_pump_transfer(obj/machinery/atmospherics/M, datum/gas_mixture/source, datum/gas_mixture/sink, requested_moles, specific_power, source_moles, source_volume)
	if(!M || !source || !sink || requested_moles <= 0)
		return FALSE
	// Machine and sink by handle, both mixes by arena id: a queued transfer never keeps a machine or a mixture wrapper alive.
	var/machine_h = entity_handle(M)
	var/sink_h = entity_handle(sink)
	if(!machine_h || !sink_h)
		return FALSE
	pending_pump_transfers += list(list(machine_h, source.arena_id(), sink.arena_id(), requested_moles, specific_power, source_moles, source_volume, sink_h))
	return TRUE

/// The domain's stable lookup provider. Registry identity persists across repair.
/datum/system/machines/proc/power_grid_registry()
	RETURN_TYPE(/datum/power_grid_registry)
	return power_grids

/// Preserve the existing public collection API: callers receive numeric IDs.
/proc/machines_power_grids()
	return SSmachines.power_grid_registry().ids()

/datum/system/machines/proc/material_power_overlay(id)
	return power_material_overlays[id]

/datum/system/machines/proc/register_material_cable(obj/structure/cable/cable)
	rel_add(src, nameof(power_material_cables), cable)

/datum/system/machines/proc/unregister_material_cable(obj/structure/cable/cable)
	rel_remove(src, nameof(power_material_cables), cable)

/datum/system/machines/proc/queue_area_power_load(area/A)
	power_dirty_areas[A] = TRUE

/datum/system/machines/proc/next_detached_grid_id()
	return --power_test_grid_serial

/datum/system/machines/proc/note_dead_gas_watch()
	gas_dead_last++

/datum/system/machines/proc/kernel_cost()
	return kernel().work_cost_of(type)

/datum/system/machines/proc/scheduling_snapshot()
	return list("fire_cost" = fire_cost, "times_fired" = times_fired)
