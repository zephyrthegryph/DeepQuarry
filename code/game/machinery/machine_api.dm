// The machine system's API (code/game/machinery/machine_service.dm declares the system).
//
//   SSmachines.queue_pump_transfer(...)                   a pump queues its gas transfer for the batched commit

/datum/system/machines/proc/queue_pump_transfer(obj/machinery/atmospherics/M, datum/gas_mixture/source, datum/gas_mixture/sink, requested_moles, specific_power, source_moles, source_volume)
	if(!M || !source || !sink || requested_moles <= 0)
		return FALSE
	// Machine and sink by handle, both mixes by arena id: a queued transfer never keeps a machine or a mixture wrapper alive.
	var/machine_h = ref_token(M)
	var/sink_h = ref_token(sink)
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

/// An engineered conductor joins the material power overlay's cable set.
/datum/system/machines/proc/track_material_cable(obj/structure/cable/cable)
	rel_add(src, nameof(power_material_cables), cable)

/datum/system/machines/proc/untrack_material_cable(obj/structure/cable/cable)
	rel_remove(src, nameof(power_material_cables), cable)

/// The next id of a detached test grid (they count down from -1; Rust never sees them).
/datum/system/machines/proc/next_test_grid_id()
	return --power_test_grid_serial

/// Profile reads for the time-track log (the machine system's own cost and fire count).
/datum/system/machines/proc/profile_fire_cost()
	return fire_cost

/datum/system/machines/proc/cycles_run()
	return times_fired
