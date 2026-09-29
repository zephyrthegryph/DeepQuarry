/obj/machinery/igniter
	name = "igniter"
	desc = "It's useful for igniting flammable items."
	icon = 'icons/obj/stationobjs.dmi'
	icon_state = "igniter1"
	var/id = null
	on = 1.0
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
	set_on(!(on))
	icon_state = text("igniter[]", on)
	if(on)
		MACHINE_WAKE(src)
	return TRUE

/// Keeps its tile ignited every machine frame while on; off, it sleeps until toggled on, and
/// unpowered until power returns.
/obj/machinery/igniter/machine_step()
	if(!on)
		return PROCESS_KILL
	if(has_stat(NOPOWER))
		return sleep_until_powered()
	var/turf/location = src.loc
	if(isturf(location))
		location.hotspot_expose(1000,500,1)

DECLARE_APPEARANCE(/obj/machinery/igniter, "on", list("0" = list(APPEARANCE_ICON_STATE = "igniter0"), "1" = list(APPEARANCE_ICON_STATE = "igniter1")))

/obj/machinery/igniter/power_change()
	. = ..()
	if(!has_stat(NOPOWER))
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
	COOLDOWN_DECLARE(spark_cooldown)
	var/base_state = "migniter"
	anchored = TRUE
	use_power = USE_POWER_IDLE
	idle_power_usage = 2
	active_power_usage = 4

/obj/machinery/sparker/power_change()
	. = ..()
	if(!has_stat(NOPOWER) && disable == 0)

		icon_state = "[base_state]"
	else
		icon_state = "[base_state]-p"

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

EXTEND_INTERACTIONS(/obj/machinery/sparker, INTERACT_SILICON("Ignite", PROC_REF(sparker_silicon_trigger)))

/// Old attack_ai: the AI triggers it directly while it is anchored.
/obj/machinery/sparker/proc/sparker_silicon_trigger(mob/user, obj/item/held, datum/interaction/interaction)
	if(anchored)
		ignite()
	return TRUE

/obj/machinery/sparker/proc/ignite()
	if(!(powered()))
		return

	if((disable) || !COOLDOWN_FINISHED(src, spark_cooldown))
		return

	flick("[base_state]-spark", src)
	var/datum/effect/effect/system/spark_spread/s = new /datum/effect/effect/system/spark_spread
	s.set_up(2, 1, src)
	s.start()
	COOLDOWN_START(src, spark_cooldown, 5 SECONDS)
	use_power(1000)
	var/turf/location = src.loc
	if(isturf(location))
		location.hotspot_expose(1000,500,1)
	return 1

/obj/machinery/sparker/emp_act(severity, recursive)
	if(!operable())
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

	set_active(TRUE)
	icon_state = "launcheract"

	for(var/obj/machinery/sparker/M in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		if(M.id == id)
			M.ignite()

	for(var/obj/machinery/igniter/M in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		if(M.id == id)
			use_power(50)
			M.set_on(!(M.on))
			M.icon_state = text("igniter[]", M.on)

	om_after_unique(src, 5 SECONDS, PROC_REF(finish_trigger))
	return TRUE

/obj/machinery/button/ignition/proc/finish_trigger()
	PRIVATE_PROC(TRUE)

	icon_state = "launcherbtt"
	set_active(FALSE)


/// Its declared start condition (machine_pipeline.dm, materialize_wakes()).
/obj/machinery/igniter/step_start_condition()
	return on
