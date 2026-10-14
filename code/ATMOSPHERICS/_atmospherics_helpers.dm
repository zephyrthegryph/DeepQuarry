/*
	Atmos processes

	These procs are thin wrappers over the Rust gas transfer binds (vg_pump, vg_scrub, vg_transfer_to_pressure; the maths and the
	movement are verdigris/domains/gas/src/power_budget.rs). What stays here is what only DM knows: the device's material hooks
	(efficiency, available power, what the move is recorded as) and the flow meter it feeds.
	If no gas was moved, they return a negative number.
	Otherwise they return the amount of energy needed to do whatever it is they do (equivalently power if done over 1 second).
	In the case of free-flowing gas you can do things with gas and still use 0 power, hence the distinction between negative and non-negative return values.
	Filtering and mixing are the pipe devices' own Rust flows (vg_filter_transfer, vg_mix_transfer and the multi form).
*/


/obj/machinery/atmospherics/var/last_flow_rate = 0
/obj/machinery/atmospherics/var/last_power_draw = 0
/obj/machinery/portable_atmospherics/var/last_flow_rate = 0


/obj/machinery/atmospherics/var/debug = 0

ADMIN_VERB(atmos_toggle_debug, R_DEBUG, "Toggle Debug Messages", "Allows to toggle receiving debug messages.", ADMIN_CATEGORY_DEBUG_MISC, obj/machinery/atmospherics/machine in view())
	machine.debug = !machine.debug
	to_chat(user, span_debug_info("[machine]: Debug messages toggled [machine.debug? "on" : "off"]."))

/// The flow meter and debug line of a move that happened: `moved` is the list vg_pump()/vg_scrub() returned,
/// list(moles, power_draw, flow_volume).
/proc/atmos_note_flow(obj/machinery/M, list/moved)
	if(istype(M, /obj/machinery/atmospherics))
		var/obj/machinery/atmospherics/A = M
		A.last_flow_rate = moved[3]
		if(A.debug)
			A.visible_message("[A]: moles transferred = [moved[1]] mol, power = [round(moved[2], 0.1)] W")
	else if(istype(M, /obj/machinery/portable_atmospherics))
		var/obj/machinery/portable_atmospherics/P = M
		P.last_flow_rate = moved[3]

/// The efficiency divisor of a device's pump moves (ATMOS_PUMP_EFFICIENCY with the material multiplier), or of its
/// filter/scrub moves.
/proc/atmos_pump_efficiency(obj/machinery/M, base)
	return base * (M ? M.material_pump_efficiency() / 0.8 : 1)

//Generalized gas pumping proc.
//Moves gas from one gas_mixture to another and returns the amount of power needed (assuming 1 second), or -1 if no gas was pumped.
//transfer_moles - Limits the amount of moles to transfer. The actual amount of gas moved may also be limited by available_power, if given.
//available_power - the maximum amount of power that may be used when moving gas. If null then the transfer is not limited by power.
/proc/pump_gas(obj/machinery/M, datum/gas_mixture/source, datum/gas_mixture/sink, transfer_moles = null, available_power = null)
	if(M)
		available_power = M.material_pump_power(available_power)
	var/list/moved = vg_pump(source, sink, transfer_moles, available_power, atmos_pump_efficiency(M, ATMOS_PUMP_EFFICIENCY), VG_PUMP_ACTIVE)
	if(!moved)
		return -1
	atmos_note_flow(M, moved)
	M?.record_material_pumping(moved[2], sink, moved[1])
	return moved[2]

/// Deferred variant used by station vents. It performs the same authoritative
/// flow/power calculation (a plan: nothing moves) but queues the actual gas mutation into the Machines
/// subsystem's single Rust transaction.
/proc/queue_pump_gas(obj/machinery/atmospherics/M, datum/gas_mixture/source, datum/gas_mixture/sink, transfer_moles = null, available_power = null)
	available_power = M.material_pump_power(available_power)
	var/list/plan = vg_pump(source, sink, transfer_moles, available_power, atmos_pump_efficiency(M, ATMOS_PUMP_EFFICIENCY), VG_PUMP_PLAN)
	if(!plan)
		return -1
	var/specific_power = plan[1] > 0 ? plan[2] / plan[1] : 0
	if(!SSmachines.queue_pump_transfer(M, source, sink, plan[1], specific_power, plan[1], plan[3]))
		return -1
	return plan[2]

//Gas 'pumping' proc for the case where the gas flow is passive and driven entirely by pressure differences (but still one-way).
/proc/pump_gas_passive(obj/machinery/M, datum/gas_mixture/source, datum/gas_mixture/sink, transfer_moles = null)
	var/list/moved = vg_pump(source, sink, transfer_moles, null, 1, VG_PUMP_PASSIVE)
	if(!moved)
		return -1
	atmos_note_flow(M, moved)
	return 0

//Generalized gas scrubbing proc.
//Selectively moves specified gasses one gas_mixture to another and returns the amount of power needed (assuming 1 second), or -1 if no gas was filtered.
//filtering - A list of gasids to be scrubbed from source
//total_transfer_moles - Limits the amount of moles to scrub. The actual amount of gas scrubbed may also be limited by available_power, if given.
//available_power - the maximum amount of power that may be used when scrubbing gas. If null then the scrubbing is not limited by power.
/proc/scrub_gas(obj/machinery/M, list/filtering, datum/gas_mixture/source, datum/gas_mixture/sink, total_transfer_moles = null, available_power = null)
	if(M)
		available_power = M.material_pump_power(available_power)
	var/mask = 0
	for(var/g in filtering)
		mask |= (1 << GAS_IDX(g))
	var/list/moved = vg_scrub(source, sink, mask, total_transfer_moles, available_power, atmos_pump_efficiency(M, ATMOS_FILTER_EFFICIENCY))
	if(!moved)
		return -1
	atmos_note_flow(M, moved)
	M?.record_material_pumping(moved[2], sink, moved[1])
	return moved[2]

/*
	Helper procs for various things.
*/

//Calculates the APPROXIMATE amount of moles that would need to be transferred to change the pressure of sink by pressure_delta
//If set, sink_volume_mod adjusts the effective output volume used in the calculation. This is useful when the output gas_mixture is
//part of a pipenetwork, and so it's volume isn't representative of the actual volume since the gas will be shared across the pipenetwork when it processes.
/proc/calculate_transfer_moles(datum/gas_mixture/source, datum/gas_mixture/sink, pressure_delta, sink_volume_mod=0)
	// One Rust solve (vg_moles_to_pressure): exact mixing temperature, no estimate. The sink's
	// pressure is taken over its volume plus sink_volume_mod, the delta is applied on top.
	var/sink_volume = sink.return_volume()
	var/current_pressure = sink.return_pressure() * sink_volume / max(sink_volume + sink_volume_mod, 1)
	return vg_moles_to_pressure(source, sink, current_pressure + pressure_delta, 0, sink_volume_mod)

//
// Debugging helper procs
//

/proc/atmos_piping_layer_str(piping_layer)
	switch(piping_layer)
		if(PIPING_LAYER_SUPPLY)
			return "SUPPLY"
		if(PIPING_LAYER_REGULAR)
			return "REGULAR"
		if(PIPING_LAYER_SCRUBBER)
			return "SCRUBBER"
		if(PIPING_LAYER_FUEL)
			return "FUEL"
		if(PIPING_LAYER_AUX)
			return "AUX"

/proc/atmos_pipe_flags_str(pipe_flags)
	var/list/dat = list()
	if(pipe_flags & PIPING_ALL_LAYER)
		dat += "ALL_LAYER"
	if(pipe_flags & PIPING_ONE_PER_TURF)
		dat += "ONE_PER_TURF"
	if(pipe_flags & PIPING_DEFAULT_LAYER_ONLY)
		dat += "DEFAULT_LAYER_ONLY"
	if(pipe_flags & PIPING_CARDINAL_AUTONORMALIZE)
		dat += "CARDINAL_AUTONORMALIZE"
	return dat.Join("|")

/proc/atmos_connect_types_str(connect_types)
	var/list/dat = list()
	if(connect_types & CONNECT_TYPE_REGULAR)
		dat += "REGULAR"
	if(connect_types & CONNECT_TYPE_SUPPLY)
		dat += "SUPPLY"
	if(connect_types & CONNECT_TYPE_SCRUBBER)
		dat += "SCRUBBER"
	if(connect_types & CONNECT_TYPE_FUEL)
		dat += "FUEL"
	if(connect_types & CONNECT_TYPE_AUX)
		dat += "AUX"
	if(connect_types & CONNECT_TYPE_HE)
		dat += "HE"
	return dat.Join("|")
