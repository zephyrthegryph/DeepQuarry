///////////////////////////
// Dost thou even hoist? //
///////////////////////////

#define NORMAL_LAYER 3

/obj/item/hoist_kit
	name = "hoist kit"
	desc = "A setup kit for a hoist that can be used to lift things. The hoist will deploy in the direction you're facing."
	icon = 'icons/obj/hoists.dmi'
	icon_state = "hoist_case"

DECLARE_INTERACTIONS(/obj/item/hoist_kit, INTERACT_USE(null, PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/hoist_kit/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	new /obj/structure/hoist (get_turf(user), user.dir)
	user.visible_message(span_warning("[user] deploys the hoist kit!"), span_notice("You deploy the hoist kit!"), span_notice("You hear the sound of parts snapping into place."))
	consume(src, user)
	return TRUE

/obj/effect/hoist_hook
	name = "hoist clamp"
	desc = "A clamp used to lift people or things."
	icon = 'icons/obj/hoists.dmi'
	icon_state = "hoist_hook"
	var/tmp/source_hoist_handle
	can_buckle = TRUE
	anchored = TRUE
	plane = ABOVE_MOB_PLANE

EXTEND_INTERACTIONS(/obj/effect/hoist_hook, \
	INTERACT_HAND_UNGATED(null, TYPE_PROC_REF(/atom, interaction_swallow)), \
	INTERACT_DRAG("Attach", PROC_REF(interaction_hoist_hook_attach), REQ_TARGET_STATE(/obj/effect/hoist_hook/proc/can_attach)), \
)

/// Requirement: TRUE, or why the dragged thing can't be clamped on.
/obj/effect/hoist_hook/proc/can_attach(mob/user, atom/target, atom/movable/held)
	if(!istype(held) || !held.simulated || held.anchored)
		return "you can't do that"
	if(source_hoist().hoistee())
		return "[source_hoist().hoistee()] is already attached"
	return TRUE

/// Old MouseDrop_T: clamp the dragged thing onto the hook. Replaces the buckle drag.
/obj/effect/hoist_hook/proc/interaction_hoist_hook_attach(mob/user, atom/movable/AM, datum/interaction/interaction)
	if (use_check(user, 0))
		return TRUE

	source_hoist().attach_hoistee(AM)
	user.visible_message(span_danger("[user] attaches \the [AM] to \the [src]."), span_danger("You attach \the [AM] to \the [src]."), span_danger("You hear something clamp into place."))
	return TRUE

/obj/structure/hoist/proc/attach_hoistee(atom/movable/AM)
	if (get_turf(AM) != get_turf(source_hook))
		AM.forceMove(get_turf(source_hook))
	hoistee_handle = om_handle(AM)
	if(ismob(AM))
		source_hook.buckle_mob(AM)
	AM.set_anchored(TRUE) // why isn't this being set by buckle_mob for silicons?
	source_hook.layer = AM.layer + 0.1

/obj/effect/hoist_hook/MouseDrop(atom/dest)
	..()
	if(!Adjacent(usr) || !dest.Adjacent(usr)) return // carried over from the default proc

	if (!(ishuman(usr) || issilicon(usr)))
		return

	if (usr.incapacitated())
		to_chat(usr, span_notice("You can't do that while incapacitated."))
		return

	if (!usr.IsAdvancedToolUser())
		to_chat(usr, span_notice("You stare cluelessly at \the [src]."))
		return

	if (!source_hoist().hoistee())
		return
	if (!isturf(dest))
		return
	if (!dest.Adjacent(source_hoist().hoistee()))
		return

	source_hoist().check_consistency()

	var/turf/desturf = dest
	source_hoist().hoistee().forceMove(desturf)
	usr.visible_message(span_danger("[usr] detaches \the [source_hoist().hoistee()] from the hoist clamp."), span_danger("You detach \the [source_hoist().hoistee()] from the hoist clamp."), span_danger("You hear something unclamp."))
	source_hoist().release_hoistee()

// This will handle mobs unbuckling themselves.
/obj/effect/hoist_hook/unbuckle_mob(mob/living/buckled_mob, force = FALSE)
	. = ..()
	if (. && !QDELETED(source_hoist()))
		var/mob/M = .
		source_hoist().hoistee_handle = null
		M.fall()

/obj/structure/hoist
	icon = 'icons/obj/hoists.dmi'
	icon_state = "hoist_base"
	var/broken = 0
	density = FALSE
	anchored = TRUE
	name = "hoist"
	desc = "A manual hoist, uses a clamp and pulley to hoist things."
	var/tmp/hoistee_handle
	var/movedir = UP
	var/obj/effect/hoist_hook/source_hook

/obj/structure/hoist/Initialize(mapload, ndir)
	. = ..()
	dir = ndir
	var/turf/newloc = get_step(src, dir)
	source_hook = new(newloc)
	source_hook.source_hoist_handle = om_handle(src)

DECLARE_REF(/obj/structure/hoist, "source_hook", OWNED, null)

// whatever hangs from the hoist is released.
/obj/structure/hoist/on_destroy(force)
	if(hoistee())
		release_hoistee()
	..()

/obj/structure/hoist/proc/check_consistency()
	if (!hoistee())
		return
	if (hoistee().z != source_hook.z)
		release_hoistee()
		return

/obj/structure/hoist/proc/release_hoistee()
	if(ismob(hoistee()))
		source_hook.unbuckle_mob(hoistee())
	else
		hoistee().anchored = FALSE
	hoistee_handle = null
	layer = NORMAL_LAYER

/obj/structure/hoist/proc/break_hoist()
	if(broken)
		return
	broken = 1
	desc += " It looks broken, and the clamp has retracted back into the hoist. Seems like you'd have to re-deploy it to get it to work again."
	if(hoistee())
		release_hoistee()
	QDEL_NULL(source_hook)

/obj/structure/hoist/ex_act(severity)
	. = ..()
	if(!QDELETED(src) && severity <= 2 && !broken)
		break_hoist()

/obj/effect/hoist_hook/ex_act(severity)
	// A hit on the hook wrenches the hoist; it breaks more often the closer the blast.
	if(prob(100 / severity))
		source_hoist().break_hoist()

/obj/structure/hoist
	silicon_use = ROBOT_USE_HAND

DECLARE_INTERACTIONS(/obj/structure/hoist, \
	INTERACT_HAND_UNGATED(null, PROC_REF(interaction_hand), REQ_TARGET_STATE(/obj/structure/hoist/proc/can_work_hoist)), \
	INTERACT_VERB("Collapse Hoist", PROC_REF(hoist_verb_collapse), REQ_TARGET_STATE(/obj/structure/hoist/proc/can_collapse)), \
)

/// Requirement: TRUE, or why this user can't work the hoist. Non-humanoids are turned away silently by the effect.
/obj/structure/hoist/proc/can_work_hoist(mob/living/user, atom/target, obj/item/held)
	if(!(ishuman(user) || issilicon(user)))
		return TRUE
	if(user.incapacitated())
		return "you can't do that while incapacitated"
	if(!user.IsAdvancedToolUser())
		return "you stare cluelessly at it"
	if(broken)
		return "the hoist is broken"
	return TRUE

/// Requirement: TRUE, or why the hoist can't be collapsed now.
/obj/structure/hoist/proc/can_collapse(mob/user, atom/target, obj/item/held)
	if(!(ishuman(user) || issilicon(user)) || isobserver(user) || user.incapacitated())
		return TRUE
	if(!user.IsAdvancedToolUser())
		return "you stare cluelessly at it"
	if(hoistee())
		return "you cannot collapse the hoist with [hoistee()] attached"
	return TRUE

/// Old attack_hand.
/obj/structure/hoist/proc/interaction_hand(mob/living/user, obj/item/held, datum/interaction/interaction)
	if (!(ishuman(user) || issilicon(user)))
		return TRUE

	var/can = can_move_dir(movedir)
	var/movtext = movedir == UP ? "raise" : "lower"
	if (!can) // If you can't...
		movedir = movedir == UP ? DOWN : UP // switch directions!
		to_chat(user, span_notice("You switch the direction of the pulley."))
		return TRUE

	if (!hoistee())
		user.visible_message(span_notice("[user] begins to [movtext] the clamp."), span_notice("You begin to [movtext] the clamp."), span_notice("You hear the sound of a crank."))
		move_dir(movedir, 0)
		return TRUE

	check_consistency()

	var/size
	if (ismob(hoistee()))
		var/mob/M = hoistee()
		size = M.mob_size
	else if (isobj(hoistee()))
		var/obj/O = hoistee()
		size = O.w_class

	user.visible_message(span_notice("[user] begins to [movtext] \the [hoistee()]!"), span_notice("You begin to [movtext] \the [hoistee()]!"), span_notice("You hear the sound of a crank."))
	om_task_timed(user, (1 SECONDS) * size / 4, src, src, PROC_REF(move_dir), list(movedir, 1))
	return TRUE

/obj/structure/hoist/proc/collapse_kit()
	replace_with(src, /obj/item/hoist_kit)

/// Old Collapse Hoist verb.
/obj/structure/hoist/proc/hoist_verb_collapse(mob/user, obj/item/held, datum/interaction/interaction)
	if (!(ishuman(user) || issilicon(user)))
		return

	if (isobserver(user) || user.incapacitated())
		return
	collapse_kit()

/obj/structure/hoist/proc/can_move_dir(direction)
	var/turf/dest = direction == UP ? GetAbove(source_hook) : GetBelow(source_hook)
	switch(direction)
		if (UP)
			if (!isopenspace(dest)) // can't move into a solid tile
				return 0
			if (source_hook in get_step(src, dir)) // you don't get to move above the hoist
				return 0
		if (DOWN)
			if (!isopenspace(get_turf(source_hook))) // can't move down through a solid tile
				return 0
	if (!dest) // can't move if there's nothing to move to
		return 0
	return 1

/obj/structure/hoist/proc/move_dir(direction, ishoisting)
	var/can = can_move_dir(direction)
	if (!can)
		return 0
	var/turf/move_dest = direction == UP ? GetAbove(source_hook) : GetBelow(source_hook)
	source_hook.forceMove(move_dest)
	if (!ishoisting)
		return 1
	hoistee().hoist_act(move_dest)
	return 1

/atom/movable/proc/hoist_act(turf/dest)
	forceMove(dest)
	return TRUE

#undef NORMAL_LAYER

/// LC-refs: the hoistee this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/structure/hoist/proc/hoistee() as /atom/movable
	return om_resolve(hoistee_handle)

/// LC-refs: the source_hoist this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/effect/hoist_hook/proc/source_hoist() as /obj/structure/hoist
	return om_resolve(source_hoist_handle)
