/datum/reagent/condensedcapsaicin/venom
	name = REAGENT_CONDENSEDCAPSAICINV
	id = REAGENT_ID_CONDENSEDCAPSAICINV
	description = "A biological agent that acts similarly to pepperspray. This compound seems to be particularly cruel, however, capable of permeating the barriers of blood vessels."
	taste_description = "fire"
	color = "#B31008"
	filtered_organs = list(O_SPLEEN)
	wiki_flag = WIKI_SPOILER
	supply_conversion_value = REFINERYEXPORT_VALUE_UNWANTED
	industrial_use = REFINERYEXPORT_REASON_BIOHAZARD

/datum/reagent/condensedcapsaicin/venom
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA) // P2-S13

/datum/reagent/condensedcapsaicin/venom/affect_blood(mob/living/carbon/M, alien, removed)
	if(prob(50))
		M.injure(INJURY_TOXIN, 0.5 * removed, source = src)
	if(prob(50))
		M.apply_effect(4, AGONY, 0)
		if(prob(20))
			to_chat(M, span_danger("You feel like your insides are burning!"))
		else if(prob(20))
			act_message(M, null, others = span_warning("%U% [pick("dry heaves!","coughs!","splutters!","rubs at their eyes!")]"))
	else
		M.status_at_least(STAT_BLURRY, 10)
