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

/// Powered straight from its cables with no metering: the pump works while it is on a network.
/obj/machinery/power/thermoregulator/southerncross/regulator_step(datum/act/A)
	if(!power_region)
		turn_off()
		return
	set_pumping(TRUE)
	update_pump_mode()
	reconsider()

// Given the power behind this thermodynamics defying machine, nerfing EMP effectiveness.
/obj/machinery/power/thermoregulator/southerncross/thermoregulator_emp(datum/act/hit/emp/A)
	if(!on)
		set_on(1)
	set_target_temp(target_temp + rand(0, 20))
	heat_entries_refresh(src)
	return ..()

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

	on = 0
	var/target_temp = T20C
	mode = MODE_IDLE
	/// Fraction of the Carnot COP this unit's pump achieves (H4, the
	/// generic vg_heat_regulator_step -- rust_core.md §15's "the heat
	/// regulator" row). Was a bespoke `removed.return_temperature()/TN60C`
	/// formula per subtype; the real Carnot-bounded model lives once in
	/// Rust now.
	var/regulator_carnot_fraction = 0.4
	/// Upper bound on the pump's COP (a pump across a tiny gap is not free).
	var/regulator_max_cop = 25
	/// The heat pump's electrical rating, W.
	var/heat_pump_watts = 150 KILOWATTS
	/// TRUE while it works the room's air: its heat pump exists exactly while this is set.
	var/pumping = FALSE

	/// It has work each service interval: on, on the grid, and the room a degree or more off its target (reconsider()).
	var/regulating = FALSE

TRACKED(/obj/machinery/power/thermoregulator, pumping)
TRACKED(/obj/machinery/power/thermoregulator, regulating)
TRACKED(/obj/machinery/power/thermoregulator, target_temp)

MSG_DEF(thermoregulator/bolted, "You bolt %T% to the floor.", "%U% bolts %T% to the floor.")
MSG_DEF(thermoregulator/unbolted, "You unbolt %T% from the floor.", "%U% unbolts %T% from the floor.")
MSG_DEF(thermoregulator/activated, "You activate %T%.", "%U% activates %T%.")
MSG_DEF(thermoregulator/deactivated, "You deactivate %T%.", "%U% deactivates %T%.")
MSG_DEF_SELF(thermoregulator/loose, "It must be bolted down first.")

CAPABILITIES(/obj/machinery/power/thermoregulator)
	climb()
	// A heat pump on the room's air toward the target, against the station's heat-rejection loop at 20 C: a Carnot-bounded COP both
	// ways (heating draws on the loop, cooling rejects into it). Its work is paid from the grid (regulator_step()).
	when(nameof(pumping), heat_pump(HEAT_AIR, HEAT_AMBIENT, nameof(heat_pump_watts), nameof(target_temp), HEAT_PUMP_BOTH, FALSE, nameof(regulator_carnot_fraction), nameof(regulator_max_cop)))
	extend(/datum/act/hit/emp, instead(then(PROC_REF(thermoregulator_emp))))
	gas_watch(changed = PROC_REF(room_changed), mask = GAS_DEPENDENCY_TEMPERATURE)
	every(MACHINE_SERVICE_INTERVAL, then(PROC_REF(regulator_step)), when = nameof(regulating))
	on_change(nameof(on), ANY, then(PROC_REF(reconsider)))
	on_change(nameof(target_temp), ANY, then(PROC_REF(reconsider)))
	examine_line(PROC_REF(display_text))
	op("switch", hand(), label("Use"), wait(0), when(cond_not(req(/obj/item))), needs(req_bool(PROC_REF(bolted), because = MSG(thermoregulator/loose))),
		says(PROC_REF(switch_message)), then(PROC_REF(switched)))
	op("anchor", tool(TOOL_WRENCH), label("Wrench"), wait(0), says(PROC_REF(anchor_message)), then(PROC_REF(anchor_toggled)))
	op("set_target", tool(TOOL_MULTITOOL), label("Set target temperature"), wait(0),
		asks(/datum/prompt/number, fields = list("title" = "Target Temperature", "question" = "Input a new target temperature, in degrees C.", "default" = computed(PROC_REF(target_celsius)), "min_value" = computed(PROC_REF(lowest_celsius)), "max_value" = MAX_ATMOS_TEMPERATURE, "timeout" = 0)),
		then(PROC_REF(target_set)))
	default_parts()

/obj/machinery/power/thermoregulator/Moved(atom/old_loc, direction, forced = FALSE)
	. = ..()
	reconsider()

/obj/machinery/power/thermoregulator/proc/display_text(datum/act/eval/A)
	var/mob/user = A.actor
	if(user && get_dist(user, src) <= 2)
		return "There is a small display that reads \"[convert_k2c(target_temp)]C\"."

// ---- the controls ----

/obj/machinery/power/thermoregulator/proc/bolted(datum/act/A)
	return anchored

/obj/machinery/power/thermoregulator/proc/switch_message(datum/act/A)
	return on ? /datum/msg/thermoregulator/activated : /datum/msg/thermoregulator/deactivated

/obj/machinery/power/thermoregulator/proc/switched(datum/act/op/A)
	set_on(!on)
	if(!on)
		change_mode(MODE_IDLE)
		set_pumping(FALSE)
	return OP_OK

/obj/machinery/power/thermoregulator/proc/anchor_message(datum/act/A)
	return anchored ? /datum/msg/thermoregulator/bolted : /datum/msg/thermoregulator/unbolted

/// The wrench bolts it onto its wire node, or frees it (switching it off).
/obj/machinery/power/thermoregulator/proc/anchor_toggled(datum/act/op/A)
	set_anchored(!anchored)
	if(anchored)
		connect_to_network()
	else
		disconnect_from_network()
		turn_off()
	reconsider()
	return OP_OK

/obj/machinery/power/thermoregulator/proc/target_celsius(datum/act/A)
	return convert_k2c(target_temp)

/obj/machinery/power/thermoregulator/proc/lowest_celsius(datum/act/A)
	return convert_k2c(TCMB)

/// The multitool's answer, in degrees C, is its new target.
/obj/machinery/power/thermoregulator/proc/target_set(datum/act/op/A)
	var/datum/prompt/number/answer = A.answer
	set_target_temp(max(convert_c2k(answer.value), TCMB))
	heat_entries_refresh(src)
	return OP_OK

// ---- its work: woken by its room's temperature, its switch and its target; nothing polls ----

/// The room's air changed temperature (its gas watch).
/obj/machinery/power/thermoregulator/proc/room_changed(list/observation, index)
	reconsider()

/// Whether it has work: on, on the grid, and the room a degree or more off its target. Idle, its pump shows idle.
/obj/machinery/power/thermoregulator/proc/reconsider(datum/act/A)
	set_regulating(!!(on && anchored && power_region && gas_wake_condition()))
	if(on && !regulating)
		change_mode(MODE_IDLE)

/// One service interval of regulating (its every()): the heat pump (its CAPABILITIES entry) works the air in Rust; this pays its work from the
/// grid and shows what it does.
/obj/machinery/power/thermoregulator/proc/regulator_step(datum/act/A)
	if(!power_region)
		turn_off()
		return
	if(draw_power(idle_power_usage) < idle_power_usage)
		visible_message(span_infoplain(span_bold("\The [src]") + " shuts down."))
		turn_off()
		return
	var/work = -heat_entries_power(src)
	if(work > 0 && draw_power(work) < work * 0.99)
		visible_message(span_infoplain(span_bold("\The [src]") + " shuts down."))
		turn_off()
		return
	set_pumping(TRUE)
	update_pump_mode()
	reconsider()

/// Shows whether the room is being heated or cooled. Returns the mode.
/obj/machinery/power/thermoregulator/proc/update_pump_mode()
	var/datum/gas_mixture/env = loc?.return_air()
	var/gap = env ? target_temp - env.return_temperature() : 0
	if(abs(gap) < 1)
		change_mode(MODE_IDLE)
	else
		change_mode(gap > 0 ? MODE_HEATING : MODE_COOLING)
	return mode

/obj/machinery/power/thermoregulator/draw(datum/look/look)
	..()
	if(!on)
		return
	look.overlay("lasergen-on")
	look.overlay("lasergen-heat", when = mode == MODE_HEATING)
	look.overlay("lasergen-cool", when = mode == MODE_COOLING)

/obj/machinery/power/thermoregulator/proc/turn_off()
	set_on(FALSE)
	set_pumping(FALSE)
	change_mode(MODE_IDLE)

/// The room is a degree or more off its target.
/obj/machinery/power/thermoregulator/proc/gas_wake_condition()
	var/datum/gas_mixture/environment = loc?.return_air()
	return environment && abs(environment.return_temperature() - target_temp) >= 1

/obj/machinery/power/thermoregulator/proc/change_mode(new_mode = MODE_IDLE)
	if(mode == new_mode)
		return
	set_mode(new_mode)

/// An EMP switches the regulator on and scrambles its target temperature (before the hit lands; the hit goes on).
/obj/machinery/power/thermoregulator/proc/thermoregulator_emp(datum/act/hit/emp/A)
	if(!on)
		set_on(TRUE)
	set_target_temp(target_temp + rand(0, 1000))
	heat_entries_refresh(src)
	return HOOK_DECLINE

/obj/machinery/power/thermoregulator/overload(obj/machinery/power/source)
	if(!anchored || !power_region)
		return
	var/power_avail = draw_power(active_power_usage*10)
	// The surge burns through its coils: what it drew becomes heat in the room, one for one.
	heat_add(loc.return_air(), power_avail, HEAT_SOURCE_DEVICE)
	var/turf/T = get_turf(src)
	new /obj/effect/decal/cleanable/liquid_fuel(T, 5)
	T.assume_gas(GAS_VOLATILE_FUEL, 5, T20C)
	T.hotspot_expose(700,400)
	fx_sparks(T, 5, FALSE)
	visible_message(span_warning("\The [src] bursts into flame!"))

#undef MODE_IDLE
#undef MODE_HEATING
#undef MODE_COOLING
