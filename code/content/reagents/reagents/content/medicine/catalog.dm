/* General medicine */

/datum/reagent/inaprovaline
	// The station's resuscitation stabiliser (and the AllergyPen's payload):
	// a weaker vasopressor on top of circulatory support.
	treatment_tags = list(TREAT_CIRCULATORY = 1.0, TREAT_VASOPRESSOR = 0.5)
	factors = alist(STAT_ANALGESIA = 10, STAT_STABILIZATION = 15, STAT_ALLERGY = -5)
	species_factors = alist(IS_DIONA = null)
	name = REAGENT_INAPROVALINE
	id = REAGENT_ID_INAPROVALINE
	description = REAGENT_INAPROVALINE + " is a synaptic stimulant and cardiostimulant. Commonly used to stabilize patients. Also counteracts allergic reactions."
	taste_description = "bitterness"
	reagent_state = LIQUID
	color = "#00BFFF"
	overdose = REAGENTS_OVERDOSE * 2
	metabolism = REM * 0.2
	dermal_absorption = 0.2
	scannable = SCANNABLE_BENEFICIAL
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_DRUG

/datum/reagent/inaprovaline/topical
	factors = alist(STAT_ANALGESIA = 12, STAT_STABILIZATION = 20, STAT_ALLERGY = -5)
	name = REAGENT_INAPROVALAZE
	id = REAGENT_ID_INAPROVALAZE
	description = REAGENT_INAPROVALAZE + " is a topical variant of Inaprovaline."
	taste_description = "bitterness"
	reagent_state = LIQUID
	color = "#00BFFF"
	overdose = REAGENTS_OVERDOSE * 2
	metabolism = REM * 0.2
	scannable = SCANNABLE_BENEFICIAL
	touch_met = REM * 0.3
	can_overdose_touch = TRUE
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_SPECIALDRUG

/datum/reagent/inaprovaline/topical
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA) // P2-S13

/datum/reagent/inaprovaline/topical/affect_blood(mob/living/carbon/M, alien, removed)
	M.injure(INJURY_TOXIN, 2 * removed, source = src)

/datum/reagent/calciumcarbonate
	factors = alist(STAT_ANTIEMETIC = 3)
	species_factors = alist(IS_DIONA = null)
	name = REAGENT_CALCIUMCARBONATE
	id = REAGENT_ID_CALCIUMCARBONATE
	description = "Calcium carbonate is a calcium salt commonly used as an antacid."
	taste_description = "chalk"
	reagent_state = SOLID
	dermal_absorption = 0 //Solids don't penetrate.
	color = "#eae6e3"
	overdose = REAGENTS_OVERDOSE * 0.8
	metabolism = REM * 0.4
	scannable = SCANNABLE_BENEFICIAL
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_DRUG

/datum/reagent/calciumcarbonate
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA) // P2-S13

/datum/reagent/calciumcarbonate/affect_blood(mob/living/carbon/M, alien, removed) // Why would you inject this.
	M.injure(INJURY_TOXIN, 3 * removed, source = src)

/datum/reagent/kelotane
	treatment_tags = list(TREAT_BURN_CARE = 0.6)
	name = REAGENT_KELOTANE
	id = REAGENT_ID_KELOTANE
	description = REAGENT_KELOTANE + " is a drug used to treat burns."
	taste_description = "bitterness"
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#FFA800"
	overdose = REAGENTS_OVERDOSE
	scannable = SCANNABLE_BENEFICIAL
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_DRUG
	medallergen_type = MEDALLERGEN_KELOTANE
	// Burn care is the treatment_tags profile. Mends burns, but has negative effects with a Promethean's skeletal structure.
	species_injuries_blood = alist(IS_SLIME = alist(INJURY_BLUNT = 2))

/datum/reagent/dermaline
	treatment_tags = list(TREAT_BURN_CARE = 1.0, TREAT_THERMOREGULATION = 0.2)
	id = REAGENT_ID_DERMALINE
	name = REAGENT_DERMALINE
	description = REAGENT_DERMALINE + " is the next step in burn medication. Works twice as good as kelotane and enables the body to restore even the direst heat-damaged tissue."
	taste_description = "bitterness"
	taste_mult = 1.5
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#FF8000"
	overdose = REAGENTS_OVERDOSE * 0.5
	scannable = SCANNABLE_BENEFICIAL
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_DRUG
	medallergen_type = MEDALLERGEN_KELOTANE

/datum/reagent/dermaline/topical
	// Dermalaze: stronger topical burn care (a distinct profile, so it treats).
	treatment_tags = list(TREAT_BURN_CARE = 1.3, TREAT_THERMOREGULATION = 0.2)
	name = REAGENT_DERMALAZE
	id = REAGENT_ID_DERMALAZE
	description = REAGENT_DERMALAZE + " is a topical variant of the chemical Dermaline."
	taste_description = "bitterness"
	taste_mult = 1.5
	reagent_state = LIQUID
	color = "#FF8000"
	overdose = REAGENTS_OVERDOSE * 0.4
	scannable = SCANNABLE_BENEFICIAL
	touch_met = REM * 0.75
	can_overdose_touch = TRUE
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_SPECIALDRUG
	medallergen_type = MEDALLERGEN_KELOTANE

/datum/reagent/dermaline/topical
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA) // P2-S13

/datum/reagent/dermaline/topical/affect_blood(mob/living/carbon/M, alien, removed)
	M.injure(INJURY_TOXIN, 2 * removed, source = src)

/datum/reagent/ryetalyn
	treatment_tags = list(TREAT_GENETIC_REPAIR = 0.5)
	name = REAGENT_RYETALYN
	id = REAGENT_ID_RYETALYN
	description = REAGENT_RYETALYN + " can cure DNA, Cloning, and genetic damage via a catalytic process."
	taste_description = "acid"
	reagent_state = SOLID
	dermal_absorption = 0
	scannable = SCANNABLE_BENEFICIAL
	color = "#004000"
	overdose = REAGENTS_OVERDOSE
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_CLONEDRUG

/datum/reagent/hyronalin
	treatment_tags = list(TREAT_ANTIRADIATION = 0.5)
	name = REAGENT_HYRONALIN
	id = REAGENT_ID_HYRONALIN
	description = REAGENT_HYRONALIN + " is a medicinal drug used to counter the effect of radiation poisoning."
	taste_description = "bitterness"
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#408000"
	metabolism = REM * 0.25
	overdose = REAGENTS_OVERDOSE
	scannable = SCANNABLE_BENEFICIAL
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_SPECIALDRUG

/datum/reagent/hyronalin
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA) // P2-S13

/datum/reagent/hyronalin/affect_blood(mob/living/carbon/M, alien, removed)
	// B14: radiation purge is the TREAT_ANTIRADIATION tag (purge_radiation()).

/datum/reagent/leporazine
	treatment_tags = list(TREAT_THERMOREGULATION = 1.0)
	name = REAGENT_LEPORAZINE
	id = REAGENT_ID_LEPORAZINE
	description = "Leporazine can be use to stabilize an individuals body temperature."
	taste_description = "bitterness"
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#C8A5DC"
	overdose = REAGENTS_OVERDOSE
	scannable = SCANNABLE_BENEFICIAL
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_CLONEDRUG
	coolant_modifier = 0.5 // Okay substitute coolant

// This exists to cut the number of chemicals a merc borg has to juggle on their hypo.
/datum/reagent/healing_nanites
	// Nanites repair organic and synthetic parts alike.
	treatment_tags = list(
		TREAT_TISSUE_REPAIR = 0.4,
		TREAT_BURN_CARE = 0.4,
		TREAT_OXYGENATION = 0.3,
		TREAT_ANTITOXIN = 0.3,
		TREAT_GENETIC_REPAIR = 0.3,
		TREAT_PLATING_REPAIR = 0.4,
		TREAT_WIRING_REPAIR = 0.4,
	)
	name = REAGENT_HEALINGNANITES
	id = REAGENT_ID_HEALINGNANITES
	description = "Miniature medical robots that swiftly restore bodily damage."
	taste_description = "metal"
	reagent_state = SOLID
	color = "#555555"
	metabolism = REM * 4 // Nanomachines gotta go fast.
	scannable = SCANNABLE_BENEFICIAL
	affects_robots = TRUE
	wiki_flag = WIKI_SPOILER
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_DRUG

// Healing nanites' repair (organic and synthetic) is their treatment_tags profile.

/datum/reagent/menthol
	name = REAGENT_MENTHOL
	id = REAGENT_ID_MENTHOL
	description = "Tastes naturally minty, and imparts a very mild numbing sensation."
	taste_description = "mint"
	reagent_state = LIQUID
	color = "#80af9c"
	metabolism = REM * 0.002
	overdose = REAGENTS_OVERDOSE
	scannable = SCANNABLE_BENEFICIAL
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_FOOD

/datum/reagent/tercozolam
	name = REAGENT_TERCOZOLAM
	id = REAGENT_ID_TERCOZOLAM
	scannable = SCANNABLE_BENEFICIAL
	color = "#afeb17"
	metabolism = 0.05
	dermal_absorption = 0.2
	description = "A well respected drug used for treatment of schizophrenia in specific."
	overdose = REAGENTS_OVERDOSE * 2
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_DRUG

/datum/reagent/alizene
	treatment_tags = list(TREAT_TISSUE_REPAIR = 1.5)
	name = REAGENT_ALIZENE
	id = REAGENT_ID_ALIZENE
	description = "A derivative from bicaridine enhanced by serazine to more effectively mend flesh, but is ineffective against internal hemorrhage."
	taste_description = "bittersweet"
	taste_mult = 3
	reagent_state = LIQUID
	color = "#b37979"
	overdose = REAGENTS_OVERDOSE
	scannable = 1
	dermal_absorption = 0.2
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_DRUG

/datum/reagent/vermicetol
	treatment_tags = list(TREAT_TISSUE_REPAIR = 1.3)
	name = REAGENT_VERMICETOL
	id = REAGENT_ID_VERMICETOL
	description = "A potent chemical that treats physical damage at an exceptional rate."
	taste_description = "sparkles"
	taste_mult = 3
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#750404"
	overdose = REAGENTS_OVERDOSE * 0.5
	scannable = SCANNABLE_BENEFICIAL
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_DRUG

// Vermicetol's trauma repair is its treatment_tags profile.

/*
/datum/reagent/sleevingcure
	name = REAGENT_SLEEVINGCURE
	id = REAGENT_ID_SLEEVINGCURE
	description = "A rare medication provided by Vey-Med that helps counteract negative side effects of using imperfect resleeving machinery."
	taste_description = "chocolate peanut butter"
	taste_mult = 2
	reagent_state = LIQUID
	color = "#b4dcdc"
	overdose = 5
	scannable = SCANNABLE_BENEFICIAL

	supply_conversion_value = REFINERYEXPORT_VALUE_RARE
	industrial_use = REFINERYEXPORT_REASON_DRUG

/datum/reagent/sleevingcure/affect_blood(mob/living/carbon/M, alien, removed)
	M.remove_body_effect_stack(/datum/body_effect/resleeving_sickness)
	M.remove_body_effect_stack(/datum/body_effect/faux_resleeving_sickness)
*/


/datum/reagent/prussian_blue //We don't have iodine, so prussian blue we go.
	treatment_tags = list(TREAT_ANTITOXIN = 0.1)
	name = REAGENT_PRUSSIANBLUE
	id = REAGENT_ID_PRUSSIANBLUE
	description = "Prussian Blue is a medication used to temporarily pause the effects of radiation poisoning to allow for treatment. Does not treat radiation sickness on its own."
	taste_description = "salt"
	reagent_state = SOLID
	dermal_absorption = 0.2 //While it /is/ a solid, it's a beneficial medical reagent that should have some use if put into a patch.
	color = "#003153" //Blue!
	metabolism = REM * 0.25//20 ticks to do things per unit injected. This means injecting 30u will give you 10 minutes to do what you need.
	overdose = REAGENTS_OVERDOSE
	scannable = SCANNABLE_BENEFICIAL
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_DRUG
	metabolized_traits = list(TRAIT_HALT_RADIATION_EFFECTS)

//Chemist expansion
//deathblood
/datum/reagent/cleansingagent
	treatment_tags = list(TREAT_ANTITOXIN = 0.8, TREAT_ANTIRADIATION = 0.5)
	name = REAGENT_CLEANSINGAGENT
	id = REAGENT_ID_CLEANSINGAGENT
	description = "An agent that purges one's body of toxins."
	reagent_state = LIQUID
	color = "#225722"
	scannable = 1
	dermal_absorption = 0.2
	overdose = REAGENTS_OVERDOSE
	overdose_mod = 0
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_MEDSCI

/datum/reagent/cleansingagent
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA)

/datum/reagent/cleansingagent/affect_blood(mob/living/carbon/M, alien, removed)
	// Antitoxin action is the treatment_tags profile.
	M.status_at_least(STAT_DRUGGED, 5)

/datum/reagent/purifyingagent
	treatment_tags = list(TREAT_ANTITOXIN = 0.8, TREAT_ANTIRADIATION = 0.5)
	name = REAGENT_PURIFYINGAGENT
	id = REAGENT_ID_PURIFYINGAGENT
	description = "An agent that purges one's body of rads and toxins."
	reagent_state = LIQUID
	color = "#225722"
	scannable = 1
	dermal_absorption = 0.2
	overdose = REAGENTS_OVERDOSE
	overdose_mod = 0
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_MEDSCI

//neoliquidfire
/datum/reagent/neotane
	treatment_tags = list(TREAT_BURN_CARE = 1.5)
	name = REAGENT_NEOTANE
	id = REAGENT_ID_NEOTANE
	description = "An advancement of kelotane that scars and breaks apart the user's flesh to remove the burnt tissue."
	taste_description = "bitterness"
	reagent_state = LIQUID
	color = "#FF6600"
	overdose = REAGENTS_OVERDOSE * 0.2
	dermal_absorption = 0.2
	scannable = 1
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_MEDSCI

/datum/reagent/neotane
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA)
	species_injuries_blood = alist(IS_SLIME = alist(INJURY_BLUNT = 3))

/datum/reagent/neotane/affect_blood(mob/living/carbon/M, alien, removed)
	// Burn care is the treatment_tags profile; the side effects stay here.
	M.injure(INJURY_BLUNT, 1 * removed, source = src)

/datum/reagent/bloodsealer
	factors = alist(STAT_STABILIZATION = 25)
	species_factors = alist(IS_DIONA = null)
	name = REAGENT_BLOODSEALER
	id = REAGENT_ID_BLOODSEALER
	description = "A strange chemical that will stablize bloodflow by burning the subject"
	taste_description = "bitterness"
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#00BFFF"
	overdose = REAGENTS_OVERDOSE
	scannable = 1
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_MEDSCI

/datum/reagent/bloodsealer
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA) // P2-S13

/datum/reagent/bloodsealer/affect_blood(mob/living/carbon/M, alien, removed)
	M.injure(INJURY_BURN, 1 * removed, source = src) // the legacy negative burn-heal: a burn

/datum/reagent/quadcord
	treatment_tags = list(
		TREAT_TISSUE_REPAIR = 0.2,
		TREAT_BURN_CARE = 0.2,
		TREAT_OXYGENATION = 0.1,
		TREAT_ANTITOXIN = 0.1,
		TREAT_NEURAL_REPAIR = 0.3,
	)
	name = REAGENT_QUADCORD
	id = REAGENT_ID_QUADCORD
	description = "An experimental drug that is meant to further enhance tricord"
	taste_description = "bitterness"
	reagent_state = LIQUID
	color = "#FF3399"
	scannable = 1
	overdose = REAGENTS_OVERDOSE * 2
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_MEDSCI

//tier 3
/datum/reagent/modapplying/liquidhealer
	name = REAGENT_LIQUIDHEALER
	id = REAGENT_ID_LIQUIDHEALER
	description = "An experimental drug that mimics rapid regeneration seen in squishy creatures."
	taste_description = "sweet"
	reagent_state = LIQUID
	color = "#00CCFF"
	scannable = 1
	overdose = REAGENTS_OVERDOSE * 0.5
	modifier_to_add = /datum/body_effect/liquidhealer
	modifier_duration = 3 SECONDS
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_MEDSCI

/datum/reagent/modapplying/phoenixbreath
	name = REAGENT_PHOENIXBREATH
	id = REAGENT_ID_PHOENIXBREATH
	description = "An experimental chem that will bring those back from the brink, with severe side effects"
	taste_description = "ash"
	reagent_state = LIQUID
	color = "#fcac00"
	scannable = 1
	overdose = REAGENTS_OVERDOSE
	mrate_static = TRUE
	metabolism = 0.1
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_MEDSCI
	modifier_to_add = /datum/body_effect/life_cloak
	modifier_duration = 3 SECONDS
