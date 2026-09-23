/obj/machinery/power/thermoregulator/cryogaia
	name = "Custom Thermal Regulator"
	desc = "A massive custom made Thermal regulator or CTR for short, intended to keep heat loss when going in our outside to a minimum, they are hardwired to twenty celsius"
	icon = 'icons/obj/machines/wallthermal.dmi'
	icon_state = "lasergen"
	density = 0
	anchored = 1
	//Consider making this powered by the room at some point.
	use_power = 0 //is powered directly from cables
	active_power_usage = 25 KILOWATTS  //Low Power
	idle_power_usage = 250

	circuit = null
	maintenance_flags = MACHINE_MAINT_STANDARD
	/*
	null so people can not deconstruct them and remake them to normal Regulators,
	probably should just make a circuit for it but this is pretty much just a proof of concept at the moment.
	*/

/obj/machinery/power/thermoregulator/cryogaia/wrench_act(mob/user, obj/item/I)
	anchored = !anchored
	visible_message(span_notice("\The [src] has been [anchored ? "bolted to the floor" : "unbolted from the floor"] by [user].")) //Does this not need to be disabled?
	playsound(src, I.usesound, 75, 1)
	if(anchored)
		connect_to_network()
	else
		disconnect_from_network()
		turn_off()
	return ITEM_INTERACT_SUCCESS

#define MODE_IDLE 0
#define MODE_HEATING 1
#define MODE_COOLING 2
/obj/machinery/power/thermoregulator/southerncross
	name = "Custom Thermal Regulator"
	desc = "A massive custom made Thermal regulator or CTR for short, intended to keep heat loss when going in our outside to a minimum."
	icon = 'icons/obj/machines/wallthermal.dmi'
	icon_state = "lasergen"
	density = 0
	anchored = 1
	//Consider making this powered by the room at some point.
	use_power = 0 //is powered directly from cables
	active_power_usage = 250 // VERY low power use
	idle_power_usage = 250

	circuit = null
	/*
	null so people can not deconstruct them and remake them to normal Regulators,
	probably should just make a circuit for it but this is pretty much just a proof of concept at the moment.
	*/

/obj/machinery/power/thermoregulator/southerncross/process()
	if(!on)
		return PROCESS_KILL
	if(!powernet)
		turn_off()
		return PROCESS_KILL

	var/datum/gas_mixture/env = loc.return_air()
	if(!env || abs(env.return_temperature() - target_temp) < 1)
		change_mode(MODE_IDLE)
		hibernate_until_temperature_changes()
		return PROCESS_KILL

	var/datum/gas_mixture/removed = env.remove_ratio(0.99)
	if(!removed)
		change_mode(MODE_IDLE)
		hibernate_until_temperature_changes()
		return PROCESS_KILL

	var/heat_transfer = removed.get_thermal_energy_change(target_temp)
	// var/power_avail
	if(heat_transfer == 0) //just in case
		change_mode(MODE_IDLE)
	else if(heat_transfer > 0)
		change_mode(MODE_HEATING)
		// power_avail = draw_power(min(heat_transfer, active_power_usage))
		removed.add_thermal_energy(min(active_power_usage*1000,heat_transfer))
	else
		change_mode(MODE_COOLING)
		heat_transfer = abs(heat_transfer)
		var/cop = removed.return_temperature()/TN60C
		var/actual_heat_transfer = heat_transfer
		heat_transfer = min(heat_transfer, active_power_usage*cop)
		// power_avail = draw_power(heat_transfer/cop)
		removed.add_thermal_energy(-min(active_power_usage*1000*cop,actual_heat_transfer))
	env.merge(removed)

// Given the power behind this thermodynamics defying machine, nerfing EMP effectiveness.
/obj/machinery/power/thermoregulator/southerncross/emp_act(severity)
	if(!on)
		on = 1
	target_temp += rand(0, 20)
	wake_for_state_change()
	update_icon()
	..(severity)

#undef MODE_IDLE
#undef MODE_HEATING
#undef MODE_COOLING

#define MODE_IDLE 0
#define MODE_HEATING 1
#define MODE_COOLING 2

/obj/machinery/power/thermoregulator
	name = "thermal regulator"
	desc = "A massive machine that can either add or remove thermal energy from the surrounding environment. Must be secured onto a powered wire node to function."
	icon = 'icons/obj/machines/thermoregulator_vr.dmi'
	icon_state = "lasergen"
	density = TRUE
	anchored = FALSE

	use_power = USE_POWER_OFF //is powered directly from cables
	active_power_usage = 150 KILOWATTS  //BIG POWER
	idle_power_usage = 500

	circuit = /obj/item/circuitboard/thermoregulator
	maintenance_flags = MACHINE_MAINT_STANDARD

	var/on = 0
	var/target_temp = T20C
	var/mode = MODE_IDLE
	var/sleeping_mixture_id
	var/sleeping_mixture_revision = -1

/obj/machinery/power/thermoregulator/Initialize(mapload)
	. = ..()
	default_apply_parts()
	AddElement(/datum/element/climbable)

/obj/machinery/power/thermoregulator/Destroy()
	clear_gas_dependency()
	return ..()

/obj/machinery/power/thermoregulator/Moved(atom/old_loc, direction, forced = FALSE)
	. = ..()
	wake_for_state_change()

/obj/machinery/power/thermoregulator/examine(mob/user)
	. = ..()
	if(get_dist(user, src) <= 2)
		. += "There is a small display that reads \"[convert_k2c(target_temp)]C\"."

/obj/machinery/power/thermoregulator/screwdriver_act(mob/user, obj/item/tool)
	return ..()

/obj/machinery/power/thermoregulator/crowbar_act(mob/user, obj/item/tool)
	return ..()

/obj/machinery/power/thermoregulator/wrench_act(mob/user, obj/item/tool)
	anchored = !anchored
	visible_message(span_notice("\The [src] has been [anchored ? "bolted to the floor" : "unbolted from the floor"] by [user]."))
	playsound(src, tool.usesound, 75, 1)
	if(anchored)
		connect_to_network()
	else
		disconnect_from_network()
		turn_off()
	return ITEM_INTERACT_SUCCESS

/obj/machinery/power/thermoregulator/multitool_act(mob/user, obj/item/tool)
	var/new_temp = tgui_input_number(user, "Input a new target temperature, in degrees C.","Target Temperature", convert_k2c(target_temp), MAX_ATMOS_TEMPERATURE, convert_k2c(TCMB), round_value = FALSE)
	if(!Adjacent(user) || user.incapacitated())
		return ITEM_INTERACT_BLOCKING
	new_temp = convert_c2k(new_temp)
	target_temp = max(new_temp, TCMB)
	wake_for_state_change()
	return ITEM_INTERACT_SUCCESS

/obj/machinery/power/thermoregulator/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/ungated/thermoregulator_interact,
	)
	..()

/// Old attack_hand: `add_fingerprint(user); interact(user)`.
/datum/interaction/machine_hand/ungated/thermoregulator_interact
	id = "thermoregulator_interact"
	name = "Use"
	effect = /obj/machinery/power/thermoregulator/proc/interaction_use

/obj/machinery/power/thermoregulator/proc/interaction_use(mob/user, obj/item/held, datum/interaction/interaction)
	add_fingerprint(user)
	interact(user)
	return TRUE

/obj/machinery/power/thermoregulator/interact(mob/user)
	if(!anchored)
		return
	on = !on
	user.visible_message(span_notice("[user] [on ? "activates" : "deactivates"] \the [src]."),span_notice("You [on ? "activate" : "deactivate"] \the [src]."))
	if(!on)
		change_mode(MODE_IDLE)
	wake_for_state_change()
	update_icon()

/obj/machinery/power/thermoregulator/process()
	if(!on)
		return PROCESS_KILL
	if(!powernet)
		turn_off()
		return PROCESS_KILL

	if(draw_power(idle_power_usage) < idle_power_usage)
		visible_message(span_infoplain(span_bold("\The [src]") + " shuts down."))
		turn_off()
		return PROCESS_KILL

	var/datum/gas_mixture/env = loc.return_air()
	if(!env || abs(env.return_temperature() - target_temp) < 1)
		change_mode(MODE_IDLE)
		hibernate_until_temperature_changes()
		return PROCESS_KILL

	var/datum/gas_mixture/removed = env.remove_ratio(0.99)
	if(!removed)
		change_mode(MODE_IDLE)
		hibernate_until_temperature_changes()
		return PROCESS_KILL

	var/heat_transfer = removed.get_thermal_energy_change(target_temp)
	var/power_avail
	if(heat_transfer == 0) //just in case
		change_mode(MODE_IDLE)
	else if(heat_transfer > 0)
		change_mode(MODE_HEATING)
		power_avail = draw_power(min(heat_transfer, active_power_usage))
		removed.add_thermal_energy(min(power_avail*5,heat_transfer))
	else
		change_mode(MODE_COOLING)
		heat_transfer = abs(heat_transfer)
		var/cop = removed.return_temperature()/TN60C
		var/actual_heat_transfer = heat_transfer
		heat_transfer = min(heat_transfer, active_power_usage*cop)
		power_avail = draw_power(heat_transfer/cop)
		removed.add_thermal_energy(-min(power_avail*5*cop,actual_heat_transfer))
	env.merge(removed)

/obj/machinery/power/thermoregulator/update_icon()
	cut_overlays()
	if(on)
		add_overlay("lasergen-on")
		switch(mode)
			if(MODE_HEATING)
				add_overlay("lasergen-heat")
			if(MODE_COOLING)
				add_overlay("lasergen-cool")

/obj/machinery/power/thermoregulator/proc/turn_off()
	on = FALSE
	change_mode(MODE_IDLE)
	update_icon()

/obj/machinery/power/thermoregulator/proc/hibernate_until_temperature_changes()
	var/datum/weakref/WR = WEAKREF(src)
	var/datum/gas_mixture/environment = loc.return_air()
	sleeping_mixture_id = environment?.arena_id()
	sleeping_mixture_revision = environment?.revision() || -1
	SSmachines.sleeping_gas_devices[WR.reference] = WR
	SSmachines.subscribe_gas_dependency(sleeping_mixture_id, WR)
	STOP_MACHINE_PROCESSING(src)

/obj/machinery/power/thermoregulator/proc/clear_gas_dependency()
	var/datum/weakref/WR = WEAKREF(src)
	SSmachines.unsubscribe_gas_dependency(sleeping_mixture_id, WR)
	sleeping_mixture_id = null
	sleeping_mixture_revision = -1
	if(WR?.reference)
		SSmachines.sleeping_gas_devices.Remove(WR.reference)

/obj/machinery/power/thermoregulator/gas_dependency_changed(mixture_id, change_mask)
	if(!(change_mask & GAS_DEPENDENCY_TEMPERATURE) || mixture_id != sleeping_mixture_id || !on)
		return FALSE
	var/datum/gas_mixture/environment = loc.return_air()
	if(!environment || environment.arena_id() != sleeping_mixture_id)
		return TRUE
	if(environment.revision() == sleeping_mixture_revision)
		return FALSE
	return abs(environment.return_temperature() - target_temp) >= 1

/obj/machinery/power/thermoregulator/gas_dependency_interest_mask()
	return GAS_DEPENDENCY_TEMPERATURE

/obj/machinery/power/thermoregulator/proc/wake_for_state_change()
	clear_gas_dependency()
	START_MACHINE_PROCESSING(src)

/obj/machinery/power/thermoregulator/proc/change_mode(new_mode = MODE_IDLE)
	if(mode == new_mode)
		return
	mode = new_mode
	update_icon()

/obj/machinery/power/thermoregulator/emp_act(severity, recursive)
	. = ..()
	if (. & EMP_PROTECT_SELF)
		return
	if(!on)
		on = TRUE
	target_temp += rand(0, 1000)
	wake_for_state_change()
	update_icon()

/obj/machinery/power/thermoregulator/overload(obj/machinery/power/source)
	if(!anchored || !powernet)
		return
	var/power_avail = draw_power(active_power_usage*10)
	var/datum/gas_mixture/env = loc.return_air()
	if(env)
		var/datum/gas_mixture/removed = env.remove_ratio(0.99)
		if(removed)
			removed.add_thermal_energy(power_avail*5)
			env.merge(removed)
	var/turf/T = get_turf(src)
	new /obj/effect/decal/cleanable/liquid_fuel(T, 5)
	T.assume_gas(GAS_VOLATILE_FUEL, 5, T20C)
	T.hotspot_expose(700,400)
	var/datum/effect/effect/system/spark_spread/s = new
	s.set_up(5, 0, T)
	s.start()
	visible_message(span_warning("\The [src] bursts into flame!"))

#undef MODE_IDLE
#undef MODE_HEATING
#undef MODE_COOLING
