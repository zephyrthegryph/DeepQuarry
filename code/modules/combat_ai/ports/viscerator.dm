// Modern-AI port for /mob/living/simple_mob/mechanical/viscerator.
//
// Legacy AI was /datum/ai_holder/simple_mob/melee/evasive — adjacent strike,
// then juke into a random adjacent tile so it's hard to swat. The modern brain
// gets identical texture by combining melee_attack with evasive_juke.

/mob/living/simple_mob/mechanical/viscerator
	use_modern_ai = TRUE

/mob/living/simple_mob/mechanical/viscerator/get_ai_behaviors()
	var/static/list/L = list(
		/datum/ai_behavior/approach_threat,
		/datum/ai_behavior/melee_attack,
		/datum/ai_behavior/evasive_juke,
		/datum/ai_behavior/idle_wander,
	)
	return L
