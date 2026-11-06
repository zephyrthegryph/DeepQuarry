/datum/reagent/serotrotium/venom
	name = REAGENT_SEROTROTIUMV
	id = REAGENT_ID_SEROTROTIUMV
	description = "A chemical compound that promotes concentrated production of the serotonin neurotransmitter in humans. This appears to be a biologically produced form, resulting in a specifically toxic nature."
	taste_description = "chalky bitterness"
	filtered_organs = list(O_SPLEEN)
	supply_conversion_value = REFINERYEXPORT_VALUE_UNWANTED
	industrial_use = REFINERYEXPORT_REASON_BIOHAZARD

/datum/reagent/serotrotium/venom
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA) // P2-S13

/datum/reagent/serotrotium/venom/affect_blood(mob/living/carbon/M, alien, removed)
	if(prob(30))
		if(prob(25))
			M.emote(pick("shiver", "blink_r"))
		M.injure(INJURY_NEURAL, 0.2 * removed, source = src)
	return ..()
