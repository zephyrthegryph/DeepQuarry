/datum/reagent/salmonella
	name = REAGENT_SALMONELLA
	id = REAGENT_ID_SALMONELLA
	scannable = SCANNABLE_ADVANCED
	description = "A nasty bacteria found in spoiled food."
	reagent_state = LIQUID
	color = "#1E4600"
	taste_mult = 0
	wiki_flag = WIKI_SPOILER
	supply_conversion_value = REFINERYEXPORT_VALUE_NO
	industrial_use = REFINERYEXPORT_REASON_BIOHAZARD

/datum/reagent/salmonella/on_mob_life(mob/living/carbon/M)
	M.force_contagion(new /datum/affliction/contagion/food_poisoning(0))
	return ..()
