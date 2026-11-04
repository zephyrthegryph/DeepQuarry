/datum/reagent/adrenaline
	// The code-blue drug: restarts electrical activity in a flatlined heart
	// and shrinks swollen airway tissue.
	treatment_tags = list(TREAT_VASOPRESSOR = 1.2, TREAT_STIMULANT = 0.3)
	name = REAGENT_ADRENALINE
	id = REAGENT_ID_ADRENALINE
	description = "Adrenaline is a hormone used as a drug to treat cardiac arrest and other cardiac dysrhythmias resulting in diminished or absent cardiac output."
	taste_description = "bitterness"
	reagent_state = LIQUID
	dermal_absorption = 0.2
	scannable = SCANNABLE_BENEFICIAL
	color = "#C8A5DC"
	mrate_static = TRUE
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_MEDSCI

/datum/reagent/adrenaline
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA) // P2-S13

/datum/reagent/adrenaline/affect_blood(mob/living/carbon/M, alien, removed)
	M.status_set(STAT_PARALYZED, 0)
	M.status_set(STAT_WEAKENED, 0)
	M.injure(INJURY_TOXIN, rand(3), source = src)
