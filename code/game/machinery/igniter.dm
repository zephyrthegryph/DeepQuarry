/obj/machinery/igniter
	name = "igniter"
	desc = "It's useful for igniting flammable items."
	icon = 'icons/obj/stationobjs.dmi'
	icon_state = "igniter1"
	var/id = null
	var/on = 1.0
	anchored = TRUE
	use_power = USE_POWER_IDLE
	idle_power_usage = 2
	active_power_usage = 4

/obj/machinery/igniter/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/igniter_toggle,
	)
	..()

/datum/interaction/machine_hand/igniter_toggle
	id = "igniter_toggle"
	name = "Toggle"
	category = INTERACTION_CAT_TOGGLE
	effect = /obj/machinery/igniter/proc/interaction_toggle

/obj/machinery/igniter/proc/interaction_toggle(mob/user, obj/item/held, datum/interaction/interaction)
	add_fingerprint(user)
	use_power(50)
	on = !(on)
	icon_state = text("igniter[]", on)
	return TRUE

/obj/machinery/igniter/process()	//ugh why is this even in process()?
	if(on && !(stat & NOPOWER))
		var/turf/location = src.loc
		if(isturf(location))
			location.hotspot_expose(1000,500,1)
	return 1

/obj/machinery/igniter/Initialize(mapload)
	icon_state = "igniter[on]"
	. = ..()

/obj/machinery/igniter/power_change()
	..()
	if(!(stat & NOPOWER))
		icon_state = "igniter[on]"
	else
		icon_state = "igniter0"

// Wall mounted remote-control igniter.

/obj/machinery/sparker
	name = "Mounted igniter"
	desc = "A wall-mounted ignition device."
	icon = 'icons/obj/stationobjs.dmi'
	icon_state = "migniter"
	layer = ABOVE_WINDOW_LAYER
	var/id = null
	var/disable = 0
	var/last_spark = 0
	var/base_state = "migniter"
	anchored = TRUE
	use_power = USE_POWER_IDLE
	idle_power_usage = 2
	active_power_usage = 4

/obj/machinery/sparker/power_change()
	..()
	if(!(stat & NOPOWER) && disable == 0)

		icon_state = "[base_state]"
//		sd_SetLuminosity(2)
	else
		icon_state = "[base_state]-p"
//		sd_SetLuminosity(0)

/obj/machinery/sparker/screwdriver_act(mob/user, obj/item/tool)
	add_fingerprint(user)
	disable = !disable
	playsound(src, tool.usesound, 50, TRUE)
	if(disable)
		user.visible_message(span_warning("[user] has disabled the [src]!"), span_warning("You disable the connection to the [src]."))
		icon_state = "[base_state]-d"
	else
		user.visible_message(span_warning("[user] has reconnected the [src]!"), span_warning("You fix the connection to the [src]."))
		icon_state = powered() ? "[base_state]" : "[base_state]-p"
	return ITEM_INTERACT_SUCCESS

/obj/machinery/sparker/attack_ai()
	if(anchored)
		return ignite()
	else
		return

/obj/machinery/sparker/proc/ignite()
	if(!(powered()))
		return

	if((disable) || (last_spark && world.time < last_spark + 50))
		return

	flick("[base_state]-spark", src)
	var/datum/effect/effect/system/spark_spread/s = new /datum/effect/effect/system/spark_spread
	s.set_up(2, 1, src)
	s.start()
	last_spark = world.time
	use_power(1000)
	var/turf/location = src.loc
	if(isturf(location))
		location.hotspot_expose(1000,500,1)
	return 1

/obj/machinery/sparker/emp_act(severity, recursive)
	if(stat & (BROKEN|NOPOWER))
		..(severity, recursive)
		return
	ignite()
	..(severity, recursive)

/obj/machinery/button/ignition
	name = "ignition switch"
	desc = "A remote control switch for a mounted igniter."

/obj/machinery/button/ignition/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/ignition_button_trigger,
	)
	..()

/datum/interaction/machine_hand/ignition_button_trigger
	id = "ignition_button_trigger"
	name = "Trigger"
	category = INTERACTION_CAT_TOGGLE
	effect = /obj/machinery/button/ignition/proc/interaction_trigger

/obj/machinery/button/ignition/proc/interaction_trigger(mob/user, obj/item/held, datum/interaction/interaction)
	use_power(5)

	if(active)
		return TRUE

	active = TRUE
	icon_state = "launcheract"

	for(var/obj/machinery/sparker/M in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		if(M.id == id)
			INVOKE_ASYNC(M, TYPE_PROC_REF(/obj/machinery/sparker, ignite))

	for(var/obj/machinery/igniter/M in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		if(M.id == id)
			use_power(50)
			M.on = !(M.on)
			M.icon_state = text("igniter[]", M.on)

	addtimer(CALLBACK(src, PROC_REF(finish_trigger)), 5 SECONDS, TIMER_DELETE_ME|TIMER_UNIQUE)
	return TRUE

/obj/machinery/button/ignition/proc/finish_trigger()
	PRIVATE_PROC(TRUE)

	icon_state = "launcherbtt"
	active = FALSE
