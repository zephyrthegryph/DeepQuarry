/obj/structure/ladder
	name = "ladder"
	desc = "A ladder. You can climb it up and down."
	icon_state = "ladder01"
	icon = 'icons/obj/structures/multiz.dmi'
	density = FALSE
	opacity = 0
	anchored = TRUE

	var/allowed_directions = DOWN
	var/obj/structure/ladder/target_up
	var/obj/structure/ladder/target_down

	var/climb_time = 2 SECONDS

/obj/structure/ladder/Initialize(mapload)
	. = ..()
	attempt_connection()

/obj/structure/ladder/proc/attempt_connection()
	// The DOWN-allowing ladder links to the UP-allowing one below, wiring BOTH ends:
	// our own target_down AND, reciprocally, the lower ladder's target_up. The reciprocal
	// assignment had been dropped in a past refactor (the removed "legacy .target" line),
	// which left every lower ladder with a null target_up — so up-climbing was broken
	// game-wide and the ladder map test failed on the first UP ladder it checked.
	if(allowed_directions & DOWN) //we only want to do the top one, as it will initialize the ones before it.
		for(var/obj/structure/ladder/L in GetBelow(src))
			if(L.allowed_directions & UP)
				rel_set(src, nameof(target_down), L)
				break

CAPABILITIES(/obj/structure/ladder)
	silicon_hand(robots = TRUE)
	// Climbing it (climbLadder()): the climber stays beside it for the climb time.
	op("climb_ladder", ai(), needs(req_capable()), takes("target_ladder", "time"), wait(PROC_REF(ladder_climb_time)), then(PROC_REF(climb_done)))
	extend(/datum/act/hit/generic, instead(then(PROC_REF(smashed_by))))
	links(/obj/structure/ladder::target_down, /obj/structure/ladder::target_up)
	op("hand", hand(), label("Use"), ungated(), needs(req_capable()), asks(/datum/prompt/choice, fields = list("question" = "Do you want to go up or down?", "title" = "Ladder", "choices" = list("Up", "Down", "Cancel"), "buttons" = TRUE, "timeout" = 0), step = "direction", when = cond_all(nameof(target_down), nameof(target_up))), then(PROC_REF(interaction_hand)))
	op("deconstruct", tool(TOOL_WELDER), label("Deconstruct"), needs(req_welder_lit()), costs(RES_FUEL, 0), begins(PROC_REF(deconstruct_begins)), plays(SFX_ITEMS_WELDER2, at_start = TRUE), wait(2 SECONDS), then(PROC_REF(deconstruct_done)))
	op("ladder_ghost_climb", observer(), label("Climb"), asks(/datum/prompt/choice, fields = list("question" = "Do you want to go up or down?", "title" = "Ladder", "choices" = list("Up", "Down", "Cancel"), "buttons" = TRUE, "timeout" = 0), step = "direction", when = cond_all(nameof(target_down), nameof(target_up))), then(PROC_REF(ladder_ghost_climb)))

/// A simple mob's (or a xeno's) generic hit on it, taken over (the hit/generic action): HOOK_DECLINE lets the default generic attack land.
/obj/structure/ladder/proc/smashed_by(datum/act/hit/generic/A)
	var/mob/user = A.attacker
	//Simple Animal
	if(isanimal(user))
		attack_hand(user)
	else
		return HOOK_DECLINE

/obj/structure/ladder/proc/deconstruct_begins(datum/act/op/A)
	return msg_text("You start to deconstruct %T%.", "%U% starts to deconstruct %T%.", "You hear welding")

/obj/structure/ladder/proc/deconstruct_done(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/structure/ladder_assembly/LA
	to_chat(user, "You deconstruct \the [src].")
	if(target_up)
		target_up.visible_message("\The [target_up] deconstructs from below")
		LA = new /obj/structure/ladder_assembly(target_up.loc)
		LA.set_state(LADDER_CONSTRUCTION_WELDED)
		LA.set_anchored(TRUE)
		destroyed(target_up, user, "deconstructed")
	if(target_down)
		target_down.visible_message("\The [target_down] deconstructs from above")
		LA = new /obj/structure/ladder_assembly(target_down.loc)
		LA.set_state(LADDER_CONSTRUCTION_WELDED)
		LA.set_anchored(TRUE)
		destroyed(target_down, user, "deconstructed")
	LA = new /obj/structure/ladder_assembly(loc)
	LA.set_state(LADDER_CONSTRUCTION_WRENCHED)
	LA.set_anchored(TRUE)
	destroyed(src, user, "deconstructed")
	return OP_OK

/// Old attack_hand.
/obj/structure/ladder/proc/interaction_hand(datum/act/op/A)
	var/mob/M = A.actor
	if(!M.may_climb_ladders(src))
		return OP_OK

	var/obj/structure/ladder/target_ladder = getTargetLadder(M, A.step_value("direction"))
	if(!target_ladder)
		return OP_OK
	if(!(M.loc == loc) && !M.Move(get_turf(src)))
		to_chat(M, span_notice("You fail to reach \the [src]."))
		return OP_OK

	climbLadder(M, target_ladder)
	return OP_OK

/// Old attack_ghost: drift up or down the ladder. Never fell through to the default.
/obj/structure/ladder/proc/ladder_ghost_climb(datum/act/op/A)
	var/mob/M = A.actor
	var/target_ladder = getTargetLadder(M, A.step_value("direction"))
	if(target_ladder)
		M.forceMove(get_turf(target_ladder))
	return OP_OK

/// Whether both of the ladder's ends that exist are standing on turfs.
/obj/structure/ladder/proc/ladder_complete()
	if((!target_up && !target_down) || (target_up && !istype(target_up.loc, /turf) || (target_down && !istype(target_down.loc,/turf))))
		return FALSE
	return TRUE

/// The ladder to climb to, given the answer to the up-or-down question (null when it was not asked).
/obj/structure/ladder/proc/getTargetLadder(mob/M, direction)
	if(!ladder_complete())
		to_chat(M, span_notice("\The [src] is incomplete and can't be climbed."))
		return
	if(target_down && target_up)
		if(!direction || direction == "Cancel")
			return

		if(!M.may_climb_ladders(src))
			return

		switch(direction)
			if("Up")
				return target_up
			if("Down")
				return target_down
	else
		return target_down || target_up

/// Why this mob cannot climb the ladder now, or null.
/mob/proc/climb_refusal(ladder)
	if(!Adjacent(ladder))
		return "You need to be next to \the [ladder] to start climbing."
	if(incapacitated())
		return "You are physically unable to climb \the [ladder]."
	return null

/mob/observer/dead/climb_refusal(ladder)
	return null

/mob/proc/may_climb_ladders(ladder)
	var/why = climb_refusal(ladder)
	if(why)
		to_chat(src, span_warning(why))
		return FALSE
	return TRUE

/obj/structure/ladder/proc/climbLadder(mob/M, obj/target_ladder)
	var/direction = (target_ladder == target_up ? "up" : "down")
	act_message(M, src, MSG_SELF(span_info("You begin climbing [direction] %T%!")), \
		MSG_OTHERS(span_infoplain(span_bold("%U%") + " begins climbing [direction] %T%!")), \
		MSG_BLIND(span_info("You hear the grunting and clanging of a metal ladder being used.")))

	target_ladder.audible_message(span_notice("You hear something coming [direction] \the [src]"), runemessage = "clank clank")

	var/climb_modifier = 1
	if(ishuman(M))
		var/mob/living/carbon/human/MS = M
		climb_modifier = MS.species.climb_mult

	perform_op(M, src, "climb_ladder", null, ORIGIN_AI, AUTH_AI | AUTH_PHYSICAL, with = list("target_ladder" = target_ladder, "time" = climb_time * climb_modifier))
	return FALSE

/// How long the climb takes: the ladder's time scaled by the climber's species.
/obj/structure/ladder/proc/ladder_climb_time(datum/act/op/A)
	return A.arg("time")

/obj/structure/ladder/proc/climb_done(datum/act/op/A)
	var/mob/M = A.actor
	var/obj/target_ladder = A.arg("target_ladder")
	if(QDELETED(target_ladder))
		return
	var/turf/T = get_turf(target_ladder)
	for(var/atom/blocker in turf_contents_of_type(T, /atom))
		if(!blocker.CanPass(M, M.loc, 1.5, 0))
			to_chat(M, span_notice("\The [blocker] is blocking \the [src]."))
			return
	M.forceMove(T) // Fixes adminspawned ladders

/obj/structure/ladder/CanPass(obj/mover, turf/source, height, airflow)
	return airflow || !density

/// Appearance reader: 1 when the ladder leads up.
/obj/structure/ladder/proc/appearance_up()
	return !!(allowed_directions & UP)

/// Appearance reader: 1 when the ladder leads down.
/obj/structure/ladder/proc/appearance_down()
	return !!(allowed_directions & DOWN)

/// The look (the draw sweep: from its template).
/obj/structure/ladder/draw(datum/look/look)
	..()
	look.state("ladder[appearance_up()][appearance_down()]")

/obj/structure/ladder/up
	allowed_directions = UP
	icon_state = "ladder10"

/obj/structure/ladder/updown
	allowed_directions = UP|DOWN
	icon_state = "ladder11"
