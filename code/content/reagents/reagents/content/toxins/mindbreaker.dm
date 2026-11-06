/datum/reagent/mindbreaker
	name = REAGENT_MINDBREAKER
	id = REAGENT_ID_MINDBREAKER
	scannable = SCANNABLE_DIFFICULT
	description = "A powerful hallucinogen that causes immediate, prolonged hallucinations in its users."
	taste_description = "sourness"
	reagent_state = LIQUID
	color = "#B31008"
	metabolism = REM * 4 //0.8 per second...This is an 'immediate effect' drug that you hit someone with and they have effects for a prolonged period after.
	overdose = REAGENTS_OVERDOSE
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_WEAPONS

/datum/reagent/mindbreaker
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA) // P2-S13
	species_strength = alist(IS_SLIME = 0.15) // ~1/6

/datum/reagent/mindbreaker/affect_blood(mob/living/carbon/M, alien, removed)
	var/drug_strength = 100
	if(M.species.chem_strength_tox > 0) //Closer to 0 means they're more resistant to toxins. Higher than 1 means they're weaker to toxins.
		drug_strength *= M.species.chem_strength_tox //Ex: If you have a CST of 0.01 (100x resistant) drug_strength would = 10000
	drug_strength *= species_mult(M)

	drug_strength = CLAMP(drug_strength, 0, 150) //Let's not have users be hallucinating more than 5 minutes.

	M.status_at_least(STAT_HALLUCINATING, drug_strength)
