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

	density = TRUE

/obj/machinery/atmospherics/binary/circulator/Initialize(mapload)
	. = ..()
	air1.set_volume(400)
	make_rotatable()

/obj/machinery/atmospherics/binary/circulator/proc/return_transfer_air()
	var/datum/gas_mixture/removed
	if(anchored && !has_stat(BROKEN) && network1)
		var/input_starting_pressure = air1.return_pressure()
		var/output_starting_pressure = air2.return_pressure()
		last_pressure_delta = max(input_starting_pressure - output_starting_pressure - 5, 0)

		//only circulate air if there is a pressure difference (plus 5kPa kinetic, 10kPa static friction)
		var/air1_temperature = air1.return_temperature()
		var/air1_volume = air1.return_volume()
		if(air1_temperature > 0 && last_pressure_delta > 5)

			//Calculate necessary moles to transfer using PV = nRT
			recent_moles_transferred = (last_pressure_delta*network1.volume/(air1_temperature * R_IDEAL_GAS_EQUATION))/3 //uses the volume of the whole network, not just itself
			volume_capacity_used = min( (last_pressure_delta*network1.volume/3)/(input_starting_pressure*air1_volume) , 1) //how much of the gas in the input air volume is consumed

			//Calculate energy generated from kinetic turbine
			stored_energy += 1/ADIABATIC_EXPONENT * min(last_pressure_delta * network1.volume , input_starting_pressure*air1_volume) * (1 - volume_ratio**ADIABATIC_EXPONENT) * kinetic_efficiency

			//Actually transfer the gas
			removed = air1.remove(recent_moles_transferred)
			if(removed)
				last_heat_capacity = removed.heat_capacity()
				last_temperature = removed.return_temperature()

				//Update the gas networks.
				network1.mark_dirty()

				EXPIRY_STAMP(src, last_worldtime_transfer, CLOCK_WORLD)
				// The "running" overlay times out 5 s after the last transfer: one timer,
				// re-armed per transfer, instead of a machine polling the clock.
				om_after_replace(src, 5 SECONDS, PROC_REF(expire_transfer_display))
		else
			recent_moles_transferred = 0

		update_icon()
		return removed

/obj/machinery/atmospherics/binary/circulator/proc/return_stored_energy()
	last_stored_energy_transferred = stored_energy
	stored_energy = 0
	return last_stored_energy_transferred

/obj/machinery/atmospherics/binary/circulator/proc/expire_transfer_display()
	if(!recent_moles_transferred || ELAPSED(src, last_worldtime_transfer, CLOCK_WORLD) < 5 SECONDS)
		return
	recent_moles_transferred = 0
	update_icon()

/obj/machinery/atmospherics/binary/circulator/update_icon()
	icon_state = anchored ? "circ-assembled" : "circ-unassembled"
	cut_overlays()
	if (!operable() || !anchored)
		return 1
	if (last_pressure_delta > 0 && recent_moles_transferred > 0)
		if (temperature_overlay)
			add_overlay(temperature_overlay)
		if (last_pressure_delta > 5*ONE_ATMOSPHERE)
			add_overlay("circ-run")
		else
			add_overlay("circ-slow")
	else
		add_overlay("circ-off")

	return 1

/obj/machinery/atmospherics/binary/circulator/wrench_act(mob/user, obj/item/W)
	playsound(src, W.usesound, 75, 1)
	set_anchored(!anchored)
	act_message(user, src, MSG_SELF("You [anchored ? "secure" : "unsecure"] the bolts holding %T% to the floor."), \
		MSG_OTHERS("[user.name] [anchored ? "secures" : "unsecures"] the bolts holding [src.name] to the floor."), \
		MSG_BLIND("You hear a ratchet."))

	if(anchored)
		temperature_overlay = null
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

		rel_clear(src, "node1")
		rel_clear(src, "node2")

	for(var/obj/machinery/power/generator/generator in range(1, src))
		generator.reconnect()
		if(generator.anchored)
			MACHINE_WAKE(generator)
	return ITEM_INTERACT_SUCCESS

/obj/machinery/atmospherics/binary/circulator/examine(mob/user, infix, suffix)
	. = ..()
	. += span_infoplain("Its outlet port is to the [dir2text(dir)].")
