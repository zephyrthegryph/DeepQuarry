// buckle(slots, delay, restrained) (doc/rewrite/final_api.html, section 11 "The library", Structures; section 16): a structure a mob can be buckled to, a
// chair, a bed, a pipe. The ops, all keyed "buckle.<name>":
//
//   buckle_self   a mob dragged onto the structure by itself sits on it at once
//   buckle_drag   a mob dragged onto it by someone else is buckled after a wait
//   buckle_grab   a hand holding a grab (the held mob) used on it: the same wait
//   unbuckle      an empty hand on it frees the one buckled to it, or asks which of several
//
//   CAPABILITIES(/obj/structure/bed/chair, buckle())
//   CAPABILITIES(/obj/structure/bed/sofa, buckle(slots = 3, delay = 3 SECONDS))
//   CAPABILITIES(/obj/structure/pipe_clamp, buckle(restrained = TRUE))        a pipe takes only a restrained mob
//
//   slots       most mobs buckled at once
//   delay       how long buckling someone else takes (themselves, none)
//   restrained  the mob must be restrained (handcuffed) to be buckled
//   smallest    the smallest mob_size the seat takes (a number, or the name of a var of the holder: a wheelchair's min_mob_buckle_size)
//   largest     the largest mob_size it takes (the same)
//
// A seat that is full still takes a predator who sits down on it when the one on it can be eaten by them (can_stumble_vore): the occupant is freed and the
// predator swallows them where they sit, as the old buckling did. A thing the holder is pulling is let go of when it is buckled to the holder.
//
// What is buckled to what is the sparse declared link LK_BUCKLED_TO / LK_BUCKLED_MOBS (links() in CAPABILITIES(/atom/movable)): buckle_link() and unbuckle_mob() write it, the
// link's own hooks do the rest (the direction, the buckled alert, the riding offsets) and drop the edge if the mob ends up off the structure's tile,
// and handle_buckled_mob_movement() carries the occupants when the structure moves. Every effect here goes through those two procs, so a structure
// that has this capability moves its occupants, frees them when it is destroyed and answers M.buckled_to() the way the old system did. The capability
// adds the ops, the rules (written as requirements, which a menu and an AI read too) and the world actions: ACT_TRY(holder, buckle, M) before the
// relation is written, and its notice (buckled / unbuckled) after, so a hook can veto or react.
//
// The rules the capability reads are its own settings above, not the holder's can_buckle / max_buckled_mobs vars (they stay for the types not converted).
// The seats are declared as the slot SLOT_BUCKLE (not wired to the containment ledger yet, as interior's is not).

MSG_DEF(buckle/self, "You buckle yourself to %T%.", "%U% buckles %THEMSELVES% to %T%.")
MSG_DEF(buckle/other, "You buckle %I% to %T%.", "%U% buckles %I% to %T%.")
MSG_DEF(buckle/grabbed, "You buckle the one you are holding to %T%.", "%U% buckles the one they are holding to %T%.")
MSG_DEF_SELF(buckle/full, "There is no room left on it.")
MSG_DEF_SELF(buckle/nobody, "Nobody is buckled to it.")
MSG_DEF_SELF(buckle/nobody_to_buckle, "You aren't holding anyone.")
MSG_DEF_SELF(buckle/not_here, "They are not next to it.")
MSG_DEF_SELF(buckle/restrained_only, "It only takes someone who is restrained.")
MSG_DEF_SELF(buckle/seated, "They are already buckled to something.")
MSG_DEF_SELF(buckle/seated_here, "They are already buckled to it.")
MSG_DEF_SELF(buckle/held_by_others, "They are held by someone else.")
MSG_DEF_SELF(buckle/pinned, "They are pinned down.")
MSG_DEF_SELF(buckle/itself, "It can't be buckled to itself.")
MSG_DEF_SELF(buckle/too_small, "They are too small to use it.")
MSG_DEF_SELF(buckle/too_large, "They are too large to use it.")

CAPABILITY_TYPE(buckle, CAP_BUCKLE, /datum/capability/lib/buckle, key = NONE, slots = 1, delay = 1.5 SECONDS, restrained = FALSE, smallest = null, largest = null)

/datum/capability/lib/buckle

/datum/capability/lib/buckle/entries()
	var/list/who = list(req_bool(CAP_PROC(can_buckle_victim), because = CAP_PROC(why_not)))
	return list(
		slot(SLOT_BUCKLE, accepts = list(/mob/living), capacity = slots),
		examine_line(CAP_PROC(seated_line), when = CAP_PROC(has_occupants)),
		op("buckle_self", item(/mob/living), gesture(GESTURE_DRAG), by(0), when(CAP_PROC(is_self_drag)), label("Buckle"), \
			needs(who), then(CAP_PROC(buckle_victim)), says(MSG(buckle/self)), plays(SFX_EFFECTS_SEATBELT), logs(LOG_GAME)),
		op("buckle_drag", item(/mob/living), gesture(GESTURE_DRAG), priority(above("buckle.buckle_self")), when(CAP_PROC(is_other_drag)), label("Buckle"), \
			needs(who), wait(delay), then(CAP_PROC(buckle_victim)), says(MSG(buckle/other)), plays(SFX_EFFECTS_SEATBELT), logs(LOG_GAME)),
		op("buckle_grab", item(/obj/item/grab), when(CAP_PROC(holds_someone)), label("Buckle"), \
			needs(who), wait(delay), then(CAP_PROC(buckle_victim)), says(MSG(buckle/grabbed)), plays(SFX_EFFECTS_SEATBELT), logs(LOG_GAME)),
		op("unbuckle", hand(), when(CAP_PROC(has_occupants)), label("Unbuckle"), \
			asks(/datum/prompt/choice, fields = list("question" = "Who do you wish to unbuckle?", "choices" = computed(CAP_PROC(occupant_names))), when = CAP_PROC(has_several)), \
			needs(req_bool(CAP_PROC(has_occupants), because = MSG(buckle/nobody))), then(CAP_PROC(unbuckle_chosen)), plays(SFX_EFFECTS_SEATBELT), logs(LOG_GAME)))

// ---- who is being buckled ----

/// The mob an op buckles: the dragged mob, or the one a held grab holds. Null when it is neither.
/datum/capability/lib/buckle/proc/victim_of(datum/act/op/A)
	var/obj/item/held = A.held
	if(isliving(held))
		return held
	var/obj/item/grab/G = held
	if(istype(G))
		return G.grab_target()
	return null

/// The mob dragged is the actor.
/datum/capability/lib/buckle/proc/is_self_drag(datum/act/op/A)
	return isliving(A.held) && A.held == A.actor && A.held != A.holder

/// The mob dragged is someone else (never the structure itself).
/datum/capability/lib/buckle/proc/is_other_drag(datum/act/op/A)
	return isliving(A.held) && A.held != A.actor && A.held != A.holder

/// A grab is in hand: the click is a buckle whether or not anyone is in it (the refusal says so).
/datum/capability/lib/buckle/proc/holds_someone(datum/act/op/A)
	return istype(A.held, /obj/item/grab)

// ---- the rules: one read, used by the requirement and its reason ----

/// Why `victim` can't be buckled to `holder` now: the reason (a message type), or null when it can. Reads only.
/datum/capability/lib/buckle/proc/refusal(atom/movable/holder, mob/living/victim, mob/actor)
	if(!istype(victim))
		return /datum/msg/buckle/nobody_to_buckle
	if(victim == holder)
		return /datum/msg/buckle/itself
	if(victim.buckled_to() == holder)
		return /datum/msg/buckle/seated_here
	if(victim.buckled_to())
		return /datum/msg/buckle/seated
	if(LAZYLEN(victim.pinned))
		return /datum/msg/buckle/pinned
	if(restrained && !victim.restrained())
		return /datum/msg/buckle/restrained_only
	for(var/obj/item/grab/grip as anything in victim.grabbed_by_list())
		if(grip.grab_assailant() != actor)
			return /datum/msg/buckle/held_by_others
	var/small = setting(holder, smallest)
	if(!isnull(small) && victim.mob_size < small)
		return /datum/msg/buckle/too_small
	var/large = setting(holder, largest)
	if(!isnull(large) && victim.mob_size > large)
		return /datum/msg/buckle/too_large
	if(length(holder.buckled_mob_list()) >= slots && !length(swallowed_by(holder, victim)))
		return /datum/msg/buckle/full
	if(!(victim.Adjacent(holder) || victim.loc == holder.loc))
		return /datum/msg/buckle/not_here
	return null

/// A setting: the value written in the declaration, or what the holder's var of that name says now.
/datum/capability/lib/buckle/proc/setting(atom/holder, value)
	if(istext(value))
		value = holder.vars[value]
	return value

/// The occupants a predator sitting down on a full seat would eat (none when the seat has room or the sitter is no predator).
/datum/capability/lib/buckle/proc/swallowed_by(atom/movable/holder, mob/living/victim)
	. = list()
	if(!is_vore_predator(victim) || !victim.vore_selected)
		return
	for(var/mob/living/L as anything in holder.buckled_mob_list())
		if(can_stumble_vore(prey = L, pred = victim))
			. += L

/datum/capability/lib/buckle/proc/can_buckle_victim(datum/act/op/A)
	return isnull(refusal(A.holder, victim_of(A), A.actor))

/datum/capability/lib/buckle/proc/why_not(datum/act/op/A)
	return refusal(A.holder, victim_of(A), A.actor) || /datum/msg/op/not_available

// ---- buckle ----

/// Buckles the victim: the world action first (a hook may veto it), then the relation, then the notice. A victim not on the structure's tile is put there.
/datum/capability/lib/buckle/proc/buckle_victim(datum/act/op/A)
	var/atom/movable/holder = A.holder
	var/mob/living/victim = victim_of(A)
	if(!istype(victim) || QDELETED(holder))
		return OP_FAILED
	GLOB.act_next_actor = A.actor
	var/datum/act/buckle/B = ACT_TRY(holder, buckle, victim)
	GLOB.act_next_actor = null
	if(isnull(B))
		A.reason = GLOB.act_last_reason || /datum/msg/op/not_available
		log_world("BUCKLE: [victim] to [holder] refused or taken over ([A.reason])")
		return OP_REFUSED
	if(victim.loc != holder.loc)
		victim.forceMove(get_turf(holder))
	link_break(holder, LK_PULLING, victim) // a seat that was pulling the one who sits down lets go (a wheelchair)
	var/list/eaten = length(holder.buckled_mob_list()) >= slots ? swallowed_by(holder, victim) : list()
	for(var/mob/living/L as anything in eaten)
		holder.unbuckle_mob(L, TRUE)
		if(victim == A.actor)
			act_message(victim, L, others = span_warning("%U% sits down on %T%!"))
		else
			act_message(A.actor, victim, others = span_warning("%T% is forced to sit down on [L.name] by %U%!"))
		victim.begin_instant_nom(A.actor, L, victim, victim.vore_selected)
	// The capability has done the checks, so the old can_buckle and max_buckled_mobs vars are not asked: the relation is written directly.
	var/linked = holder.buckle_link(victim)
	if(!linked)
		act_cancel(B)
		A.reason = /datum/msg/op/failed
		log_world("BUCKLE: [victim] to [holder] did not link")
		return OP_REFUSED
	if(A.actor)
		holder.add_fingerprint(A.actor)
	victim.reveal(TRUE, null)
	var/obj/item/grab/grip = A.held
	if(istype(grip) && !QDELETED(grip))
		consume(grip, A.actor) // the grab lets go: the mob is seated, not held
	act_done(B)
	return OP_OK

// ---- unbuckle ----

/// Examine: who is buckled to it.
/datum/capability/lib/buckle/proc/seated_line(datum/act/A)
	var/atom/movable/holder = A.holder
	var/list/names = list()
	for(var/mob/living/L as anything in holder.buckled_mob_list())
		names += "[L]"
	return span_notice("[english_list(names)] [length(names) > 1 ? "are" : "is"] buckled to it.")

/datum/capability/lib/buckle/proc/has_occupants(datum/act/A)
	var/atom/movable/holder = A.holder
	return istype(holder) && length(holder.buckled_mob_list()) > 0

/datum/capability/lib/buckle/proc/has_several(datum/act/A)
	var/atom/movable/holder = A.holder
	return istype(holder) && length(holder.buckled_mob_list()) > 1

/// Each occupant by the name the choice shows: a name two share is told apart with a number. Names to mobs.
/datum/capability/lib/buckle/proc/occupants_by_name(atom/movable/holder)
	var/list/by_name = list()
	for(var/mob/living/L as anything in holder.buckled_mob_list())
		var/label = "[L]"
		var/n = 2
		while(label in by_name)
			label = "[L] ([n++])"
		by_name[label] = L
	return by_name

/// The names the choice shows.
/datum/capability/lib/buckle/proc/occupant_names(datum/act/op/A)
	var/list/names = list()
	for(var/label in occupants_by_name(A.holder))
		names += label
	return names

/// The occupant the op frees: the only one, or the one the choice named.
/datum/capability/lib/buckle/proc/chosen_occupant(datum/act/op/A)
	var/atom/movable/holder = A.holder
	var/list/seated = holder.buckled_mob_list()
	if(length(seated) == 1)
		return seated[1]
	var/datum/prompt/R = A.answer
	var/list/by_name = occupants_by_name(holder)
	return R ? by_name[R.value] : null

/datum/capability/lib/buckle/proc/unbuckle_chosen(datum/act/op/A)
	var/atom/movable/holder = A.holder
	var/mob/living/occupant = chosen_occupant(A)
	if(!istype(occupant) || occupant.buckled_to() != holder)
		A.reason = /datum/msg/buckle/nobody
		return OP_REFUSED
	GLOB.act_next_actor = A.actor
	var/datum/act/unbuckle/U = ACT_TRY(holder, unbuckle, occupant)
	GLOB.act_next_actor = null
	if(isnull(U))
		A.reason = GLOB.act_last_reason || /datum/msg/op/not_available
		log_world("BUCKLE: [occupant] from [holder] refused or taken over ([A.reason])")
		return OP_REFUSED
	if(!holder.unbuckle_mob(occupant))
		act_cancel(U)
		A.reason = /datum/msg/op/failed
		return OP_REFUSED
	if(A.actor)
		holder.add_fingerprint(A.actor)
	if(occupant == A.actor)
		act_message(occupant, holder, MSG_SELF(span_notice("You unbuckle yourself from %T%.")), MSG_OTHERS(span_notice("%U% unbuckles %THEMSELVES% from %T%.")), MSG_BLIND(span_notice("You hear metal clanking.")))
	else
		act_message(A.actor, occupant, MSG_SELF(span_notice("You unbuckle %T% from [holder].")), MSG_OTHERS(span_notice("%U% unbuckles %T% from [holder].")), MSG_BLIND(span_notice("You hear metal clanking.")))
	act_done(U)
	return OP_OK
