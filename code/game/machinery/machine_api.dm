// The machine system's API (code/game/machinery/machine_service.dm declares the system).
//
//   SSmachines.queue_pump_transfer(...)                   a pump queues its gas transfer for the batched commit
//   SSmachines.hibernate_generator(generator)   sleep a device on its gas watches

/datum/system/machines/proc/queue_pump_transfer(obj/machinery/atmospherics/M, datum/gas_mixture/source, datum/gas_mixture/sink, requested_moles, specific_power, source_moles, source_volume)
	if(!M || !source || !sink || requested_moles <= 0)
		return FALSE
	pending_pump_transfers += list(list(M, source, sink, requested_moles, specific_power, source_moles, source_volume))
	return TRUE

/datum/system/machines/proc/hibernate_generator(obj/machinery/power/generator/G)
	if(!G)
		return
	G.register_gas_dependencies()
	MACHINE_SLEEP(G)
