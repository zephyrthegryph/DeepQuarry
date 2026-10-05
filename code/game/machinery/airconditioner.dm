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
	set_anchored(!anchored)
	act_message(src, user, others = span_notice("%U% has been [anchored ? "bolted to the floor" : "unbolted from the floor"] by %T%.")) //Does this not need to be disabled?
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

/// Powered straight from its cables with no metering: the pump works while it is on a network.
/obj/machinery/power/thermoregulator/southerncross/machine_step()
	if(!power_region)
		turn_off()
		return PROCESS_KILL
	set_pumping(TRUE)
	update_pump_mode()

// Given the power behind this thermodynamics defying machine, nerfing EMP effectiveness.
/obj/machinery/power/thermoregulator/southerncross/thermoregulator_emp(datum/act/hit/emp/A)
	if(!on)
		set_on(1)
	target_temp += rand(0, 20)
	heat_entries_refresh(src)
	wake_for_state_change()
	update_icon()
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

DECLARE_PERIODIC_WHILE(/obj/machinery/power/thermoregulator, MACHINE_PIPELINE, "on")
TRACKED(/obj/machinery/power/thermoregulator, pumping)

CAPABILITIES(/obj/machinery/power/thermoregulator)
	climb()
	// A heat pump on the room's air toward the target, against the station's heat-rejection loop at 20 C: a Carnot-bounded COP both
	// ways (heating draws on the loop, cooling rejects into it). Its work is paid from the grid (machine_step()).
	when(nameof(pumping), heat_pump(HEAT_AIR, HEAT_AMBIENT, nameof(heat_pump_watts), nameof(target_temp), HEAT_PUMP_BOTH, FALSE, nameof(regulator_carnot_fraction), nameof(regulator_max_cop)))
	extend(/datum/act/hit/emp, instead(then(PROC_REF(thermoregulator_emp))))

/obj/machinery/power/thermoregulator/Initialize(mapload)
	. = ..()
	default_apply_parts()

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
	set_anchored(!anchored)
	act_message(src, user, others = span_notice("%U% has been [anchored ? "bolted to the floor" : "unbolted from the floor"] by %T%."))
	playsound(src, tool.usesound, 75, 1)
	if(anchored)
		connect_to_network()
	else
		disconnect_from_network()
		turn_off()
	return ITEM_INTERACT_SUCCESS

/obj/machinery/power/thermoregulator/multitool_act(mob/user, obj/item/tool)
	open_request(src, /datum/prompt/number, PROC_REF(target_temperature_entered), answerer = user, default = convert_k2c(target_temp), min_value = convert_k2c(TCMB), title = "Target Temperature", question = "Input a new target temperature, in degrees C.", max_value = MAX_ATMOS_TEMPERATURE, ask_flags = ASK_ADJACENT | ASK_CAPABLE, timeout = 0)
	return ITEM_INTERACT_SUCCESS

/obj/machinery/power/thermoregulator/proc/target_temperature_entered(datum/act/request/A)
	if(!A.answer)
		return
	var/new_temp = convert_c2k(A.answer.answer_value)
	target_temp = max(new_temp, TCMB)
	heat_entries_refresh(src)
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
	set_on(!on)
	act_message(user, src, MSG_SELF(span_notice("You [on ? "activate" : "deactivate"] %T%.")), \
		MSG_OTHERS(span_notice("%U% [on ? "activates" : "deactivates"] %T%.")))
	if(!on)
		change_mode(MODE_IDLE)
		set_pumping(FALSE)
	wake_for_state_change()
	update_icon()

/// The heat pump (its CAPABILITIES entry) works the air in Rust; the step pays its work from the grid and shows what it does. It
/// sleeps within a degree of its target, where the pump has nothing to move.
/obj/machinery/power/thermoregulator/machine_step()
	if(!power_region)
		turn_off()
		return PROCESS_KILL

	if(draw_power(idle_power_usage) < idle_power_usage)
		visible_message(span_infoplain(span_bold("\The [src]") + " shuts down."))
		turn_off()
		return PROCESS_KILL

	var/work = -heat_entries_power(src)
	if(work > 0 && draw_power(work) < work * 0.99)
		visible_message(span_infoplain(span_bold("\The [src]") + " shuts down."))
		turn_off()
		return PROCESS_KILL
	set_pumping(TRUE)
	if(update_pump_mode() == MODE_IDLE)
		hibernate_until_temperature_changes()
		return PROCESS_KILL

/// Shows whether the room is being heated or cooled. Returns the mode.
/obj/machinery/power/thermoregulator/proc/update_pump_mode()
	var/datum/gas_mixture/env = loc?.return_air()
	var/gap = env ? target_temp - env.return_temperature() : 0
	if(abs(gap) < 1)
		change_mode(MODE_IDLE)
	else
		change_mode(gap > 0 ? MODE_HEATING : MODE_COOLING)
	return mode

/obj/machinery/power/thermoregulator/proc/appearance_mode()
	if(!on)
		return "off"
	switch(mode)
		if(MODE_HEATING)
			return "heat"
		if(MODE_COOLING)
			return "cool"
	return "idle"

DECLARE_APPEARANCE(/obj/machinery/power/thermoregulator, "appearance_mode", list(
	"idle" = list(APPEARANCE_OVERLAYS = list("lasergen-on")),
	"heat" = list(APPEARANCE_OVERLAYS = list("lasergen-on", "lasergen-heat")),
	"cool" = list(APPEARANCE_OVERLAYS = list("lasergen-on", "lasergen-cool"))
))

/obj/machinery/power/thermoregulator/proc/turn_off()
	set_on(FALSE)
	set_pumping(FALSE)
	change_mode(MODE_IDLE)
	update_icon()

/// Wakes only once the room drifts at least a degree from its target while it is on -- the test
/// process() makes before regulating.
/obj/machinery/power/thermoregulator/proc/hibernate_until_temperature_changes()
	var/datum/gas_mixture/environment = loc.return_air()
	om_watch_arm_condition(src, "gas", list(environment?.arena_id()), GAS_DEPENDENCY_TEMPERATURE, om_callable(src, PROC_REF(gas_wake_condition)), wake_callback = om_callable(src, PROC_REF(wake_for_state_change)))
	// Every machine_step() caller returns PROCESS_KILL right after; while off the declaration keeps it parked.

/obj/machinery/power/thermoregulator/proc/gas_wake_condition()
	var/datum/gas_mixture/environment = loc?.return_air()
	return on && environment && abs(environment.return_temperature() - target_temp) >= 1

/obj/machinery/power/thermoregulator/proc/clear_gas_dependency()
	om_watch_disarm(src, "gas")

/obj/machinery/power/thermoregulator/proc/wake_for_state_change()
	clear_gas_dependency()
	MACHINE_WAKE(src)

/obj/machinery/power/thermoregulator/proc/change_mode(new_mode = MODE_IDLE)
	if(mode == new_mode)
		return
	set_mode(new_mode)

/// An EMP switches the regulator on and scrambles its target temperature (before the hit lands; the hit goes on).
/obj/machinery/power/thermoregulator/proc/thermoregulator_emp(datum/act/hit/emp/A)
	if(!on)
		set_on(TRUE)
	target_temp += rand(0, 1000)
	heat_entries_refresh(src)
	wake_for_state_change()
	update_icon()
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

/obj/machinery/power/thermoregulator/step_has_work()
	return gas_wake_condition()

/// Setup at spawn: arm what wakes it (machine_pipeline.dm, materialize_wakes()).
/obj/machinery/power/thermoregulator/arm_wakes()
	..()
	hibernate_until_temperature_changes()
