// Modern-AI port for /mob/living/simple_mob/humanoid/possessed.
//
// Legacy AI was /datum/ai_holder/simple_mob/merc — a hostile humanoid combatant
// using A* and post-attack juke. Modern brain provides the same texture via
// approach (A* through smart_step_toward) + melee + evasive_juke + flee +
// scavenge_weapon for the hands.

/mob/living/simple_mob/humanoid/possessed
	use_modern_ai = TRUE

/mob/living/simple_mob/humanoid/possessed/get_ai_behaviors()
	var/static/list/L = list(
		/datum/ai_behavior/threaten,
		/datum/ai_behavior/approach_threat,
		/datum/ai_behavior/melee_attack,
		/datum/ai_behavior/evasive_juke,
		/datum/ai_behavior/maul_unconscious,
		/datum/ai_behavior/retaliate_to_attacker,
		/datum/ai_behavior/scavenge_weapon,
		/datum/ai_behavior/call_for_help,
		/datum/ai_behavior/flee_low_hp,
		/datum/ai_behavior/idle_wander,
	)
	return L
