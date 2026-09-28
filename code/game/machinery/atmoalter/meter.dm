/obj/machinery/meter
	name = "meter"
	desc = "It measures something."
	icon = 'icons/obj/meter.dmi'
	icon_state = "meterX"
	var/target_handle
	var/list/pipes_on_turf
	anchored = TRUE
	power_channel = ENVIRON
	var/frequency = 0
	var/id
	var/open = FALSE
	use_power = USE_POWER_IDLE
	idle_power_usage = 15

/obj/machinery/meter/Initialize(mapload)
	. = ..()
	set_target(target_ref() || select_target())

/// Points the meter at `new_target`. The meter owns its lifetime watch on a
/// pipe target: when the pipe is destroyed the meter comes off as an item.
/obj/machinery/meter/proc/set_target(new_target)
	if(istype(target_ref(), /obj/machinery/atmospherics/pipe))
		UnregisterSignal(target_ref(), COMSIG_QDELETING)
	target_handle = om_handle(new_target)
	if(istype(target_ref(), /obj/machinery/atmospherics/pipe))
		RegisterSignal(target_ref(), COMSIG_QDELETING, PROC_REF(on_target_deleted))

/obj/machinery/meter/proc/on_target_deleted(datum/source)
	SIGNAL_HANDLER
	target_handle = null
	if(QDELETED(src))
		return
	var/obj/item/pipe_meter/PM = new /obj/item/pipe_meter(loc)
	transfer_fingerprints_to(PM)
	qdel(src)

/obj/machinery/meter/proc/select_target()
	var/obj/machinery/atmospherics/pipe/P
	for(P in loc)
		if(!P.hides_under_flooring())
			break
	if(!P)
		P = locate(/obj/machinery/atmospherics/pipe) in loc
	return P

/// A meter wakes only when what it shows or broadcasts would change: local meters when their
/// discrete needle sprite changes, radio meters when the sprite or the rounded kPa they send
/// changes (a value watch on current_display_signature()). Pressure noise below the display's
/// resolution never wakes it.
/obj/machinery/meter/proc/register_gas_dependency()
	var/datum/gas_mixture/environment = target_ref()?.return_air()
	om_watch_arm_value(src, "gas", environment?.arena_id(), GAS_DEPENDENCY_PRESSURE, CALLBACK(src, PROC_REF(current_display_signature)), wake_callback = CALLBACK(src, PROC_REF(wake_from_gas)))

/obj/machinery/meter/proc/current_display_signature()
	var/datum/gas_mixture/environment = target_ref()?.return_air()
	if(!frequency || !environment)
		return pressure_icon_state(environment)
	return "[pressure_icon_state(environment)]|[round(environment.return_pressure())]"

/obj/machinery/meter/proc/unregister_gas_dependency()
	om_watch_disarm(src, "gas")

/obj/machinery/meter/proc/wake_from_gas()
	unregister_gas_dependency()
	MACHINE_WAKE(src)

/obj/machinery/meter/proc/current_pressure_icon_state()
	return pressure_icon_state(target_ref()?.return_air())

/obj/machinery/meter/proc/pressure_icon_state(datum/gas_mixture/environment)
	if(!environment)
		return "meterX"
	var/env_pressure = environment.return_pressure()
	if(env_pressure <= 0.15 * ONE_ATMOSPHERE)
		return "meter0"
	if(env_pressure <= 1.8 * ONE_ATMOSPHERE)
		var/val = round(env_pressure / (ONE_ATMOSPHERE * 0.3) + 0.5)
		return "meter1_[val]"
	if(env_pressure <= 30 * ONE_ATMOSPHERE)
		var/val = round(env_pressure / (ONE_ATMOSPHERE * 5) - 0.35) + 1
		return "meter2_[val]"
	if(env_pressure <= 59 * ONE_ATMOSPHERE)
		var/val = round(env_pressure / (ONE_ATMOSPHERE * 5) - 6) + 1
		return "meter3_[val]"
	return "meter4"

/obj/machinery/meter/machine_step()
	if(!target_ref())
		icon_state = "meterX"
		return PROCESS_KILL

	if(stat & (BROKEN|NOPOWER))
		icon_state = "meter0"
		return PROCESS_KILL

	var/datum/gas_mixture/environment = target_ref().return_air()
	if(!environment)
		icon_state = "meterX"
		return PROCESS_KILL

	var/env_pressure = environment.return_pressure()
	icon_state = pressure_icon_state(environment)

	if(frequency)
		var/datum/radio_frequency/radio_connection = GLOB.radio_service.return_frequency(frequency)

		if(!radio_connection)
			register_gas_dependency()
			return PROCESS_KILL

		var/datum/signal/signal = new
		signal.source_handle = om_handle(src)
		signal.transmission_method = TRANSMISSION_RADIO
		signal.data = list(
			"tag" = id,
			"device" = "AM",
			"pressure" = round(env_pressure),
			"sigtype" = "status"
		)
		radio_connection.post_signal(src, signal)
	register_gas_dependency()
	return PROCESS_KILL

/obj/machinery/meter/examine(mob/user)
	. = ..()

	if(get_dist(user, src) > 3 && !(isAI(user) || isobserver(user)))
		. += span_warning("You are too far away to read it.")

	else if(stat & (NOPOWER|BROKEN))
		. += span_warning("The display is off.")

	else if(target_ref())
		var/datum/gas_mixture/environment = target_ref().return_air()
		if(environment)
			var/environment_temperature = environment.return_temperature()
			. += "The pressure gauge reads [round(environment.return_pressure(), 0.01)] kPa; [round(environment_temperature,0.01)]K ([round(environment_temperature-T0C,0.01)]&deg;C)"
		else
			. += "The sensor error light is blinking."
	else
		. += "The connect error light is blinking."

/obj/machinery/meter/Click()

	if(ishuman(usr) || isAI(usr)) // ghosts can call ..() for examine
		var/mob/living/L = usr
		if(!L.get_active_hand() || !L.Adjacent(src))
			usr.examinate(src)
			return 1

	return ..()

/obj/machinery/meter/wrench_act(mob/user, obj/item/tool)
	use_tool(user, tool, src, delay = 4 SECONDS, volume = 50, message_self = "You begin to unfasten \the [src]...", receiver = src, on_done = PROC_REF(wrench_act_tool_done), done_args = list(user))
	return ITEM_INTERACT_SUCCESS

/obj/machinery/meter/proc/wrench_act_tool_done(mob/user)
	user.visible_message(span_infoplain(span_bold("\The [user]") + " unfastens \the [src]."), span_notice("You have unfastened \the [src]."), "You hear ratchet.")
	replace_with(src, /obj/item/pipe_meter)

/obj/machinery/meter/screwdriver_act(mob/user, obj/item/tool)
	playsound(src, tool.usesound, 50, TRUE)
	to_chat(user, span_notice("You have [open ? "closed" : "opened"] the maintenance panel for [src]."))
	open = !open
	return ITEM_INTERACT_SUCCESS

/obj/machinery/meter/multitool_act(mob/user, obj/item/tool)
	if(open)
		om_prompt(src, user, list("kind" = "text", "message" = "Please insert an ID tag for [src], example 'exhaust_pipe'.", "title" = "Set ID Tag", "default" = id, "max_length" = MAX_NAME_LEN, "requires" = PROMPT_ADJACENT, "data" = list("tool" = tool)), PROC_REF(meter_id_entered))
		return ITEM_INTERACT_SUCCESS
	for(var/obj/machinery/atmospherics/pipe/pipe in loc)
		LAZYOR(pipes_on_turf, pipe)
	if(!length(pipes_on_turf))
		return ITEM_INTERACT_BLOCKING
	set_target(LAZYACCESS(pipes_on_turf, 1))
	LAZYREMOVE(pipes_on_turf, target_ref())
	LAZYADD(pipes_on_turf, target_ref())
	to_chat(user, span_notice("Pipe meter set to monitor \the [target_ref()]."))
	return ITEM_INTERACT_SUCCESS

/obj/machinery/meter/proc/meter_id_entered(mob/user, new_id, datum/om/prompt/ask)
	if(!open)
		return
	id = new_id
	var/obj/item/tool = ask.get("tool")
	var/obj/item/multitool/multitool = tool.get_multitool()
	if(multitool)
		multitool.connectable_handle = om_handle(src)
	return ITEM_INTERACT_SUCCESS

// TURF METER - REPORTS A TILE'S AIR CONTENTS

/obj/machinery/meter/turf/select_target()
	return loc

/obj/machinery/meter/turf/tool_interaction(mob/user, obj/item/tool, list/modifiers, secondary = FALSE)
	return ITEM_INTERACT_BLOCKING

/// Setup at spawn: arm what wakes it (machine_pipeline.dm, materialize_wakes()).
/obj/machinery/meter/arm_wakes()
	..()
	register_gas_dependency()

/// LC-refs: target -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/machinery/meter/proc/target_ref() as /obj/machinery/atmospherics/pipe
	return om_resolve(target_handle)
