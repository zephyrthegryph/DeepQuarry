// climb(delay, vaulting, landing, delay_by, gate, climbed) (doc/rewrite/final_api.html, section 11 "The library", Structures; section 16): a structure a mob
// climbs onto, a table, a railing, a crate, a machine. It replaced make_climbable() and /datum/om/behaviour/climbable. One op, "climb.climb", reached by
// a mob dragging itself onto the structure (by(0): a mouse has no hands) or by the context menu's "Climb" ("climb.climb_menu", the same effect):
//
//   CAPABILITIES(/obj/structure/table)
//       climb(landing = PROC_REF(flipped_landing))
//   CAPABILITIES(/obj/structure/railing)
//       climb(delay = 3.4 SECONDS, vaulting = TRUE, climbed = PROC_REF(climbed_over))
//
//   delay      how long a climb takes (a small mob takes 60% of it)
//   vaulting   a railing: climbing from its own tile goes over it, to the tile it faces; from any other side it is climbed onto
//   landing    a holder proc (mob/living/climber) -> the turf the climber ends on, or null for the default (a flipped table: out the side it faces)
//   delay_by   a holder proc () -> the delay, in place of `delay` (a double cliff takes half)
//   gate       a holder proc (mob/living/climber) -> null to allow, or why not (text or a message type): a cliff needs climbing shoes, a fence a hole
//   climbed    a holder proc (mob/living/climber) called once the climber has arrived (an unanchored railing breaks under it)
//
// The climber waits (the climb is cancelled if it moves, falls unconscious, or the structure moves away). The refusals are one requirement, read again when
// the wait ends: the climber has to be free to act, next to it, the gate has to allow, and the tile it would stand on must be clear (what stands there that
// is itself climbable does not count). On success the mob is moved onto the tile; ACT_TRY(climber, climb, structure) runs first, so a hook on the mob can
// veto the climb, and its notice (climbed) goes out after.
//
// Climbers are the actors of the pending climb ops on the structure (climbers_of()). climb_shake_off(structure, shaker) knocks them off: the structure
// being opened (a crate), broken (a solar panel), flipped (a table) or hit (hand_gate); a structure that moves under a climber does the same through the op's
// own on_interrupt (the wait's keep on the structure's tile breaks).
//
// While the capability is on a holder it has TRAIT_CLIMBABLE, which can_climb_turf() reads.

MSG_DEF(climb/start, "You start climbing onto %T%.", "%U% starts climbing onto %T%!")
MSG_DEF(climb/onto, "You climb onto %T%.", "%U% climbs onto %T%!")
MSG_DEF(climb/over, "You climb over %T%.", "%U% climbs over %T%!")
MSG_DEF_SELF(climb/examine, "It looks climbable.")
MSG_DEF_SELF(climb/hands_needed, "You need your hands and legs free for this.")
MSG_DEF_SELF(climb/cant_now, "You can't climb right now.")
MSG_DEF_SELF(climb/no_hands, "You need hands for this.")
MSG_DEF_SELF(climb/blocked, "You can't climb there, the way is blocked.")
MSG_DEF_SELF(climb/phased, "You can't climb while you are not solid.")

CAPABILITY_TYPE(climb, CAP_CLIMB, /datum/capability/lib/climb, key = NONE, delay = 3.5 SECONDS, vaulting = FALSE, landing = null, delay_by = null, gate = null, climbed = null)

/datum/capability/lib/climb
	holder_hooks = HOLDER_HOOK_INIT | HOLDER_HOOK_DESTROY

/datum/capability/lib/climb/entries()
	return list(
		examine_line(MSG(climb/examine)),
		op("climb", item(/mob/living), gesture(GESTURE_DRAG), by(0), when(CAP_PROC(is_self_drag)), label("Climb"), \
			needs(req_bool(CAP_PROC(can_climb), because = CAP_PROC(why_not))), \
			begins(MSG(climb/start)), wait(CAP_PROC(climb_time)), on_interrupt(CAP_PROC(climb_interrupted)), then(CAP_PROC(climb_over)), says(CAP_PROC(done_message)), logs(LOG_GAME)),
		op("climb_menu", menu(), label("Climb"), \
			needs(req_bool(CAP_PROC(can_climb), because = CAP_PROC(why_not))), \
			begins(MSG(climb/start)), wait(CAP_PROC(climb_time)), on_interrupt(CAP_PROC(climb_interrupted)), then(CAP_PROC(climb_over)), says(CAP_PROC(done_message)), logs(LOG_GAME)))

/// The holder is climbable while it has the capability: the trait the old behaviour added.
/datum/capability/lib/climb/on_holder_init(datum/act/eval/A)
	add_trait(A.holder, TRAIT_CLIMBABLE, "capability_climb")

/datum/capability/lib/climb/on_holder_destroy(datum/act/eval/A)
	remove_trait(A.holder, TRAIT_CLIMBABLE, "capability_climb")

/// The mob dragged is the actor itself.
/datum/capability/lib/climb/proc/is_self_drag(datum/act/op/A)
	return isliving(A.held) && A.held == A.actor && A.held != A.holder

// ---- the rules ----

/// Why `climber` can't climb `holder` now: text (what to tell the climber) or a message type, or null when it can. Reads only.
/datum/capability/lib/climb/proc/refusal(atom/movable/holder, mob/living/climber)
	if(!istype(climber))
		return /datum/msg/climb/cant_now
	if(gate)
		var/why = call(holder, gate)(climber)
		if(why)
			return why
	if(climber.is_incorporeal())
		return /datum/msg/climb/phased
	if(isAI(climber))
		return /datum/msg/climb/no_hands
	if(climber.restrained() || climber.buckled_to())
		return /datum/msg/climb/hands_needed
	if(climber.stat || climber.lying || climber.has_status(STAT_PARALYZED) || climber.has_status(STAT_SLEEPING) || climber.has_status(STAT_WEAKENED))
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
	var/base = delay_by ? call(A.holder, delay_by)() : delay
	return issmall(A.actor) ? base * 0.6 : base

// ---- the climb ----

/// Where the climber ends up: what the holder's landing says, else its tile, or (a vaulted railing climbed from its own tile) the tile it faces.
/datum/capability/lib/climb/proc/landing_of(atom/movable/holder, mob/living/climber)
	if(landing)
		var/turf/chosen = call(holder, landing)(climber)
		if(chosen)
			return chosen
	if(vaulting && get_turf(climber) == get_turf(holder))
		return get_step(holder, holder.dir)
	return get_turf(holder)

/datum/capability/lib/climb/proc/climb_over(datum/act/op/A)
	var/atom/movable/holder = A.holder
	var/mob/living/climber = A.actor
	if(!istype(climber) || QDELETED(holder))
		return OP_FAILED
	var/turf/destination = landing_of(holder, climber)
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
	if(climbed && !QDELETED(holder))
		call(holder, climbed)(climber)
	return OP_OK

/// "You climb onto it" or "...over it", by where the climber ended up.
/datum/capability/lib/climb/proc/done_message(datum/act/op/A)
	return get_turf(A.actor) == get_turf(A.holder) ? /datum/msg/climb/onto : /datum/msg/climb/over

// ---- shaking climbers off ----

/// The climb was broken. When it was the structure that moved (the wait's keep on its tile broke), the climber is shaken off as if it had been shaken.
/datum/capability/lib/climb/proc/climb_interrupted(datum/act/op/A)
	var/datum/pending_op/P = A.pending
	var/atom/movable/holder = A.holder
	if(!P || !istype(holder) || QDELETED(holder) || !P.target_turf || get_turf(holder) == P.target_turf)
		return
	var/mob/living/climber = A.actor
	if(istype(climber))
		climb_topple(climber, holder)

/// The mobs climbing `holder` now: the actors of its waiting climb ops.
/proc/climbers_of(atom/movable/holder)
	READS_FROM() // who is climbing is the engine's record of waiting ops, never cached
	var/list/found = list()
	for(var/ref in GLOB.op_pending_all)
		var/datum/pending_op/P = GLOB.op_pending_all[ref]
		if(!P || !P.active || QDELETED(P) || P.holder != holder || !istype(P.cap, /datum/capability/lib/climb))
			continue
		if(P.actor)
			found += P.actor
	return found

/// Shakes `holder`: whoever is climbing it falls off (knocked down, the climb ends, a quarter of the time they land hard). `shaker` is who shook it, or
/// null (a crate opening, a solar panel breaking, the holder moving); someone shaking a structure nobody climbs, or one they climb themselves, shakes nothing.
/proc/climb_shake_off(atom/movable/holder, mob/shaker)
	var/list/climbers = climbers_of(holder)
	if(!length(climbers))
		return
	if(shaker)
		if(shaker in climbers)
			return
		act_message(shaker, holder, MSG_SELF(span_notice("You shake %T%.")), MSG_OTHERS(span_warning("%U% shakes %T%.")))
	for(var/mob/living/M in climbers)
		if(!climb_topple(M, holder))
			continue
		log_world("CLIMB: [M] shaken off [holder] by [shaker || "nobody"]")
		for(var/datum/pending_op/P as anything in op_pendings_of(M))
			if(P.holder == holder && istype(P.cap, /datum/capability/lib/climb))
				P.cancel(null)

/// `M` falls off `holder`: knocked down, and a quarter of the time they land hard. FALSE when they are left alone (not solid, already down, pulling it).
/proc/climb_topple(mob/living/M, atom/movable/holder)
	if(M.is_incorporeal())
		return FALSE
	if(M.lying) // no spamming this on people
		return FALSE
	if(M.pulling_target() == holder) // pulling stuff up stairs can get weird
		return FALSE
	M.status_at_least(STAT_WEAKENED, 3)
	to_chat(M, span_danger("You topple as you are shaken off \the [holder]!"))
	if(prob(25))
		climb_tumble(M)
	return TRUE

/// A climber who fell hard: simple mobs are hurt as a whole, a human on one limb.
/proc/climb_tumble(mob/living/M)
	var/damage = rand(10, 20)
	var/mob/living/carbon/human/H = M
	if(!istype(H))
		to_chat(M, span_danger("You land heavily!"))
		M.injure(INJURY_BLUNT, damage)
		return
	var/obj/item/organ/external/affecting = H.get_organ(pick(BP_ALL))
	if(affecting)
		to_chat(H, span_danger("You land heavily on your [affecting.name]!"))
		H.injure(INJURY_BLUNT, damage, affecting.organ_tag)
		return
	to_chat(H, span_danger("You land heavily!"))
	H.injure(INJURY_BLUNT, damage)

// ---- what stands on the tile ----

/// Checks if something is blocking our climb destination, ignores climbable objects
/proc/can_climb_turf(obj/climbed_thing)
	READS_FROM() // what stands on a tile is asked when a choice is made, never cached
	var/turf/T = get_turf(climbed_thing)
	if(!T || !istype(T))
		return "empty void"
	if(T.density)
		return T
	for(var/obj/O in turf_contents_of_type(T, /obj))
		if(O && O.density && !(O.flags & ON_BORDER) && !has_trait(O,TRAIT_CLIMBABLE)) //ON_BORDER structures are handled by the Adjacent() check.
			return O
	return 0

/// Check if the destination turf for vaulting is blocked by something. Extremely similar to above.
/proc/can_climb_neighbor_turf(obj/climbed_thing)
	var/turf/T = get_step(climbed_thing, climbed_thing.dir)
	if(!T || !istype(T))
		return 0
	if(T.density == 1)
		return T
	for(var/obj/O in turf_contents_of_type(T, /obj))
		if(O && O.density && !(O.flags & ON_BORDER && !(turn(O.dir, 180) & climbed_thing.dir)) && !has_trait(O,TRAIT_CLIMBABLE))
			return O
	return 0
