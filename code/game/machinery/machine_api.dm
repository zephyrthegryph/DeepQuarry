// The machine system's API (code/game/machinery/machine_service.dm declares the system).
//
//   SSmachines.queue_pump_transfer(...)                   a pump queues its gas transfer for the batched commit

/datum/system/machines/proc/queue_pump_transfer(obj/machinery/atmospherics/M, datum/gas_mixture/source, datum/gas_mixture/sink, requested_moles, specific_power, source_moles, source_volume)
	if(!M || !source || !sink || requested_moles <= 0)
		return FALSE
	pending_pump_transfers += list(list(M, source, sink, requested_moles, specific_power, source_moles, source_volume))
	return TRUE

/// The domain's stable lookup provider. Registry identity persists across repair.
/datum/system/machines/proc/power_grid_registry()
	return power_grids

/// Preserve the existing public collection API: callers receive numeric IDs.
/proc/machines_power_grids()
	return SSmachines.power_grid_registry().ids()
