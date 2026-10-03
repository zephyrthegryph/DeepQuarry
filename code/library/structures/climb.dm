// climb(delay, vaulting) (doc/rewrite/final_api.html, section 11 "The library", Structures; section 16): a structure a mob climbs onto, a table, a railing,
// a crate. It replaces make_climbable() and /datum/om/behaviour/climbable. One op, "climb.climb", reached by a mob dragging itself onto the structure
// (by(0): a mouse has no hands) or by the context menu's "Climb" ("climb.climb_menu", the same effect):
//
//   CAPABILITIES(/obj/structure/table, climb())
//   CAPABILITIES(/obj/structure/railing, climb(delay = 2 SECONDS, vaulting = TRUE))
//
//   delay      how long a climb takes (a small mob takes 60% of it)
//   vaulting   a railing: climbing from its own tile goes over it, to the tile it faces; from any other side it is climbed onto
//
// The climber waits (the climb is cancelled if it moves, falls unconscious, or the structure moves away: the structure moving shakes its climbers off).
// The refusals are one requirement, read again when the wait ends: the climber has to be free to act, next to it, and the tile it would stand on must be
// clear (what stands there that is itself climbable does not count). On success the mob is moved onto the tile; ACT_TRY(climber, climb, structure) runs
// first, so a hook on the mob can veto the climb, and its notice (climbed) goes out after.
//
// While the capability is on a holder it has TRAIT_CLIMBABLE, which can_climb_turf() and the old drag read. What is not here: the legacy climbers
// relation and climb_shake event (a flipped table throwing climbers off), the cliff's need for climbing shoes and the unanchored railing that breaks
// under a climber. They are the holder types' own, written as extend() / hooks on the type, when those types move to the capability.

MSG_DEF(climb/start, "You start climbing onto %T%.", "%U% starts climbing onto %T%!")
MSG_DEF(climb/onto, "You climb onto %T%.", "%U% climbs onto %T%!")
MSG_DEF(climb/over, "You climb over %T%.", "%U% climbs over %T%!")
MSG_DEF_SELF(climb/examine, "It looks climbable.")
MSG_DEF_SELF(climb/hands_needed, "You need your hands and legs free for this.")
MSG_DEF_SELF(climb/cant_now, "You can't climb right now.")
MSG_DEF_SELF(climb/no_hands, "You need hands for this.")
MSG_DEF_SELF(climb/blocked, "You can't climb there, the way is blocked.")
MSG_DEF_SELF(climb/phased, "You can't climb while you are not solid.")

CAPABILITY_TYPE(climb, CAP_CLIMB, /datum/capability/lib/climb, key = NONE, delay = 3.5 SECONDS, vaulting = FALSE)

/datum/capability/lib/climb
	holder_hooks = HOLDER_HOOK_INIT | HOLDER_HOOK_DESTROY

/datum/capability/lib/climb/entries()
	return list(
		examine_line(MSG(climb/examine)),
		op("climb", item(/mob/living), gesture(GESTURE_DRAG), by(0), when(CAP_PROC(is_self_drag)), label("Climb"), \
			needs(req(CAP_PROC(can_climb), because = CAP_PROC(why_not))), \
			begins(MSG(climb/start)), wait(CAP_PROC(climb_time)), then(CAP_PROC(climb_over)), says(CAP_PROC(done_message)), logs(LOG_GAME)),
		op("climb_menu", menu(), label("Climb"), \
			needs(req(CAP_PROC(can_climb), because = CAP_PROC(why_not))), \
			begins(MSG(climb/start)), wait(CAP_PROC(climb_time)), then(CAP_PROC(climb_over)), says(CAP_PROC(done_message)), logs(LOG_GAME)))

/// The holder is climbable while it has the capability: the trait the old behaviour added.
/datum/capability/lib/climb/on_holder_init_ctx(datum/act/eval/A)
	add_trait(A.holder, TRAIT_CLIMBABLE, "capability_climb")

/datum/capability/lib/climb/on_holder_destroy_ctx(datum/act/eval/A)
	remove_trait(A.holder, TRAIT_CLIMBABLE, "capability_climb")

/// The mob dragged is the actor itself.
/datum/capability/lib/climb/proc/is_self_drag(datum/act/op/A)
	return isliving(A.held) && A.held == A.actor && A.held != A.holder

// ---- the rules ----

/// Why `climber` can't climb `holder` now: text (what to tell the climber) or a message type, or null when it can. Reads only.
/datum/capability/lib/climb/proc/refusal(atom/movable/holder, mob/living/climber)
	if(!istype(climber))
		return /datum/msg/climb/cant_now
	if(climber.is_incorporeal())
		return /datum/msg/climb/phased
	if(isAI(climber))
		return /datum/msg/climb/no_hands
	if(climber.restrained() || climber.buckled_to())
		return /datum/msg/climb/hands_needed
	if(climber.stat || climber.lying || climber.has_status(EFFECT_PARALYZED) || climber.has_status(EFFECT_SLEEPING) || climber.has_status(EFFECT_WEAKENED))
		return /datum/msg/climb/cant_now
	if(!climber.Adjacent(holder))
		return /datum/msg/climb/blocked
	var/obj/occupied = can_climb_turf(holder)
	if(occupied)
		return "There's \a [occupied] in the way."
	if(vaulting && get_turf(climber) == get_turf(holder))
		occupied = can_climb_neighbor_turf(holder)
		if(occupied)
			return "You can't climb there, there's \a [occupied] in the way."
	return null

/datum/capability/lib/climb/proc/can_climb(datum/act/op/A)
	return isnull(refusal(A.holder, A.actor))

/datum/capability/lib/climb/proc/why_not(datum/act/op/A)
	return refusal(A.holder, A.actor) || /datum/msg/op/not_available

/// A small mob climbs in 60% of the time.
/datum/capability/lib/climb/proc/climb_time(datum/act/op/A)
	return issmall(A.actor) ? delay * 0.6 : delay

// ---- the climb ----

/// Where the climber ends up: the holder's tile, or (a vaulted railing climbed from its own tile) the tile it faces.
/datum/capability/lib/climb/proc/landing(atom/movable/holder, mob/living/climber)
	if(vaulting && get_turf(climber) == get_turf(holder))
		return get_step(holder, holder.dir)
	return get_turf(holder)

/datum/capability/lib/climb/proc/climb_over(datum/act/op/A)
	var/atom/movable/holder = A.holder
	var/mob/living/climber = A.actor
	if(!istype(climber) || QDELETED(holder))
		return OP_FAILED
	var/turf/destination = landing(holder, climber)
	if(!destination)
		A.reason = /datum/msg/climb/blocked
		return OP_REFUSED
	GLOB.act_next_actor = climber
	var/datum/act/climb/C = ACT_TRY(climber, climb, holder)
	GLOB.act_next_actor = null
	if(isnull(C))
		A.reason = GLOB.act_last_reason || /datum/msg/op/not_available
		log_world("CLIMB: [climber] onto [holder] refused or taken over ([A.reason])")
		return OP_REFUSED
	climber.forceMove(destination)
	if(climber.loc != destination)
		act_cancel(C)
		A.reason = /datum/msg/climb/blocked
		log_world("CLIMB: [climber] did not arrive at [destination] for [holder]")
		return OP_REFUSED
	act_done(C)
	return OP_OK

/// "You climb onto it" or "...over it", by where the climber ended up.
/datum/capability/lib/climb/proc/done_message(datum/act/op/A)
	return get_turf(A.actor) == get_turf(A.holder) ? /datum/msg/climb/onto : /datum/msg/climb/over
