// Modern-AI port for /mob/living/simple_mob/illusion.
//
// Legacy used /datum/ai_holder/simple_mob/inert/astar — a barely-active AI
// that pathfinds when given a destination by external code. The modern brain
// gets the same effect with an empty behavior list and ai_attack_on_sight off;
// external code can set brain.primary_threat or call brain.smart_step_toward
// for movement.

/mob/living/simple_mob/illusion
	use_modern_ai = TRUE
	ai_attack_on_sight = FALSE

/mob/living/simple_mob/illusion/get_ai_behaviors()
	var/static/list/L = list()  // intentionally empty — controlled externally
	return L
