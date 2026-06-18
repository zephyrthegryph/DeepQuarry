// Modern-AI port for /mob/living/simple_mob/vore/scrubble.
//
// The scrubble is a skittish ambush-prey predator. Its deleted AI lived on
// /datum/ai_holder/simple_mob/hostile/scrubble and did two unusual things:
//   * find_target() preferred EDIBLE mobs: it built the list of attackable
//     mobs, filtered to those it could vore, and picked a random edible one;
//     only if none were edible did it pick a random plain hostile.
//   * flee_from_target() inverted normal combat — the scrubble ALWAYS fled
//     (dying_threshold 1.1 ⇒ flees even at full health). But if it ended up
//     adjacent to a target it could pounce and eat, it would whirl around,
//     pounce, and swallow it. So: run away, but if you corner it (or it corners
//     you), it lunges and eats.
//   * vision_range 5 (only reacts up close), can_flee, base_wander_delay 2.
//
// Modern port: a custom target selector reproduces the "prefer edible, else
// random hostile" pick. One INTERRUPT behavior, scrubble_skitter, reproduces the
// always-flee-but-pounce-when-adjacent loop. PounceTarget / EatTarget / will_eat
// all still live on the mob and are reused unchanged.

/mob/living/simple_mob/vore/scrubble
	use_modern_ai = TRUE
	// Skittish: prey, not an on-sight aggressor. It only engages (to flee/pounce)
	// targets it has reason to react to, picked by the selector below.
	ai_attack_on_sight = TRUE   // legacy holder was /hostile, so it does react

/mob/living/simple_mob/vore/scrubble/initialize_ai_brain()
	. = ..()
	if(. && ai_brain)
		ai_brain.vision_range = 5   // only reacts when something gets close

/mob/living/simple_mob/vore/scrubble/get_ai_behaviors()
	var/static/list/L = list(
		/datum/ai_behavior/scrubble_skitter,
		/datum/ai_behavior/idle_wander,
	)
	return L

/mob/living/simple_mob/vore/scrubble/get_ai_target_selectors()
	var/static/list/L = list(
		/datum/target_selector/scrubble_prey,
		/datum/target_selector/closest,
	)
	return L

// ---------------------------------------------------------------------------
// Target selector — reproduce find_target()'s "prefer something I can eat,
// otherwise just pick any attackable mob" pick. Legacy used a random pick among
// the edible set; we mirror that with pick() to keep its skittish, non-fixated
// feel. Falls back to closest hostile when nothing is edible.
// ---------------------------------------------------------------------------

/datum/target_selector/scrubble_prey
	name = "scrubble prey"

/datum/target_selector/scrubble_prey/select(datum/ai_brain/brain, list/candidates)
	if(!length(candidates))
		return null
	var/mob/living/simple_mob/vore/scrubble/S = brain.holder
	if(!istype(S))
		var/datum/target_selector/closest_selector = dq_get_selector(/datum/target_selector/closest)
		return closest_selector.select(brain, candidates)
	var/list/edible = list()
	for(var/mob/living/M as anything in candidates)
		if(S.will_eat(M))
			edible += M
	if(length(edible))
		return pick(edible)
	// Nothing edible — still react to a plain hostile (so it can flee one).
	return pick(candidates)

// ---------------------------------------------------------------------------
// Skitter — the scrubble's whole combat loop. Always flee from the target, but
// when adjacent and able to pounce-and-eat, whirl around and devour it. Runs as
// an INTERRUPT so it always wins over wandering once a target exists.
// ---------------------------------------------------------------------------

/datum/ai_behavior/scrubble_skitter
	name = "scrubble skitter"
	priority_class = DQ_BEHAVIOR_PRIORITY_INTERRUPT
	target_kind = DQ_TARGET_MOB
	eval_triggers = list(COMSIG_DQAI_TARGET_CHANGED, COMSIG_DQAI_DAMAGE_TAKEN)

/datum/ai_behavior/scrubble_skitter/applicable_to(mob/living/owner)
	return istype(owner, /mob/living/simple_mob/vore/scrubble)

/datum/ai_behavior/scrubble_skitter/evaluate(datum/ai_brain/brain, atom/source)
	var/mob/living/simple_mob/vore/scrubble/S = brain.holder
	if(!istype(S) || !brain.primary_threat)
		return null
	// Always engaged while a target exists (dying_threshold 1.1 ⇒ always flee).
	return DQAI_RESULT(100, brain.primary_threat)

/datum/ai_behavior/scrubble_skitter/start(datum/ai_brain/brain, atom/target, atom/source)
	. = ..()
	return DQ_BEHAVIOR_CONTINUE

/datum/ai_behavior/scrubble_skitter/tick(datum/ai_brain/brain, atom/target, atom/source)
	var/mob/living/simple_mob/vore/scrubble/S = brain.holder
	if(!istype(S) || QDELETED(target))
		return DQ_BEHAVIOR_FAILED
	if(!isliving(target))
		return DQ_BEHAVIOR_DONE
	var/mob/living/L = target
	// Cornered / on top of edible prey → pounce and eat (legacy adjacency branch).
	if(get_dist(S, L) <= 1)
		if(S.will_eat(L) && S.CanPounceTarget(L))
			S.face_atom(L)
			S.PounceTarget(L)
			return DQ_BEHAVIOR_DONE   // ate it (or whiffed); re-evaluate next tick
	// Otherwise keep bolting away (legacy step_away distance 7).
	var/turf/away = get_step_away(S, L, 7)
	if(away && !away.density)
		step_to(S, away)
	return DQ_BEHAVIOR_CONTINUE
