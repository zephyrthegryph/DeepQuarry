// Modern-AI port for /mob/living/simple_mob/hostile/blob/spore.
//
// Spores are fragile melee attackers tied to a blob factory; the legacy
// hostile/blob path gave them generic on-sight aggression. Modern brain
// matches that with melee + approach + retaliate; the blob's Life() proc
// handles infestation independently of the brain.

/mob/living/simple_mob/hostile/blob/spore
	use_modern_ai = TRUE

/mob/living/simple_mob/hostile/blob/spore/get_ai_behaviors()
	var/static/list/L = list(
		/datum/ai_behavior/threaten,
		/datum/ai_behavior/approach_threat,
		/datum/ai_behavior/melee_attack,
		/datum/ai_behavior/retaliate_to_attacker,
		/datum/ai_behavior/idle_wander,
	)
	return L
