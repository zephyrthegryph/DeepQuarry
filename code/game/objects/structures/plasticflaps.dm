/obj/structure/plasticflaps //HOW DO YOU CALL THOSE THINGS ANYWAY
	name = "\improper plastic flaps"
	desc = "Completely impassable - or are they?"
	icon = 'icons/obj/stationobjs.dmi' //Change this.
	icon_state = "plasticflaps"
	density = FALSE
	anchored = TRUE
	layer = MOB_LAYER
	plane = MOB_PLANE
	explosion_resistance = 5
	var/can_pass_lying = TRUE
	var/static/list/mobs_can_pass = list(
		/mob/living/bot,
		/mob/living/simple_mob/slime/xenobio,
		/mob/living/simple_mob/animal/passive/mouse,
		/mob/living/silicon/robot/drone
		)

CAPABILITIES(/obj/structure/plasticflaps)
	op("use_wirecutter", tool(TOOL_WIRECUTTER), starts(PROC_REF(wirecutter_started)), begins(PROC_REF(wirecutter_begins)), wait(1 SECOND), then(PROC_REF(wirecutter_act_tool_done)))

/obj/structure/plasticflaps/proc/wirecutter_started(datum/act/op/A)
	playsound(src, sounds_of(A.held).use, 50, TRUE)

/obj/structure/plasticflaps/proc/wirecutter_begins(datum/act/op/A)
	return msg_text("You start to cut the plastic flaps.", null)

/obj/structure/plasticflaps/proc/wirecutter_act_tool_done(datum/act/op/A)
	var/mob/user = A.actor
	to_chat(user, span_notice("You cut the plastic flaps."))
	replace_with(src, /obj/item/stack/material/plastic, 4)

/obj/structure/plasticflaps/can_pathfinding_enter(atom/movable/actor, dir, datum/pathfinding/search)
	if(isliving(actor))
		var/mob/living/L = actor
		if(isbot(L))
			return TRUE
		if(L.can_ventcrawl())
			return TRUE
		if(L.mob_size <= MOB_TINY)
			return TRUE
		return FALSE
	return TRUE
	//return isnull(actor.pulling)? TRUE : can_pathfinding_enter(actor.pulling, dir, search)
/obj/structure/plasticflaps/CanPass(atom/A, turf/T)
	if(istype(A) && A.checkpass(PASSGLASS))
		return prob(60)

	var/obj/structure/bed/B = A
	if (istype(A, /obj/structure/bed) && B.has_buckled_mobs())//if it's a bed/chair and someone is buckled, it will not pass
		return 0

	if(istype(A, /obj/vehicle) || istype (A, /obj/mecha)) //no vehicles
		return 0

	var/mob/living/M = A
	if(istype(M))
		if(M.lying && can_pass_lying)
			return ..()
		for(var/mob_type in mobs_can_pass)
			if(istype(A, mob_type))
				return ..()
		return issmall(M)

	return ..()

/obj/structure/plasticflaps/mining //A specific type for mining that doesn't allow airflow because of them damn crates
	name = "airtight plastic flaps"
	desc = "Heavy duty, airtight, plastic flaps. Have extra safety installed, preventing passage of living beings."
	can_atmos_pass = ATMOS_PASS_NO
	can_pass_lying = FALSE
