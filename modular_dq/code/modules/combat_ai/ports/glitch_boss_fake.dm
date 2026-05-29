// Modern-AI port for /mob/living/simple_mob/glitch_boss_fake.
//
// The fake is just a ranged shooter that aggresses on sight — no special
// attacks, no boss state. Default factory would also work, but we declare
// the list explicitly to drop the legacy ai_holder_type entirely.

/mob/living/simple_mob/glitch_boss_fake
	use_modern_ai = TRUE

/mob/living/simple_mob/glitch_boss_fake/get_ai_behaviors()
	var/static/list/L = list(
		/datum/ai_behavior/threaten,
		/datum/ai_behavior/approach_threat,
		/datum/ai_behavior/ranged_attack,
		/datum/ai_behavior/retaliate_to_attacker,
		/datum/ai_behavior/idle_wander,
	)
	return L

/mob/living/simple_mob/glitch_boss_fake/get_ai_target_selectors()
	var/static/list/L = list(/datum/target_selector/prefer_players, /datum/target_selector/closest)
	return L
