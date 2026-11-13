/* General medicine */

/datum/reagent/inaprovaline
	// The station's resuscitation stabiliser (and the AllergyPen's payload):
	// a weaker vasopressor on top of circulatory support.
	treatment_tags = list(TREAT_CIRCULATORY = 1.0, TREAT_VASOPRESSOR = 0.5)
	// Dampens pain (and hides where it hurts), slows a dying patient's decline (stabilisation), holds a withdrawal crisis off (and hides it from scans).
	factors = alist(STAT_ANALGESIA = 10, STAT_STABILIZATION = 15, STAT_ALLERGY = -5, STAT_WITHDRAWAL = -1.5)
	hides = list(HIDE_PAIN_LOCATION, HIDE_SYMPTOM_SUPPRESSION)
	species_factors = alist(IS_DIONA = null)
	name = REAGENT_INAPROVALINE
	id = REAGENT_ID_INAPROVALINE
	description = REAGENT_INAPROVALINE + " is a synaptic stimulant and cardiostimulant. Commonly used to stabilize patients: it supports the circulation, dampens pain, slows the decline of a dying patient, suppresses withdrawal and counteracts allergic reactions. Scans lose track of where it hurts and of the signs of withdrawal while it is in the blood."
	taste_description = "bitterness"
	reagent_state = LIQUID
	color = "#00BFFF"
	overdose = REAGENTS_OVERDOSE * 2
	metabolism = REM * 0.2
	dermal_absorption = 0.2
	scannable = SCANNABLE_BENEFICIAL
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_DRUG

/datum/reagent/calciumcarbonate
	treatment_tags = list(TREAT_ANTIEMETIC = 1.0)
	factors = alist(STAT_ANTIEMETIC = 3)
	species_factors = alist(IS_DIONA = null)
	name = REAGENT_CALCIUMCARBONATE
	id = REAGENT_ID_CALCIUMCARBONATE
	description = "Calcium carbonate is a calcium salt commonly used as an antacid: it settles nausea and stops vomiting. It binds Dylovene in the blood and weakens it, and injecting it poisons the patient."
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
	// Burn care for degrees 1 to 3 (moderate, large and severe burns); deep and carbonised burns (4 and 5) need dermaline (TREAT_BURN_DEEP).
	treatment_tags = list(TREAT_BURN_CARE = 0.6)
	// Slows the natural healing of the other wounds (cuts, bruises) on a limb where it is healing burns, only there.
	slows_other = alist(TREAT_BURN_CARE = 0.85)
	name = REAGENT_KELOTANE
	id = REAGENT_ID_KELOTANE
	description = REAGENT_KELOTANE + " is a drug used to treat burns of the first to third degree (it barely reaches deep burns, which need dermaline). On a limb where it is healing burns it slows the natural healing of that limb's other wounds, and an overdose upsets the stomach."
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
	// Deep burns (degrees 4 and 5), burnt airways and the swelling they cause; a minor share of ordinary burn care.
	treatment_tags = list(TREAT_BURN_DEEP = 1.0, TREAT_BURN_CARE = 0.3, TREAT_ANTIEDEMA = 0.8, TREAT_THERMOREGULATION = 0.2)
	strains = alist(O_KIDNEYS = DRUG_STRAIN_MODERATE)
	drains_blood = 2
	id = REAGENT_ID_DERMALINE
	name = REAGENT_DERMALINE
	description = REAGENT_DERMALINE + " is the next step in burn medication: it restores the direst heat damage (fourth and fifth degree burns), heals burnt airways and shrinks the airway swelling that comes with them. It drains blood from the patient (watch the blood volume) and strains the kidneys."
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

/datum/reagent/hyronalin
	// Weak and slow: mild radiation only.
	treatment_tags = list(TREAT_ANTIRADIATION = 0.25)
	name = REAGENT_HYRONALIN
	id = REAGENT_ID_HYRONALIN
	description = REAGENT_HYRONALIN + " is a mild, slow-acting drug used against radiation poisoning: weak, but it clears from the body only slowly. Arithrazine is the stronger choice for severe radiation."
	taste_description = "bitterness"
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#408000"
	metabolism = REM * 0.1
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
	description = "Leporazine drives the body temperature back toward normal, whether the patient is too cold or too hot (hypothermia, heatstroke). An overdose reverses it: the temperature is pushed further away from normal."
	taste_description = "bitterness"
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#C8A5DC"
	overdose = REAGENTS_OVERDOSE
	scannable = SCANNABLE_BENEFICIAL
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_CLONEDRUG
	coolant_modifier = 0.5 // Okay substitute coolant

/// Overdosed, the regulation flips: the body is pushed further from normal (hot goes hotter, cold goes colder) on top of the poisoning.
/datum/reagent/leporazine/overdose(mob/living/carbon/M, alien, removed)
	..()
	var/direction = M.body_temperature() >= BODYTEMP_NORMAL ? 1 : -1
	var/moved = warm_body(M, direction * LEPORAZINE_OVERDOSE_KELVIN_PER_REM, removed)
	if(GLOB.chem_trace)
		log_world("CHEM: leporazine overdose pushes [M] by [moved] K (direction [direction], removed [removed])")

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
	description = "A well respected antipsychotic used for the treatment of schizophrenia in specific: it quiets hallucinations and shortens the hallucination episodes of the schizophrenic trait. Leaves the patient mildly drowsy."
	overdose = REAGENTS_OVERDOSE * 2
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_DRUG

/datum/reagent/tercozolam/affect_blood(mob/living/carbon/M, alien, removed)
	M.status_adjust(STAT_HALLUCINATING, -(6 * removed))


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
