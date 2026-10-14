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
