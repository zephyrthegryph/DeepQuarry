// Fluffball port — restores the skittish "flee everything, tail-pounce when
// cornered" behavior from the deleted
// /datum/ai_holder/simple_mob/hostile/fluffball.
//
// Legacy flavor, faithfully reconstructed:
//   * Anxious prey-animal: not an on-sight aggressor. It flees from any nearby
//     creature (vision_range was a tight 3). It does NOT flee from anyone who
//     just gave it food (the gift-friend list) — that survives as a personal
//     FRIENDLY entry set in the mob's attackby (already in fluffball.dm), and
//     friendlies aren't in the brain's visible_hostiles, so they never trigger
//     a flee.
//   * When a fleer gets cornered (adjacent), it whirls and tail-pounces, which
//     swallows edible prey. The mob's own PounceTarget override handles the
//     eat; this port just calls it when adjacent, mirroring flee_from_target().
//   * People CARRYING food are ignored (the legacy find_target skipped targets
//     holding a food item). Reproduced in the flee behavior's candidate filter.
//
// Net effect: a fluffball runs away from you, and if you trap it against a
// wall it tail-whips/eats you, unless you're holding food — then it's calm.

/mob/living/simple_mob/vore/fluffball
	// Not an on-sight predator; it reacts to proximity by fleeing, not chasing.
	ai_attack_on_sight = FALSE

/mob/living/simple_mob/vore/fluffball/get_ai_behaviors()
	var/static/list/L = list(
		/datum/ai_behavior/predation/pounce,    // cornered eat = the escapable grab, not an instant swallow
		/datum/ai_behavior/fluffball_flee_pounce,
		/datum/ai_behavior/retaliate_to_attacker,
		/datum/ai_behavior/idle_wander,
		/datum/ai_behavior/idle_speak,
	)
	return L

// ---------------------------------------------------------------------------
// Flee + corner-pounce.
//
// The brain's visible_hostiles only contains mobs it's disposed to engage. A
// passive fluffball has no on-sight hostiles, so we scan view() directly for
// any nearby creature to be scared of, the way the legacy holder did. We skip
// food-carriers (calming) and gift-friends (FRIENDLY personal entries).
// ---------------------------------------------------------------------------

/datum/ai_behavior/fluffball_flee_pounce
	name = "skittish flee"
	// NORMAL, not INTERRUPT: the OVERRIDE predation/pounce must outrank fleeing so a cornered
	// fluffball commits the grab. (INTERRUPT — 4 — would beat OVERRIDE — 3 — and the corner-grab
	// would never fire; the scrubble has the same note.)
	priority_class = DQ_BEHAVIOR_PRIORITY_NORMAL
	target_kind = DQ_TARGET_MOB
	no_threat_required = TRUE
	/// How close another creature has to be to spook the fluffball.
	var/spook_range = 3
	/// How far it tries to flee.
	var/flee_distance = 5

/datum/ai_behavior/fluffball_flee_pounce/applicable_to(mob/living/owner)
	return istype(owner, /mob/living/simple_mob/vore/fluffball)

/// Find the nearest creature the fluffball should flee from. Skips food-carriers
/// and anyone it's friendly toward (gift-givers, faction-mates).
/datum/ai_behavior/fluffball_flee_pounce/proc/find_scary(datum/ai_brain/brain)
	var/mob/living/simple_mob/vore/fluffball/F = brain.holder
	if(!istype(F))
		return null
	var/mob/living/best = null
	var/best_dist = INFINITY
	for(var/mob/living/L in dview(spook_range, F)) // dview: senses prey in unlit caves, like the perception layer
		if(L == F || L.stat >= DEAD)
			continue
		// Calm around food-bearers — they might feed it.
		if(ishuman(L))
			var/mob/living/carbon/human/H = L
			if(istype(H.get_active_hand(), /obj/item/reagent_containers/food) || istype(H.get_inactive_hand(), /obj/item/reagent_containers/food))
				continue
		// Friendly toward us (gift-giver / faction-mate)? Not scary.
		if(brain.disposition_to(L) >= DQ_DISPOSITION_FRIENDLY)
			continue
		var/d = get_dist(F, L)
		if(d < best_dist)
			best_dist = d
			best = L
	return best

/datum/ai_behavior/fluffball_flee_pounce/evaluate(datum/ai_brain/brain, atom/source)
	// Pure scoring — no side effects. The fright is published to brain.primary_threat in tick() so
	// the OVERRIDE predation/pounce can read it and preempt this (NORMAL) flee the instant the
	// fluffball is cornered adjacent to edible prey.
	var/mob/living/scary = find_scary(brain)
	if(!scary)
		return null
	return DQAI_RESULT(80, scary)

/datum/ai_behavior/fluffball_flee_pounce/start(datum/ai_brain/brain, atom/target, atom/source)
	var/mob/living/owner = brain.get_owner()
	if(!owner || !target)
		return DQ_BEHAVIOR_FAILED
	owner.face_atom(target)
	return DQ_BEHAVIOR_CONTINUE

/datum/ai_behavior/fluffball_flee_pounce/tick(datum/ai_brain/brain, atom/target, atom/source)
	var/mob/living/simple_mob/vore/fluffball/F = brain.holder
	if(!istype(F) || QDELETED(target) || !isliving(target))
		return DQ_BEHAVIOR_FAILED
	var/mob/living/prey = target
	// Re-check that this creature is still worth fearing; otherwise calm down.
	if(prey.stat >= DEAD || get_dist(F, prey) > F.ai_brain?.vision_range)
		return DQ_BEHAVIOR_DONE
	// Publish the fright as our threat so the OVERRIDE predation/pounce grabs it the moment we're
	// cornered adjacent to edible prey (it reads brain.primary_threat); until then we just run.
	brain.primary_threat = prey
	// Flee ONE throttled, glided step away — not raw step_away(…, distance), which jumps several
	// tiles every 250ms tick and reads as teleporting.
	var/turf/away = get_step_away(F, prey)
	if(away && !away.density)
		dq_ai_step_to(F, away)
	F.face_atom(prey)
	return DQ_BEHAVIOR_CONTINUE
