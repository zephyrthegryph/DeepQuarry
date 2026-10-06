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

/obj/machinery/igniter/proc/interaction_toggle(datum/act/op/A)
	var/mob/user = A.actor
	add_fingerprint(user)
	use_power(50)
	set_on(!(on))
	icon_state = text("igniter[]", on)
	return TRUE

/// Keeps its tile ignited every machine frame while on; off, it sleeps until toggled on, and
/// unpowered until power returns.
// Its periodic work: work_step() while it is started (code/library/machine/started_work.dm).
CAPABILITIES(/obj/machinery/igniter)
	started_work(step = PROC_REF(work_step), starts = TRUE, when = nameof(on), wakes_on = list(nameof(on)))
	op("toggle", hand(), priority(OP_PRIORITY_DEFAULT - 1), label("Toggle"), then(PROC_REF(interaction_toggle)))

/obj/machinery/igniter/proc/work_step(datum/act/timer/A)
	if(has_stat(NOPOWER))
		return work_wait_for_power(src)
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

/obj/machinery/sparker/proc/screwdriver_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/tool = A.held
	add_fingerprint(user)
	disable = !disable
	playsound(src, tool.usesound, 50, TRUE)
	if(disable)
		act_message(user, src, MSG_SELF(span_warning("You disable the connection to %T%.")), MSG_OTHERS(span_warning("%U% has disabled %T%!")))
		icon_state = "[base_state]-d"
	else
		act_message(user, src, MSG_SELF(span_warning("You fix the connection to %T%.")), MSG_OTHERS(span_warning("%U% has reconnected %T%!")))
		icon_state = powered() ? "[base_state]" : "[base_state]-p"
	return OP_OK

/// Old attack_ai: the AI triggers it directly while it is anchored.
/obj/machinery/sparker/proc/sparker_silicon_trigger(datum/act/op/A)
	if(anchored)
		ignite()
	return TRUE

/obj/machinery/sparker/proc/ignite()
	if(!(powered()))
		return

	if((disable) || !COOLDOWN_FINISHED(src, spark_cooldown))
		return

	flick("[base_state]-spark", src)
	fx_sparks(src, 2)
	COOLDOWN_START(src, spark_cooldown, 5 SECONDS)
	use_power(1000)
	var/turf/location = src.loc
	if(isturf(location))
		location.hotspot_expose(1000,500,1)
	return 1

CAPABILITIES(/obj/machinery/sparker)
	extend(/datum/act/hit/emp, instead(then(PROC_REF(sparker_emp))))
	op("use_screwdriver", tool(TOOL_SCREWDRIVER), priority(OP_PRIORITY_DEFAULT - 1), wait(0), then(PROC_REF(screwdriver_used)))
	op("sparker_silicon_trigger", remote(), priority(OP_PRIORITY_DEFAULT - 1), label("Ignite"), then(PROC_REF(sparker_silicon_trigger)))

/// An EMP makes a working sparker spark.
/obj/machinery/sparker/proc/sparker_emp(datum/act/hit/emp/A)
	if(!operable())
		return HOOK_DECLINE
	ignite()
	return HOOK_DECLINE

/obj/machinery/button/ignition
	name = "ignition switch"
	desc = "A remote control switch for a mounted igniter."

CAPABILITIES(/obj/machinery/button/ignition)
	op("trigger", hand(), priority(OP_PRIORITY_DEFAULT - 1), label("Trigger"), then(PROC_REF(interaction_trigger)))

/// Sparkers and igniters sharing our id (keyed).
/obj/machinery/button/ignition/var/list/obj/machinery/sparker/controlled_sparkers
/obj/machinery/button/ignition/var/list/obj/machinery/igniter/controlled_igniters
/obj/machinery/button/ignition/relations()
	. = ..()
	. += rel_many(nameof(controlled_sparkers), keyed = nameof(id), keyed_target = /obj/machinery/sparker)
	. += rel_many(nameof(controlled_igniters), keyed = nameof(id), keyed_target = /obj/machinery/igniter)
/obj/machinery/sparker/relations()
	. = ..()
	. += rel_key(nameof(id))
/obj/machinery/igniter/relations()
	. = ..()
	. += rel_key(nameof(id))

/obj/machinery/button/ignition/proc/interaction_trigger(datum/act/op/A)
	use_power(5)

	if(active)
		return TRUE

	set_active(TRUE)
	icon_state = "launcheract"

	for(var/obj/machinery/sparker/M as anything in controlled_sparkers)
		M.ignite()

	for(var/obj/machinery/igniter/M as anything in controlled_igniters)
		use_power(50)
		M.set_on(!(M.on))
		M.icon_state = text("igniter[]", M.on)

	if(!after_pending(src, "finish_trigger"))
		after(src, 5 SECONDS, PROC_REF(finish_trigger), key = "finish_trigger")
	return TRUE

/obj/machinery/button/ignition/proc/finish_trigger()
	PRIVATE_PROC(TRUE)

	icon_state = "launcherbtt"
	set_active(FALSE)


/// Whether its work starts at initialization (started_work(starts =)).
/obj/machinery/igniter/step_start_condition()
	return on
