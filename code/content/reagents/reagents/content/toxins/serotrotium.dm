/* Drugs */

/datum/reagent/serotrotium
	name = REAGENT_SEROTROTIUM
	id = REAGENT_ID_SEROTROTIUM
	description = "A chemical compound that promotes concentrated production of the serotonin neurotransmitter in humans."
	taste_description = "bitterness"
	scannable = SCANNABLE_ADVANCED
	reagent_state = LIQUID
	color = "#202040"
	metabolism = REM * 0.25
	overdose = REAGENTS_OVERDOSE
	wiki_flag = WIKI_SPOILER
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_MEDSCI

/datum/reagent/serotrotium
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA)

/datum/reagent/serotrotium/affect_blood(mob/living/carbon/M, alien, removed)
	if(prob(7))
		M.emote(pick("twitch", "drool", "moan", "gasp"))
	return
