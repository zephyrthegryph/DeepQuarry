/datum/reagent/bullvalene //This is for the third sap. It converts Brute Oxy and burn into slightly less toxins.
	// Converts injury into toxin: the toxin side is injured in medicine.dm.
	treatment_tags = list(
		TREAT_TISSUE_REPAIR = 0.3,
		TREAT_BURN_CARE = 0.3,
		TREAT_OXYGENATION = 0.2,
	)
	name = REAGENT_BULLVALENE
	id = REAGENT_ID_BULLVALENE
	description = "A catalytic chemical that can treat a wide variety of ailments at the cost of toxifying the host's body."
	taste_description = "sulfur"
	reagent_state = LIQUID
	color = "#163851"
	overdose = 8 //This many units starts killing you.
	scannable = 1 // Mechs can scan this ye
	metabolism = REM * 0.15 //Slow metabolism. This value was plucked out of nowhere. Can be changed.
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_DRUG

/datum/reagent/bullvalene
	immune_species_blood = SPECIES_TAG_BIT(IS_SLIME) | SPECIES_TAG_BIT(IS_DIONA)

/datum/reagent/bullvalene/affect_blood(mob/living/carbon/M, alien, removed)
	// Repair is the treatment_tags profile; the catalysis toxifies the host
	// while it has something to convert.
	if(M.injury_load(INJURY_CATEGORY_PHYSICAL) || M.injury_load(INJURY_CATEGORY_THERMAL) || M.oxygen_debt())
		M.injure(INJURY_TOXIN, 0.8, source = src)
