/obj/machinery/power/generator/oldteg
	name = "old thermoelectric generator"
	desc = "It's a 'high efficiency' thermoelectric generator, though this one seems a bit old and worn out. Are the turbines squeeking?"
	max_power = 500000
	thermal_efficiency = 0.40 // 25% less effective around 1400 kw with 24 shots

/obj/machinery/power/generator
	name = "thermoelectric generator"
	desc = "It's a high efficiency thermoelectric generator."
	icon_state = "teg-unassembled"
	density = TRUE
	anchored = FALSE
	unacidable = TRUE

	use_power = USE_POWER_IDLE
	idle_power_usage = 100 //Watts, I hope.  Just enough to do the computer and display things.

	var/max_power = 500000
	var/thermal_efficiency = 0.65

	var/tmp/obj/machinery/atmospherics/binary/circulator/circ1
	var/tmp/obj/machinery/atmospherics/binary/circulator/circ2

	var/last_circ1_gen = 0
	var/last_circ2_gen = 0
	var/last_thermal_gen = 0
	var/stored_energy = 0
	var/lastgen1 = 0
	var/lastgen2 = 0
	var/effective_gen = 0
	var/lastgenlev = 0
	var/datum/looping_sound/generator/soundloop

REGISTRY_MEMBERSHIP(/obj/machinery/power/generator, REGISTRY_TURBINES)

/obj/machinery/power/generator/Initialize(mapload)
	own_set(src, "soundloop", new /datum/looping_sound/generator(list(src), FALSE))
	desc = initial(desc) + " Rated for [round(max_power/1000)] kW."
	make_rotatable()
	..() //Not returned, because...
	return INITIALIZE_HINT_LATELOAD

/obj/machinery/power/generator/LateInitialize()
	reconnect()


//generators connect in dir and GLOB.reverse_dir(dir) directions
//mnemonic to determine circulator/generator directions: the cirulators orbit clockwise around the generator
//so a circulator to the NORTH of the generator connects first to the EAST, then to the WEST
//and a circulator to the WEST of the generator connects first to the NORTH, then to the SOUTH
//note that the circulator's outlet dir is it's always facing dir, and it's inlet is always the reverse
/obj/machinery/power/generator/proc/reconnect()
	clear_gas_dependencies()
	rel_clear(src, "circ1")
	rel_clear(src, "circ2")
	if(src.loc && anchored)
		if(src.dir & (EAST|WEST))
			rel_set(src, "circ1", locate_within(get_step(src,WEST), /obj/machinery/atmospherics/binary/circulator))
			rel_set(src, "circ2", locate_within(get_step(src,EAST), /obj/machinery/atmospherics/binary/circulator))

			if(circ1() && circ2())
				if(circ1().dir != NORTH || circ2().dir != SOUTH)
					rel_clear(src, "circ1")
					rel_clear(src, "circ2")

		else if(src.dir & (NORTH|SOUTH))
			rel_set(src, "circ1", locate_within(get_step(src,NORTH), /obj/machinery/atmospherics/binary/circulator))
			rel_set(src, "circ2", locate_within(get_step(src,SOUTH), /obj/machinery/atmospherics/binary/circulator))

			if(circ1() && circ2() && (circ1().dir != EAST || circ2().dir != WEST))
				rel_clear(src, "circ1")
				rel_clear(src, "circ2")

/// Wakes only once either circulator loop has a pressure head worth turning -- the test the old
/// dependency filter made.
/obj/machinery/power/generator/proc/register_gas_dependencies()
	clear_gas_dependencies()
	if(!circ1() || !circ2())
		return
	var/list/mixture_ids = list()
	for(var/datum/gas_mixture/air as anything in list(circ1().air1, circ1().air2, circ2().air1, circ2().air2))
		var/id = air?.arena_id()
		if(!isnull(id))
			mixture_ids |= id
	om_watch_arm_condition(src, "gas", mixture_ids, GAS_DEPENDENCY_PRESSURE, om_callable(src, PROC_REF(gas_wake_condition)), wake_callback = om_callable(src, PROC_REF(wake_from_gas)))

/obj/machinery/power/generator/proc/gas_wake_condition()
	if(!circ1() || !circ2())
		return FALSE
	return (circ1().air1.return_pressure() - circ1().air2.return_pressure() > 10) || (circ2().air1.return_pressure() - circ2().air2.return_pressure() > 10)

/obj/machinery/power/generator/proc/clear_gas_dependencies()
	om_watch_disarm(src, "gas")

/obj/machinery/power/generator/proc/wake_from_gas()
	clear_gas_dependencies()
	MACHINE_WAKE(src)

/obj/machinery/power/generator/update_icon()
	icon_state = anchored ? "teg-assembled" : "teg-unassembled"
	cut_overlays()
	if (circ1())
		circ1().temperature_overlay = null
	if (circ2())
		circ2().temperature_overlay = null
	if (!operable())
		return 1
	else
		if (lastgenlev != 0)
			add_overlay("teg-op[lastgenlev]")
			if (circ1() && circ2())
				var/extreme = (lastgenlev > 9) ? "ex" : ""
				if (circ1().last_temperature < circ2().last_temperature)
					circ1().temperature_overlay = "circ-[extreme]cold"
					circ2().temperature_overlay = "circ-[extreme]hot"
				else
					circ1().temperature_overlay = "circ-[extreme]hot"
					circ2().temperature_overlay = "circ-[extreme]cold"
		return 1

/obj/machinery/power/generator/machine_step()
	if(!anchored)
		stored_energy = 0
		set_power_supply(0)
		return PROCESS_KILL
	if(!circ1() || !circ2() || !operable())
		stored_energy = 0
		set_power_supply(0)
		return PROCESS_KILL

	var/datum/gas_mixture/air1 = circ1().return_transfer_air()
	var/datum/gas_mixture/air2 = circ2().return_transfer_air()

	lastgen2 = lastgen1
	lastgen1 = 0
	last_thermal_gen = 0
	last_circ1_gen = 0
	last_circ2_gen = 0

	if(air1 && air2)
		var/air1_heat_capacity = air1.heat_capacity()
		var/air2_heat_capacity = air2.heat_capacity()
		var/delta_temperature = abs(air2.return_temperature() - air1.return_temperature())

		if(delta_temperature > 0 && air1_heat_capacity > 0 && air2_heat_capacity > 0)
			var/energy_transfer = delta_temperature*air2_heat_capacity*air1_heat_capacity/(air2_heat_capacity+air1_heat_capacity)
			var/heat = energy_transfer*(1-thermal_efficiency)
			last_thermal_gen = energy_transfer*thermal_efficiency

			if(air2.return_temperature() > air1.return_temperature())
				air2.set_temperature(air2.return_temperature() - energy_transfer/air2_heat_capacity)
				air1.set_temperature(air1.return_temperature() + heat/air1_heat_capacity)
			else
				air2.set_temperature(air2.return_temperature() + heat/air2_heat_capacity)
				air1.set_temperature(air1.return_temperature() - energy_transfer/air1_heat_capacity)

	//Transfer the air
	if (air1)
		circ1().air2.merge(air1)
	if (air2)
		circ2().air2.merge(air2)

	//Update the gas networks
	if(circ1().network2)
		circ1().network2.mark_dirty()
	if(circ2().network2)
		circ2().network2.mark_dirty()

	//Exceeding maximum power leads to some power loss
	if(effective_gen > max_power && prob(5))
		fx_sparks(src, 3)
		stored_energy *= 0.5

	//Power
	last_circ1_gen = circ1().return_stored_energy()
	last_circ2_gen = circ2().return_stored_energy()
	stored_energy += last_thermal_gen + last_circ1_gen + last_circ2_gen
	lastgen1 = stored_energy*0.4 //smoothened power generation to prevent slingshotting as pressure is equalized, then restored by pumps
	stored_energy -= lastgen1
	effective_gen = (lastgen1 + lastgen2) / 2

	// Sounds.
	if(effective_gen > (max_power * 0.05)) // More than 5% and sounds start.
		soundloop.start()
		soundloop.volume = LERP(1, 40, effective_gen / max_power)
	else
		soundloop.stop()

	// update icon overlays and power usage only if displayed level has changed
	var/genlev = max(0, min( round(11*effective_gen / max_power), 11))
	if(effective_gen > 100 && genlev == 0)
		genlev = 1
	if(genlev != lastgenlev)
		lastgenlev = genlev
		update_icon()
	// A supply rate, not a per-tick pulse: the TEG is a steady generator (M3).
	set_power_supply(effective_gen)
	if(!air1 && !air2 && stored_energy < 0.01 && effective_gen < 0.01)
		set_power_supply(0)
		GLOB.machine_service.hibernate_generator(src)
		return PROCESS_KILL

/obj/machinery/power/generator/wrench_act(mob/user, obj/item/W)
	playsound(src, W.usesound, 75, 1)
	set_anchored(!anchored)
	act_message(user, src, MSG_SELF("You [anchored ? "secure" : "unsecure"] the bolts holding %T% to the floor."), \
		MSG_OTHERS("[user.name] [anchored ? "secures" : "unsecures"] the bolts holding [src.name] to the floor."), \
		MSG_BLIND("You hear a ratchet."))
	set_use_power(anchored ? USE_POWER_IDLE : USE_POWER_ACTIVE)
	if(anchored)
		MACHINE_WAKE(src)
	if(anchored)
		connect_to_network()
	else
		disconnect_from_network()
	reconnect()
	lastgenlev = 0
	effective_gen = 0
	update_icon()
	return ITEM_INTERACT_SUCCESS

/obj/machinery/power/generator/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/ungated/generator_open_ui,
	)
	..()

/// Old attack_hand: never called ..().
/datum/interaction/machine_hand/ungated/generator_open_ui
	id = "generator_open_ui"
	name = "Use"
	effect = /obj/machinery/power/generator/proc/interaction_open_ui_impl

/obj/machinery/power/generator/proc/interaction_open_ui_impl(mob/user, obj/item/held, datum/interaction/interaction)
	add_fingerprint(user)
	if(!operable() || !anchored)
		return TRUE
	if(!circ1() || !circ2()) //Just incase the middle part of the TEG was not wrenched last.
		reconnect()
	tgui_interact(user)
	return TRUE

DECLARE_UI(/obj/machinery/power/generator, "TEGenerator")

UI_DATA_REPLACE(/obj/machinery/power/generator, "totalOutput=effective_gen:num", "maxTotalOutput=max_power:num", "thermalOutput=last_thermal_gen:num", "merge:ui_data_obj_machinery_power_generator{primary:list,secondary:list}")

/// The computed part of /obj/machinery/power/generator's window data (declared on its UI_DATA row).
/obj/machinery/power/generator/proc/ui_data_obj_machinery_power_generator(mob/user, datum/tgui/ui, datum/tgui_state/state)
	// this is the data which will be sent to the ui
	var/vertical = 0
	if (dir == NORTH || dir == SOUTH)
		vertical = 1

	var/list/data = list()

	data["primary"] = null
	if(circ1())
		//The one on the left (or top)
		data["primary"] = list()
		data["primary"]["dir"] = vertical ? "top" : "left"
		data["primary"]["output"] = last_circ1_gen
		data["primary"]["flowCapacity"] = circ1().volume_capacity_used*100
		data["primary"]["inletPressure"] = circ1().air1.return_pressure()
		data["primary"]["inletTemperature"] = circ1().air1.return_temperature()
		data["primary"]["outletPressure"] = circ1().air2.return_pressure()
		data["primary"]["outletTemperature"] = circ1().air2.return_temperature()

	data["secondary"] = null
	if(circ2())
		//Now for the one on the right (or bottom)
		data["secondary"] = list()
		data["secondary"]["dir"] = vertical ? "bottom" : "right"
		data["secondary"]["output"] = last_circ2_gen
		data["secondary"]["flowCapacity"] = circ2().volume_capacity_used*100
		data["secondary"]["inletPressure"] = circ2().air1.return_pressure()
		data["secondary"]["inletTemperature"] = circ2().air1.return_temperature()
		data["secondary"]["outletPressure"] = circ2().air2.return_pressure()
		data["secondary"]["outletTemperature"] = circ2().air2.return_temperature()

	return data

/obj/machinery/power/generator/power_change()
	. = ..()
	if(anchored)
		clear_gas_dependencies()
		MACHINE_WAKE(src)
	update_icon()

/obj/machinery/power/generator/power_spike(announce_prob = 30)
	if(!(effective_gen >= max_power / 2 && power_region)) // Don't make a spike if we're not making a whole lot of power.
		return

	var/list/powernet_union = LAZYCOPY(power_grid_nodes(power_region))
	for(var/obj/machinery/power/terminal/T in power_grid_nodes(power_region))
		if(T.master() && istype(T.master(), /obj/machinery/power/smes))
			var/obj/machinery/power/smes/S = T.master()
			if(length(power_grid_nodes(S.power_region))) powernet_union |= power_grid_nodes(S.power_region)

	var/found_grid_checker = FALSE
	for(var/obj/machinery/power/grid_checker/G in powernet_union)
		G.power_failure(announce_prob) // If we found a grid checker, then all is well.
		found_grid_checker = TRUE
	if(!found_grid_checker) // Otherwise lets break some stuff.
		om_after(src, 1, PROC_REF(announce_power_spike))
		// The overloads roll through the network a machine a tick, each on the machine's clock.
		var/i = 0
		var/limit = rand(30, 50)
		for(var/obj/machinery/power/P in powernet_union)
			i++
			om_after(P, i, TYPE_PROC_REF(/obj/machinery/power, overload), src)
			if(i >= limit)
				break

/obj/machinery/power/generator/proc/announce_power_spike()
	GLOB.command_announcement.Announce("Dangerous power spike detected in the power network.  Please check machinery \
	for electrical damage.",
	"Critical Power Overload",
	ANNOUNCER_MSG_POWERSPIKE)

/// Setup at spawn: arm what wakes it (machine_pipeline.dm, materialize_wakes()).
/obj/machinery/power/generator/arm_wakes()
	..()
	register_gas_dependencies()

/// the circ1 this refers to: a relation view, null once that is deleted.
/obj/machinery/power/generator/proc/circ1() as /obj/machinery/atmospherics/binary/circulator
	return circ1

/// the circ2 this refers to: a relation view, null once that is deleted.
/obj/machinery/power/generator/proc/circ2() as /obj/machinery/atmospherics/binary/circulator
	return circ2
