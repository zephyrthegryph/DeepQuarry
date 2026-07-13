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
// Modern port: a custom target selector reproduces the "prefer edible, else random hostile"
// pick. scrubble_harry is the skittish, darty OFFENSE — it darts in to bite, recoils to a
// stand-off band, and repeats, pressing harder (biting more often) the more worn down the prey
// gets. It yields to the shared predation finisher (the same telegraphed tackle→pin→devour every
// predator uses) the moment the prey is downed, so the swallow is the escapable grapple and the
// payoff for grinding the prey down rather than an instant gulp on first contact.

/mob/living/simple_mob/vore/scrubble
	use_modern_ai = TRUE
	// Skittish: prey, not an on-sight aggressor. It only engages (to harry/eat)
	// targets it has reason to react to, picked by the selector below.
	ai_attack_on_sight = TRUE   // legacy holder was /hostile, so it does react

	/// world.time the scrubble may next dart in for a bite. Recoils to its stand-off band until
	/// then; the gap shrinks as the prey tires (see scrubble_harry), so a worn-down target gets
	/// harried frantically while a fresh one is only nipped at.
	var/scrubble_next_bite = 0

/mob/living/simple_mob/vore/scrubble/initialize_ai_brain()
	. = ..()
	if(. && ai_brain)
		ai_brain.vision_range = 5   // only reacts when something gets close

/mob/living/simple_mob/vore/scrubble/get_ai_behaviors()
	var/static/list/L = list(
		/datum/ai_behavior/predation,   // shared finisher: tackle→pin→devour once the prey is worn down
		/datum/ai_behavior/scrubble_harry,   // darty dart-in/bite/recoil offense (yields to the finisher)
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
// Harry — the scrubble's darty offense. It darts in to bite, recoils to a short stand-off band,
// and repeats, so the prey reads a skittish hit-and-run rather than a facetanking brawler. The
// gap between darts scales with how worn down the prey is: a fresh fighter is nipped at
// infrequently, but as it tires the scrubble presses harder and bites almost continuously, and
// stops recoiling so it stays on a downed target. The shared predation finisher (OVERRIDE) takes
// the slot the instant the prey is worn down and in reach — this behavior doesn't manage that
// hand-off; the brain's continuous selection preempts it automatically. Runs as an INTERRUPT so
// its skittish offense wins over idle wandering; the eat itself is the escapable predation grab.
// ---------------------------------------------------------------------------

#define SCRUBBLE_BAND_MIN 2          // recoil out to at least this far between darts
#define SCRUBBLE_BAND_MAX 4          // don't drift past this — close back to dart range
#define SCRUBBLE_BITE_GAP_CALM (2.5 SECONDS)   // fresh prey: timid, infrequent nips
#define SCRUBBLE_BITE_GAP_FRANTIC (6)          // worn-down prey: frantic, near-continuous bites

/datum/ai_behavior/scrubble_harry
	name = "scrubble harry"
	// NORMAL, not INTERRUPT: harrying is a standard combat decision, so the OVERRIDE predation
	// finisher outranks it and takes the slot the moment the prey is worn down. (INTERRUPT — 4 —
	// is the top class for true panic reactions and would wrongly beat the OVERRIDE — 3 — grab.)
	// It still outranks idle_wander (IDLE) so the scrubble harries rather than mills about.
	priority_class = DQ_BEHAVIOR_PRIORITY_NORMAL
	target_kind = DQ_TARGET_MOB
	eval_triggers = list(COMSIG_DQAI_TARGET_CHANGED, COMSIG_DQAI_DAMAGE_TAKEN)

/datum/ai_behavior/scrubble_harry/applicable_to(mob/living/owner)
	return istype(owner, /mob/living/simple_mob/vore/scrubble)

/datum/ai_behavior/scrubble_harry/evaluate(datum/ai_brain/brain, atom/source)
	if(!istype(brain.holder, /mob/living/simple_mob/vore/scrubble) || !brain.primary_threat)
		return null
	return DQAI_RESULT(100, brain.primary_threat)

/datum/ai_behavior/scrubble_harry/start(datum/ai_brain/brain, atom/target, atom/source)
	. = ..()
	return DQ_BEHAVIOR_CONTINUE

/// Deciseconds before the scrubble may dart in again, shrinking as the prey wears down.
/datum/ai_behavior/scrubble_harry/proc/bite_gap(mob/living/prey)
	var/frac = 1
	if(isliving(prey) && prey.max_stamina > 0)
		frac = clamp(prey.stamina / prey.max_stamina, 0, 1)
	// Fresh prey (frac 1) → the long calm gap; gassed prey (frac 0) → the frantic short one.
	return SCRUBBLE_BITE_GAP_FRANTIC + (SCRUBBLE_BITE_GAP_CALM - SCRUBBLE_BITE_GAP_FRANTIC) * frac

/datum/ai_behavior/scrubble_harry/tick(datum/ai_brain/brain, atom/target, atom/source)
	var/mob/living/simple_mob/vore/scrubble/S = brain.holder
	if(!istype(S) || QDELETED(target))
		return DQ_BEHAVIOR_FAILED
	if(!isliving(target))
		return DQ_BEHAVIOR_DONE
	var/mob/living/L = target
	S.face_atom(L)
	var/dist = get_dist(S, L)
	if(world.time >= S.scrubble_next_bite)
		// Dart-in: close to reach, bite, then arm the recoil. The bite routes through the normal
		// melee path so the player can parry/block it like any strike.
		if(dist <= 1)
			if(S.checkClickCooldown())
				dqai_pdbg(S, "HARRY", "bite (prey stamina [round(L.stamina)]/[L.max_stamina]) — next dart in [bite_gap(L)/10]s", L)
				S.attack_target(L)
				S.scrubble_next_bite = world.time + bite_gap(L)
		else if(world.time >= S.next_move)
			dq_ai_step_to(S, L)
		return DQ_BEHAVIOR_CONTINUE
	// Between darts. A worn-down prey is about to be tackled (or is on the finisher's brief
	// cooldown) — stay on it instead of recoiling. A fresh one gets the skittish dart-out.
	if(world.time < S.next_move)
		return DQ_BEHAVIOR_CONTINUE
	if(dq_prey_worn_down(L) && S.will_eat(L))
		if(dist > 1)
			dq_ai_step_to(S, L)
	else if(dist <= SCRUBBLE_BAND_MIN)
		var/turf/away = get_step_away(S, L)
		if(away && !away.density)
			dq_ai_step_to(S, away)
	else if(dist >= SCRUBBLE_BAND_MAX)
		dq_ai_step_to(S, L)
	return DQ_BEHAVIOR_CONTINUE

#undef SCRUBBLE_BAND_MIN
#undef SCRUBBLE_BAND_MAX
#undef SCRUBBLE_BITE_GAP_CALM
#undef SCRUBBLE_BITE_GAP_FRANTIC
