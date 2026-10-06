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
	extend(/datum/act/hit/generic, instead(then(PROC_REF(smashed_by))))
	links(/obj/structure/ladder::target_down, /obj/structure/ladder::target_up)

/// A simple mob's (or a xeno's) generic hit on it, taken over (the hit/generic action): HOOK_DECLINE lets the default generic attack land.
/obj/structure/ladder/proc/smashed_by(datum/act/hit/generic/A)
	var/mob/user = A.attacker
	//Simple Animal
	if(isanimal(user))
		attack_hand(user)
	else
		return HOOK_DECLINE

/obj/structure/ladder/welder_act(mob/user, obj/item/C)
	var/obj/item/weldingtool/WT = C.get_welder()
	if(WT.remove_fuel(0, user))
		play_sfx(src, SFX_ITEMS_WELDER2)
		act_message(user, src, MSG_SELF("You start to deconstruct %T%."), MSG_OTHERS("%U% starts to deconstruct %T%."), MSG_BLIND("You hear welding"))
		task_timed(user, 2 SECONDS, src, src, PROC_REF(deconstruct_done), list(user, WT))
		return ITEM_INTERACT_SUCCESS
	return ITEM_INTERACT_BLOCKING

/obj/structure/ladder/proc/deconstruct_done(mob/user, obj/item/weldingtool/WT)
	if(!WT.isOn())
		return
	var/obj/structure/ladder_assembly/A
	to_chat(user, "You deconstruct \the [src].")
	if(target_up)
		target_up.visible_message("\The [target_up] deconstructs from below")
		A = new /obj/structure/ladder_assembly(target_up.loc)
		A.state = LADDER_CONSTRUCTION_WELDED
		A.set_anchored(TRUE)
		destroyed(target_up, user, "deconstructed")
	if(target_down)
		target_down.visible_message("\The [target_down] deconstructs from above")
		A = new /obj/structure/ladder_assembly(target_down.loc)
		A.state = LADDER_CONSTRUCTION_WELDED
		A.set_anchored(TRUE)
		destroyed(target_down, user, "deconstructed")
	A = new /obj/structure/ladder_assembly(loc)
	A.state = LADDER_CONSTRUCTION_WRENCHED
	A.set_anchored(TRUE)
	destroyed(src, user, "deconstructed")

DECLARE_INTERACTIONS(/obj/structure/ladder, \
	INTERACT_HAND_UNGATED(null, PROC_REF(interaction_hand)), \
	INTERACT_OBSERVER("Climb", PROC_REF(ladder_ghost_climb)), \
)

/// Old attack_hand.
/obj/structure/ladder/proc/interaction_hand(mob/M, obj/item/held, datum/interaction/interaction)
	if(!M.may_climb_ladders(src))
		return TRUE

	var/obj/structure/ladder/target_ladder = getTargetLadder(M, PROC_REF(interaction_hand), args)
	if(!target_ladder)
		return TRUE
	if(!(M.loc == loc) && !M.Move(get_turf(src)))
		to_chat(M, span_notice("You fail to reach \the [src]."))
		return TRUE

	climbLadder(M, target_ladder)
	return TRUE

/// Old attack_ghost: drift up or down the ladder. Never fell through to the default.
/obj/structure/ladder/proc/ladder_ghost_climb(mob/M, obj/item/held, datum/interaction/interaction)
	var/target_ladder = getTargetLadder(M, PROC_REF(ladder_ghost_climb), args)
	if(target_ladder)
		M.forceMove(get_turf(target_ladder))
	return TRUE

/obj/structure/ladder
	silicon_use = ROBOT_USE_HAND

/// The ladder to climb to. Asking up or down re-runs `caller_proc` with `caller_args` on the answer,
/// and returns null meanwhile.
/obj/structure/ladder/proc/getTargetLadder(mob/M, caller_proc, list/caller_args)
	if((!target_up && !target_down) || (target_up && !istype(target_up.loc, /turf) || (target_down && !istype(target_down.loc,/turf))))
		to_chat(M, span_notice("\The [src] is incomplete and can't be climbed."))
		return
	if(target_down && target_up)
		var/direction = rerun_ask(M, "direction", caller_proc, caller_args, /datum/prompt/choice, question = "Do you want to go up or down?", title = "Ladder", choices = list("Up", "Down", "Cancel"), buttons = TRUE)

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

/mob/proc/may_climb_ladders(ladder)
	if(!Adjacent(ladder))
		to_chat(src, span_warning("You need to be next to \the [ladder] to start climbing."))
		return FALSE
	if(incapacitated())
		to_chat(src, span_warning("You are physically unable to climb \the [ladder]."))
		return FALSE
	return TRUE

/mob/observer/dead/may_climb_ladders(ladder)
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

	task_timed(M, (climb_time * climb_modifier), src, src, PROC_REF(climb_done), list(M, target_ladder))
	return FALSE

/obj/structure/ladder/proc/climb_done(mob/M, obj/target_ladder)
	var/turf/T = get_turf(target_ladder)
	for(var/atom/A in turf_contents_of_type(T, /atom))
		if(!A.CanPass(M, M.loc, 1.5, 0))
			to_chat(M, span_notice("\The [A] is blocking \the [src]."))
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
