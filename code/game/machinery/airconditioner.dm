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

	apply_regulator_step(removed, active_power_usage*1000)
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
	/// Fraction of the Carnot COP this unit's pump achieves (H4, the
	/// generic vg_heat_regulator_step -- rust_core.md §15's "the heat
	/// regulator" row). Was a bespoke `removed.return_temperature()/TN60C`
	/// formula per subtype; the real Carnot-bounded model lives once in
	/// Rust now.
	var/regulator_carnot_fraction = 0.4
	/// Upper bound on the pump's COP (a pump across a tiny gap is not free).
	var/regulator_max_cop = 25

/// One vg_heat_regulator_step() call against `removed`'s current heat
/// capacity/temperature, applied with add_thermal_energy(). `watts` is the
/// electrical work budget for this call (one process() tick is treated as
/// one second, matching every caller's existing per-tick power constants);
/// heating is resistive (1:1, matching every caller's old heating branch
/// exactly); cooling rejects to an infinite reservoir (the old code never
/// applied the rejected/absorbed heat to any other side either -- see H4's
/// note in temperature.md). Sets `mode` and returns it.
/obj/machinery/power/thermoregulator/proc/apply_regulator_step(datum/gas_mixture/removed, watts)
	var/capacity = removed.heat_capacity()
	if(!removed || capacity <= 0)
		change_mode(MODE_IDLE)
		return mode
	// The "other" side is an infinite reservoir at station-ambient
	// temperature (there is no specific hull/space hookup here -- the old
	// code never applied the rejected/absorbed heat to any other side
	// either). Only cooling's Carnot lift (Th - Tc) reads this; T20C keeps
	// that lift physically sane instead of the wildly-wrong TCMB a
	// space-side default would give.
	var/list/step = vg_heat_regulator_step(
		target_temp, watts, REGULATOR_MODE_BOTH,
		regulator_carnot_fraction, regulator_max_cop, TRUE, 1,
		capacity, removed.return_temperature(),
		-1, T20C,
		1,
	)
	var/moved = step[2]
	if(moved > 0)
		change_mode(MODE_HEATING)
	else if(moved < 0)
		change_mode(MODE_COOLING)
	else
		change_mode(MODE_IDLE)
		return mode
	removed.add_thermal_energy(moved)
	return mode

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
		// H4: the Carnot-bounded COP formula lives once in Rust now
		// (rust_core.md §15's "the heat regulator" row) instead of this
		// unit's own `removed.return_temperature()/TN60C` approximation;
		// "other" (the hot side rejected heat goes to) is treated as
		// station-ambient, same reasoning as apply_regulator_step's.
		var/cop = vg_heat_regulator_cooling_cop(removed.return_temperature(), T20C, regulator_carnot_fraction, regulator_max_cop)
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
	var/datum/gas_mixture/environment = loc.return_air()
	om_watch_arm_revision(src, "gas", environment?.arena_id(), GAS_DEPENDENCY_TEMPERATURE, wake_callback = CALLBACK(src, PROC_REF(wake_for_state_change)), current_revision = environment?.revision())
	STOP_MACHINE_PROCESSING(src)

/obj/machinery/power/thermoregulator/proc/clear_gas_dependency()
	om_watch_disarm(src, "gas")

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
