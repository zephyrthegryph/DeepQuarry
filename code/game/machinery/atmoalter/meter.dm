/obj/machinery/meter
	name = "meter"
	desc = "It measures something."
	icon = 'icons/obj/meter.dmi'
	icon_state = "meterX"
	var/obj/machinery/atmospherics/pipe/target = null
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
	if (!target)
		target = select_target()

/obj/machinery/meter/Destroy()
	LAZYCLEARLIST(pipes_on_turf)
	target = null
	return ..()

/obj/machinery/meter/proc/select_target()
	var/obj/machinery/atmospherics/pipe/P
	for(P in loc)
		if(!P.hides_under_flooring())
			break
	if(!P)
		P = locate(/obj/machinery/atmospherics/pipe) in loc
	return P

/// Radio meters publish their numeric reading on every material pressure change (a revision
/// watch); local-only meters need wake only when their discrete needle sprite changes (a value
/// watch on pressure_icon_state()). Both paths are event-driven; neither needs a permanent
/// heartbeat.
/obj/machinery/meter/proc/register_gas_dependency()
	var/datum/gas_mixture/environment = target?.return_air()
	var/mixture_id = environment?.arena_id()
	var/datum/callback/wake = CALLBACK(src, PROC_REF(wake_from_gas))
	if(frequency)
		om_watch_arm_revision(src, "gas", mixture_id, GAS_DEPENDENCY_PRESSURE, wake_callback = wake, current_revision = environment?.revision())
	else
		om_watch_arm_value(src, "gas", mixture_id, GAS_DEPENDENCY_PRESSURE, CALLBACK(src, PROC_REF(current_pressure_icon_state)), wake_callback = wake)

/obj/machinery/meter/proc/unregister_gas_dependency()
	om_watch_disarm(src, "gas")

/obj/machinery/meter/proc/wake_from_gas()
	unregister_gas_dependency()
	START_MACHINE_PROCESSING(src)

/obj/machinery/meter/proc/current_pressure_icon_state()
	return pressure_icon_state(target?.return_air())

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

/obj/machinery/meter/process()
	if(!target)
		icon_state = "meterX"
		return PROCESS_KILL

	if(stat & (BROKEN|NOPOWER))
		icon_state = "meter0"
		return PROCESS_KILL

	var/datum/gas_mixture/environment = target.return_air()
	if(!environment)
		icon_state = "meterX"
		return PROCESS_KILL

	var/env_pressure = environment.return_pressure()
	icon_state = pressure_icon_state(environment)

	if(frequency)
		var/datum/radio_frequency/radio_connection = SSradio.return_frequency(frequency)

		if(!radio_connection)
			SSmachines.hibernate_meter(src)
			return PROCESS_KILL

		var/datum/signal/signal = new
		signal.source = src
		signal.transmission_method = TRANSMISSION_RADIO
		signal.data = list(
			"tag" = id,
			"device" = "AM",
			"pressure" = round(env_pressure),
			"sigtype" = "status"
		)
		radio_connection.post_signal(src, signal)
	SSmachines.hibernate_meter(src)
	return PROCESS_KILL

/obj/machinery/meter/examine(mob/user)
	. = ..()

	if(get_dist(user, src) > 3 && !(isAI(user) || isobserver(user)))
		. += span_warning("You are too far away to read it.")

	else if(stat & (NOPOWER|BROKEN))
		. += span_warning("The display is off.")

	else if(target)
		var/datum/gas_mixture/environment = target.return_air()
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
	if(use_tool(user, tool, src, delay = 4 SECONDS, volume = 50, message_self = "You begin to unfasten \the [src]..."))
		user.visible_message(span_infoplain(span_bold("\The [user]") + " unfastens \the [src]."), span_notice("You have unfastened \the [src]."), "You hear ratchet.")
		new /obj/item/pipe_meter(get_turf(src))
		qdel(src)
	return ITEM_INTERACT_SUCCESS

/obj/machinery/meter/screwdriver_act(mob/user, obj/item/tool)
	playsound(src, tool.usesound, 50, TRUE)
	to_chat(user, span_notice("You have [open ? "closed" : "opened"] the maintenance panel for [src]."))
	open = !open
	return ITEM_INTERACT_SUCCESS

/obj/machinery/meter/multitool_act(mob/user, obj/item/tool)
	if(open)
		id = tgui_input_text(user, "Please insert an ID tag for [src], example 'exhaust_pipe'.", "Set ID Tag", id, MAX_NAME_LEN)
		var/obj/item/multitool/multitool = tool.get_multitool()
		if(multitool)
			multitool.connectable = src
		return ITEM_INTERACT_SUCCESS
	for(var/obj/machinery/atmospherics/pipe/pipe in loc)
		LAZYOR(pipes_on_turf, pipe)
	if(!length(pipes_on_turf))
		return ITEM_INTERACT_BLOCKING
	target = LAZYACCESS(pipes_on_turf, 1)
	LAZYREMOVE(pipes_on_turf, target)
	LAZYADD(pipes_on_turf, target)
	to_chat(user, span_notice("Pipe meter set to monitor \the [target]."))
	return ITEM_INTERACT_SUCCESS

// TURF METER - REPORTS A TILE'S AIR CONTENTS

/obj/machinery/meter/turf/select_target()
	return loc

/obj/machinery/meter/turf/tool_interaction(mob/user, obj/item/tool, list/modifiers, secondary = FALSE)
	return ITEM_INTERACT_BLOCKING
