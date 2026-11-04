// Quadcord's healing is its treatment_tags profile.

//tier 2


/datum/reagent/curea
	name = REAGENT_CUREA
	id = REAGENT_ID_CUREA
	description = "An experimental that removes many ailments, such as poison and stiffening of muscles via frost"
	taste_description = "bitterness"
	reagent_state = LIQUID
	color = "#660066"
	scannable = 1
	dermal_absorption = 1
	overdose = REAGENTS_OVERDOSE * 0.5
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_MEDSCI

/datum/reagent/curea/affect_blood(mob/living/carbon/M, alien, removed)
	M.mend(TREAT_ANTITOXIN, 100)
	M.remove_body_effect(/datum/body_effect/chilled)
	M.remove_body_effect(/datum/body_effect/doomed)
	M.remove_body_effect(/datum/body_effect/invulnerable)
	M.remove_body_effect(/datum/body_effect/elemental_vulnerability)
	M.remove_body_effect(/datum/body_effect/grievous_wounds)
	M.remove_body_effect(/datum/body_effect/deep_wounds)
	M.remove_body_effect(/datum/body_effect/hivebot_weaken)
	M.extinguish_mob()
	M.remove_body_effect(/datum/body_effect/berserk_exhaustion)
	M.remove_body_effect(/datum/body_effect/entangled)
	M.remove_body_effect_stack(/datum/body_effect/wizfire)
	M.remove_body_effect_stack(/datum/body_effect/wizpoison)
