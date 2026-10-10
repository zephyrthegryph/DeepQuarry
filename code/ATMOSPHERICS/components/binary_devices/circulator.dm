//node1, air1, network1 correspond to input
//node2, air2, network2 correspond to output
/obj/machinery/atmospherics/binary/circulator
	name = "circulator"
	desc = "A gas circulator turbine and heat exchanger."
	icon = 'icons/obj/power.dmi'
	icon_state = "circ-unassembled"
	anchored = FALSE
	unacidable = TRUE
	pipe_flags = PIPING_DEFAULT_LAYER_ONLY|PIPING_ONE_PER_TURF

	var/kinetic_efficiency = 0.04 //combined kinetic and kinetic-to-electric efficiency
	var/volume_ratio = 0.2

	var/recent_moles_transferred = 0
	var/last_heat_capacity = 0
	var/last_temperature = 0
	var/last_pressure_delta = 0
	EXPIRY_DECLARE(last_worldtime_transfer)
	var/last_stored_energy_transferred = 0
	var/volume_capacity_used = 0
	var/stored_energy = 0
	var/temperature_overlay
	/// What its turbine shows: "off", "slow" or "run" (set as it circulates).
	var/run_state = "off"

	density = TRUE

TRACKED(/obj/machinery/atmospherics/binary/circulator, temperature_overlay)
TRACKED(/obj/machinery/atmospherics/binary/circulator, run_state)

MSG_DEF(circulator/secured, "You secure the bolts holding %T% to the floor.", "%U% secures the bolts holding %T% to the floor.")
MSG_DEF(circulator/unsecured, "You unsecure the bolts holding %T% to the floor.", "%U% unsecures the bolts holding %T% to the floor.")

CAPABILITIES(/obj/machinery/atmospherics/binary/circulator)
	rotatable()
	op("anchor", tool(TOOL_WRENCH), label("Wrench"), wait(0), says(PROC_REF(anchor_message)), then(PROC_REF(anchor_toggled)))

/obj/machinery/atmospherics/binary/circulator/Initialize(mapload)
	. = ..()
	air1.set_volume(400)

/obj/machinery/atmospherics/binary/circulator/proc/return_transfer_air()
	var/datum/gas_mixture/removed
	if(anchored && !broken_now() && network1)
		var/input_starting_pressure = air1.return_pressure()
		var/output_starting_pressure = air2.return_pressure()
		last_pressure_delta = max(input_starting_pressure - output_starting_pressure - 5, 0)

		//only circulate air if there is a pressure difference (plus 5kPa kinetic, 10kPa static friction)
		var/air1_temperature = air1.return_temperature()
		var/air1_volume = air1.return_volume()
		if(air1_temperature > 0 && last_pressure_delta > 5)

			//Calculate necessary moles to transfer using PV = nRT
			recent_moles_transferred = (last_pressure_delta*network1.volume()/(air1_temperature * R_IDEAL_GAS_EQUATION))/3 //uses the volume of the whole network, not just itself
			volume_capacity_used = min( (last_pressure_delta*network1.volume()/3)/(input_starting_pressure*air1_volume) , 1) //how much of the gas in the input air volume is consumed

			//Calculate energy generated from kinetic turbine
			stored_energy += 1/ADIABATIC_EXPONENT * min(last_pressure_delta * network1.volume() , input_starting_pressure*air1_volume) * (1 - volume_ratio**ADIABATIC_EXPONENT) * kinetic_efficiency

			//Actually transfer the gas
			removed = air1.remove(recent_moles_transferred)
			if(removed)
				last_heat_capacity = removed.heat_capacity()
				last_temperature = removed.return_temperature()

				//Update the gas networks.
				gas_touched(air1)

				EXPIRY_STAMP(src, last_worldtime_transfer, CLOCK_WORLD)
				// The "running" overlay times out 5 s after the last transfer: one keyed timer, re-armed per transfer.
				after(src, 5 SECONDS, PROC_REF(expire_transfer_display), key = "transfer_display")
		else
			recent_moles_transferred = 0

		update_run_state()
		return removed

/obj/machinery/atmospherics/binary/circulator/proc/return_stored_energy()
	last_stored_energy_transferred = stored_energy
	stored_energy = 0
	return last_stored_energy_transferred

/obj/machinery/atmospherics/binary/circulator/proc/expire_transfer_display()
	if(!recent_moles_transferred || ELAPSED(src, last_worldtime_transfer, CLOCK_WORLD) < 5 SECONDS)
		return
	recent_moles_transferred = 0
	update_run_state()

/// What its turbine shows, from its last circulation.
/obj/machinery/atmospherics/binary/circulator/proc/update_run_state()
	if(last_pressure_delta > 0 && recent_moles_transferred > 0)
		set_run_state(last_pressure_delta > 5*ONE_ATMOSPHERE ? "run" : "slow")
	else
		set_run_state("off")

/obj/machinery/atmospherics/binary/circulator/draw(datum/look/look)
	..()
	look.state(anchored ? "circ-assembled" : "circ-unassembled")
	if(!operable() || !anchored)
		return
	if(run_state == "off")
		look.overlay("circ-off")
		return
	if(temperature_overlay)
		look.overlay(temperature_overlay)
	look.overlay("circ-[run_state]")

/obj/machinery/atmospherics/binary/circulator/derived()
	. = ..()
	. += drawn_from(nameof(run_state), nameof(temperature_overlay), nameof(anchored))

/obj/machinery/atmospherics/binary/circulator/proc/anchor_message(datum/act/A)
	return anchored ? /datum/msg/circulator/secured : /datum/msg/circulator/unsecured

/// The wrench bolts it down (joining its pipes) or frees it; the generators beside it look for their circulators again.
/obj/machinery/atmospherics/binary/circulator/proc/anchor_toggled(datum/act/op/A)
	set_anchored(!anchored)
	if(anchored)
		set_temperature_overlay(null)
		if(dir & (NORTH|SOUTH))
			initialize_directions = NORTH|SOUTH
		else if(dir & (EAST|WEST))
			initialize_directions = EAST|WEST

		atmos_init()
		if (node1)
			node1.atmos_init()
		if (node2)
			node2.atmos_init()
		rust_register_pipe_topology()
	else
		rust_unregister_pipe_topology()
		if(node1)
			node1.disconnect(src)
			rust_release_network_wrapper(network1)
		if(node2)
			node2.disconnect(src)
			rust_release_network_wrapper(network2)

		rel_clear(src, nameof(node1))
		rel_clear(src, nameof(node2))

	for(var/obj/machinery/power/generator/generator in range(1, src))
		generator.reconnect()
	return OP_OK

/obj/machinery/atmospherics/binary/circulator/examine(mob/user, infix, suffix)
	. = ..()
	. += span_infoplain("Its outlet port is to the [dir2text(dir)].")
