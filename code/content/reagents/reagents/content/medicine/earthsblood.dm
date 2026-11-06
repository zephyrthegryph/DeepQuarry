/datum/reagent/earthsblood
	treatment_tags = list(
		TREAT_TISSUE_REPAIR = 0.6,
		TREAT_BURN_CARE = 0.6,
		TREAT_OXYGENATION = 0.5,
		TREAT_ANTITOXIN = 0.5,
		TREAT_GENETIC_REPAIR = 0.3,
	)
	name = REAGENT_EARTHSBLOOD
	id = REAGENT_ID_EARTHSBLOOD
	description = "A rare plant extract with immense, almost magical healing capabilities. Induces a potent psychoactive state, damaging neurons with prolonged use."
	taste_description = "honey and sunlight"
	reagent_state = LIQUID
	dermal_absorption = 0.25
	color = "#ffb500"
	overdose = REAGENTS_OVERDOSE * 0.50
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_DRUG
	scannable = SCANNABLE_BENEFICIAL

/datum/reagent/earthsblood/affect_blood(mob/living/carbon/M, alien, removed)
	// The healing is the treatment_tags profile; the Tithe is paid here.
	M.status_at_least(STAT_DRUGGED, 20)
	M.status_at_least(STAT_HALLUCINATING, 3)
	M.injure(INJURY_NEURAL, 1 * removed, source = src) //your life for your mind. The Earthmother's Tithe.
