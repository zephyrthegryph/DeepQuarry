
// These are found on the surface, and contain a drone (braintype, inside a borg shell), with a special module and semi-random laws.
/obj/structure/ghost_pod/manual/lost_drone
	name = "drone pod"
	desc = "This is a pod which appears to contain a drone. You might be able to reactivate it, if you're brave enough."
	icon_state = "borg_pod_closed"
	icon_state_opened = "borg_pod_opened"
	density = TRUE
	ghost_query_type = /datum/ghost_query/lost_drone
	confirm_before_open = TRUE
	needscharger = TRUE

/obj/structure/ghost_pod/manual/lost_drone/trigger(mob/user)
	..(user, span_notice("\The [src] appears to be attempting to restart the robot contained inside."), "is attempting to open \a [src].")

/obj/structure/ghost_pod/manual/lost_drone/create_occupant(mob/M)
	set_density(FALSE)
	var/mob/living/silicon/robot/malf/lost/randomlaws/R = new(get_turf(src))
	R.injure(INJURY_BLUNT, rand(5, 30), null, src)
	R.injure(INJURY_BURN, rand(5, 10), null, src)
	if(M.mind)
		M.mind.transfer_to(R)
	// Put this text here before ckey change so that their laws are shown below it, since borg login() shows it.
	to_chat(M, span_notice("You are a <b>Lost Drone</b>, discovered inside the wreckage of your previous home. \
	Something has reactivated you, with their intentions unknown to you, and yours unknown to them. They are a foreign entity, \
	however they did free you from your pod..."))
	to_chat(M, span_notice(span_bold("Be sure to examine your currently loaded lawset closely.") + " Remember, your \
	definiton of 'the station' is where your pod is, and unless your laws say otherwise, the entity that released you \
	from the pod is not a crewmember."))
	R.ckey = M.ckey
	visible_message(span_warning("As \the [src] opens, the eyes of the robot flicker as it is activated."))
	log_and_message_admins("successfully opened \a [src] and got a Lost Drone.", opening_actor)
	..()

/obj/structure/ghost_pod/automatic/gravekeeper_drone
	name = "drone pod"
	desc = "This is a pod which appears to contain a drone. You might be able to reactivate it, if you're brave enough."
	icon_state = "borg_pod_closed"
	icon_state_opened = "borg_pod_opened"
	density = TRUE
	ghost_query_type = /datum/ghost_query/gravekeeper_drone
	needscharger = TRUE

/obj/structure/ghost_pod/automatic/gravekeeper_drone/create_occupant(mob/M)
	set_density(FALSE)
	var/mob/living/silicon/robot/malf/gravekeeper/R = new(get_turf(src))
	if(M.mind)
		M.mind.transfer_to(R)
	// Put this text here before ckey change so that their laws are shown below it, since borg login() shows it.
	to_chat(M, span_notice("You are a <b>Gravekeeper Drone</b>, activated once again to tend to the restful dead."))
	to_chat(M, span_notice(span_bold("Be sure to examine your currently loaded lawset closely.") + " Remember, your \
	definiton of 'your gravesite' is where your pod is."))
	R.ckey = M.ckey
	visible_message(span_warning("As \the [src] opens, the eyes of the robot flicker as it is activated."))
	..()

/obj/structure/ghost_pod/ghost_activated/swarm_drone
	name = "drone shell"
	desc = "A heavy metallic ball."
	icon = 'icons/mob/swarmbot.dmi'
	icon_state = "swarmer_unactivated"
	density = FALSE
	anchored = FALSE

	var/drone_class = "general"
	var/drone_type = /mob/living/silicon/robot/drone/swarm

/obj/structure/ghost_pod/ghost_activated/swarm_drone/create_occupant(mob/M)
	var/mob/living/silicon/robot/drone/swarm/R = new drone_type(get_turf(src))
	if(M.mind)
		M.mind.transfer_to(R)
	to_chat(M, span_cult("You are <b>[R]</b>, the remnant of some distant species, mechanical or flesh, living or dead."))
	R.ckey = M.ckey
	visible_message(span_cult("As \the [src] shudders, it glows before lifting itself with three shimmering limbs!"))
	var/list/drone_briefing = list(span_notice("Many of your tools are standard drone devices, however others provide you with particular benefits."),
		span_notice("Unlike standard drones, you are capable of utilizing 'zero point wells', found in your 'spells' tab."),
		span_notice("Here you will also find your replication ability(s), depending on the type of drone you are."),
		span_notice("Gunners have a special anti-personnel gun capable of shocking or punching through armor with low damage."),
		span_notice("Impalers have an energy-lance."),
		span_notice("General drones have the unique ability to produce one of each of these two types of shells per generation."))
	for(var/briefing_line in drone_briefing)
		after(R, 3 SECONDS, GLOBAL_PROC_REF(to_chat), with = list(R, briefing_line))
	if(!QDELETED(src))
		spent(src, M)

/obj/structure/ghost_pod/ghost_activated/swarm_drone/event/Initialize(mapload)
	. = ..()

	var/turf/T = get_turf(src)
	say_dead_object("A " + span_notice("[drone_class] swarm drone") + " shell is now available in \the [T.loc].", src)

/obj/structure/ghost_pod/ghost_activated/swarm_drone/event/gunner
	name = "gunner shell"

	drone_class = "gunner"
	drone_type = /mob/living/silicon/robot/drone/swarm/gunner

/obj/structure/ghost_pod/ghost_activated/swarm_drone/event/melee
	name = "impaler shell"

	drone_class = "impaler"
	drone_type = /mob/living/silicon/robot/drone/swarm/melee


// === merged from silicon_vr.dm during hard-fork de-suffix (verified no override-order change) ===
/obj/structure/ghost_pod/manual/lost_drone/dogborg			// name is just legacy now
	remains_active = TRUE

/obj/structure/ghost_pod/manual/lost_drone/dogborg
	/// The law type the ghost picked ("Regular" or "Vore"), asked before the drone is made.
	var/drone_laws

/// The laws the ghost picked; a closed window is the regular ones.
/obj/structure/ghost_pod/manual/lost_drone/dogborg/proc/drone_type_chosen(datum/act/request/A)
	var/mob/M = A.request.answerer
	if(QDELETED(M))
		return
	drone_laws = A.answer ? A.answer.value : "Regular"
	create_occupant(M)

/obj/structure/ghost_pod/manual/lost_drone/dogborg/create_occupant(mob/M)
	if(!drone_laws)
		set_used(TRUE)
		open_request(src, /datum/prompt/choice, PROC_REF(drone_type_chosen), answerer = M, title = "Drone Type", question = "What sort of laws do you wish to have as Lost Drone (they will still be random)", choices = list("Regular", "Vore"), buttons = TRUE, timeout = 0)
		return
	if(!(drone_laws == "Vore"))	// Regular
		return ..()
	else
		set_density(FALSE)
		var/mob/living/silicon/robot/malf/lost/randomlaws/vore/R = new(get_turf(src))
		R.injure(INJURY_BLUNT, rand(5, 30), null, src)
		R.injure(INJURY_BURN, rand(5, 10), null, src)
		if(M.mind)
			M.mind.transfer_to(R)
		// Put this text here before ckey change so that their laws are shown below it, since borg login() shows it.
		to_chat(M, span_notice("You are a " + span_bold("Lost Drone") + ", discovered inside the wreckage of your previous home. \
		Something has reactivated you, with their intentions unknown to you, and yours unknown to them. They are a foreign entity, \
		however they did free you from your pod..."))
		to_chat(M, span_notice(span_bold("Be sure to examine your currently loaded lawset closely.") + " Remember, your \
		definiton of 'the station' is where your pod is, and unless your laws say otherwise, the entity that released you \
		from the pod is not a crewmember."))
		R.ckey = M.ckey
		visible_message(span_warning("As \the [src] opens, the eyes of the robot flicker as it is activated."))
		log_and_message_admins("successfully opened \a [src] and got a Lost Drone.", opening_actor)
		set_used(TRUE)
		return TRUE
