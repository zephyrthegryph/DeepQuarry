/obj/machinery/firework_launcher
	name = "firework launcher"
	desc = "A machine for launching fireworks of varying practicality."
	icon = 'icons/obj/machines/firework_launcher.dmi'
	icon_state = "launcher01"
	density = TRUE
	anchored = TRUE
	maintenance_flags = MACHINE_MAINT_STANDARD_MOVABLE
	maintenance_wrench_time = 2 SECONDS

	circuit = /obj/item/circuitboard/firework_launcher
	var/tmp/obj/item/firework_star/loaded_star
	EXPIRY_DECLARE(last_launch)
	var/launch_cooldown = 5 MINUTES

// ALLOW(init/INSTANCE_STATE): takes its built parts and stamps its cooldown so a rebuild cannot skip it
/obj/machinery/firework_launcher/Initialize(mapload)
	. = ..()

	EXPIRY_STAMP(src, last_launch, CLOCK_WORLD)	// Prevents cheesing cooldown by deconstructing and reconstructing

/obj/machinery/firework_launcher/RefreshParts()
	launch_cooldown = 5 MINUTES
	var/rating = get_part_rating(/obj/item/stock_parts/micro_laser) - get_part_count(/obj/item/stock_parts/micro_laser)
	launch_cooldown = max(0, (launch_cooldown - ((rating*30) SECONDS)))			// For every part tier above 1 on the two lasers, reduce cooldown by 30 seconds. 1 minute cooldown on the tier 5 parts, 3 minutes on tier 3.

	. = ..()

/// The look (the draw sweep: from its template).
/obj/machinery/firework_launcher/draw(datum/look/look)
	..()
	look.state("launcher[loaded_star ? "1" : "0"][anchored ? "1" : "0"][panel_open ? "_open" : ""]")

CAPABILITIES(/obj/machinery/firework_launcher)
	default_parts()
	op("part_replacement", item(/obj/item/storage/part_replacer), priority(OP_PRIORITY_DEFAULT - 1), label("Replace parts"), then(TYPE_PROC_REF(/obj/machinery, op_part_replacement)))
	op("load_star", item(/obj/item/firework_star), priority(OP_PRIORITY_DEFAULT - 1), label("Insert firework star"), needs(req(PROC_REF(can_load_star_holds))), then(PROC_REF(interaction_load_star)))
	op("eject", menu(), priority(OP_PRIORITY_DEFAULT - 1), label("Eject Firework Star"), needs(req_adjacent(), req_capable(), req(PROC_REF(dq_actor_can_act_holds))), then(PROC_REF(interaction_eject)))
	op("launch", hand(), priority(OP_PRIORITY_DEFAULT - 1), ungated(), label("Launch"), needs(req(PROC_REF(can_launch_holds))), then(PROC_REF(interaction_launch)))

/// Requirement: the launcher is empty.
/obj/machinery/firework_launcher/proc/can_load_star(mob/user, atom/target, obj/item/held)
	var/obj/item/star = loaded_star()
	if(star)
		return "\The [src] already has \a [star] inside, unload it first"
	return TRUE

/// Requirement (was REQ_* can_load_star): the legacy check answers TRUE to pass.
/obj/machinery/firework_launcher/proc/can_load_star_holds(datum/act/op/A)
	var/answer = can_load_star(A.actor, src, A.held)
	if(!istext(answer) && answer)
		return null
	return req_refusal_value(answer, /datum/msg/req_failed)

/// Why can_load_star_holds refuses: the legacy check's text, else the clause's own reason.
/obj/machinery/firework_launcher/proc/interaction_load_star(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/firework_star/O = A.held
	if(user.unEquip(O, 0, src))
		rel_set(src, nameof(loaded_star), O)
		to_chat(user, span_notice("You insert the firework star into \the [src]."))
		add_fingerprint(user)
		return TRUE
	return TRUE

/// Requirement (was REQ_* dq_actor_can_act): the legacy check answers TRUE to pass.
/obj/machinery/firework_launcher/proc/dq_actor_can_act_holds(datum/act/op/A)
	var/answer = dq_actor_can_act(A.actor, src, A.held)
	if(!istext(answer) && answer)
		return null
	return req_refusal_value(answer, "you can't do that right now")

/// Why dq_actor_can_act_holds refuses: the legacy check's text, else the clause's own reason.
/obj/machinery/firework_launcher/proc/interaction_eject(datum/act/op/A)
	var/mob/user = A.actor
	if(!loaded_star())
		to_chat(user, span_notice("There is no firework star loaded in \the [src]."))
		return TRUE
	else
		loaded_star().forceMove(get_turf(src))
		rel_clear(src, nameof(loaded_star))
		add_fingerprint(user)
	return TRUE

/// Requirement: TRUE, or why the loaded firework can't be launched.
/obj/machinery/firework_launcher/proc/can_launch(mob/user, atom/target, obj/item/held)
	if(panel_open)
		return "close the panel first"
	if(!loaded_star())
		return "there is no firework star loaded in \the [src]"
	if(ELAPSED_SINCE(src, last_launch, CLOCK_WORLD) <= launch_cooldown) // ALLOW(reads): the legacy check is read when the op is tried, never from a cached menu
		return "\The [src] is still re-priming for launch"
	if(!anchored)
		return "\The [src] must be firmly secured to the ground before firework can be launched"
	var/datum/planet/P = get_planet()
	if(!P || !(P.weather_holder)) // There are potential cases of being outside but not on planet. And checking whether planet has weather at all is more sanity thing than anything.
		return "\The [src] beeps as its safeties seem to prevent launch in the current location"
	var/datum/weather_holder/WH = P.weather_holder
	if(WH.firework_override && istype(loaded_star(), /obj/item/firework_star/weather)) // Enable weather-based events to not be ruined
		return "\The [src] beeps as it seems some interference is preventing launch of this type of firework"
	return TRUE

/// Requirement (was REQ_* can_launch): the legacy check answers TRUE to pass.
/obj/machinery/firework_launcher/proc/can_launch_holds(datum/act/op/A)
	var/answer = can_launch(A.actor, src, A.held)
	if(!istext(answer) && answer)
		return null
	return req_refusal_value(answer, /datum/msg/req_failed)

/// Why can_launch_holds refuses: the legacy check's text, else the clause's own reason.
/obj/machinery/firework_launcher/proc/interaction_launch(datum/act/op/A)
	var/mob/user = A.actor
	var/datum/planet/P = get_planet()
	var/datum/weather_holder/WH = P.weather_holder

	to_chat(user, span_notice("You launch the firework!"))
	play_sfx(get_turf(src), SFX_WEAPONS_RPG)
	loaded_star().trigger_firework(WH)
	spent(loaded_star(), user)
	rel_clear(src, nameof(loaded_star))
	EXPIRY_STAMP(src, last_launch, CLOCK_WORLD)
	add_fingerprint(user)
	flick("launcher_launch", src)
	return TRUE

/obj/machinery/firework_launcher/proc/get_planet()
	var/turf/T = get_turf(src)
	if(!T)
		return

	if(!T.is_outdoors())
		return

	var/datum/planet/P = planets_z_to_planet()[T.z]
	if(!P)
		return
	return P

/// the loaded_star this refers to (a relation view: null once it is deleted).
/obj/machinery/firework_launcher/proc/loaded_star() as /obj/item/firework_star
	return loaded_star // ALLOW(reads): the legacy check is read when the op is tried, never from a cached menu
