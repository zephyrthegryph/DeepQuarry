///Trait state that gives negative effects when at low nutrition.
/datum/trait_state/diabetic
	var/nutrition_threshold = 200
	var/nutrition_weak = 100
	var/nutrition_danger = 50
	var/nutrition_critical = 25

/datum/trait_state/diabetic/life_tick()
	var/mob/living/living_guy = owner
	if(living_guy.nutrition > nutrition_threshold || isbelly(living_guy.loc))
		return
	if((living_guy.nutrition < nutrition_threshold) && prob(5))
		if(living_guy.nutrition > nutrition_weak)
			to_chat(living_guy, span_warning("You start to feel noticeably weak as your stomach rumbles, begging for more food. Maybe you should eat something to keep your blood sugar up"))
		else if(living_guy.nutrition > nutrition_danger)
			to_chat(living_guy, span_warning("You begin to feel rather weak, and your stomach rumbles loudly. You feel lightheaded and it's getting harder to think. You really need to eat something."))
		else if(living_guy.nutrition > nutrition_critical)
			to_chat(living_guy, span_danger("You're feeling very weak and lightheaded, and your stomach continously rumbles at you. You really need to eat something!"))
		else
			to_chat(living_guy,span_critical("You're feeling extremely weak and lightheaded. You feel as though you might pass out any moment and your stomach is screaming for food by now! You should really find something to eat!"))
	if((living_guy.nutrition < nutrition_weak) && prob(10))
		living_guy.status_at_least(EFFECT_CONFUSED, 10)
	if((living_guy.nutrition < nutrition_danger) && prob(25))
		living_guy.status_set(EFFECT_HALLUCINATING, min(30,living_guy.status_units(EFFECT_HALLUCINATING)+8))
	if((living_guy.nutrition < nutrition_critical) && prob(5))
		living_guy.status_set(EFFECT_DROWSY, min(100,living_guy.status_units(EFFECT_DROWSY)+30))

/// Trait system: low blood sugar.
/// One Life step per cycle while attached (doc/rewrite/om_retirement.md L1).
/datum/trait_state/diabetic/life_steps()
	return list(seq_step(PROC_REF(life_tick), after = list(LIFE_INPUT, "life_type_pre"), key = "life_trait_diabetic"))
