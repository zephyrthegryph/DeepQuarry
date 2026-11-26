/datum/reagent/hepanephrodaxon/affect_blood(mob/living/carbon/M, alien, removed)
	daxon_affect(M, removed)

/datum/reagent/hepanephrodaxon
	treatment_tags = list(TREAT_HEPATORENAL = 1.0)
	// The filtering organs are busy mending: everything in the blood, toxins included, is cleared more slowly.
	factors = alist(STAT_METABOLISM_MULT = 0.85)
	name = REAGENT_HEPANEPHRODAXON
	id = REAGENT_ID_HEPANEPHRODAXON
	description = "Used to repair the liver and kidneys (hepatorenal failure). While the organs mend, reagents and toxins in the blood clear more slowly, and the drug makes the patient nauseous."
	taste_description = "glue"
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#D2691E"
	metabolism = REM * 1.5
	overdose = 10
	overdose_mod = 1.75
	scannable = SCANNABLE_BENEFICIAL
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_SPECIALDRUG

TYPE_TABLE(/datum/reagent/hepanephrodaxon, daxon_organs, list(O_LIVER, O_KIDNEYS, O_APPENDIX, O_ACID, O_HIVE))

TYPE_TABLE(/datum/reagent/hepanephrodaxon, daxon_partners, list(REAGENT_ID_CORDRADAXON, REAGENT_ID_PERIDAXON))

/datum/reagent/hepanephrodaxon/daxon_clash(mob/living/carbon/human/H, removed)
	if(prob(5))
		H.vomit(1)
	else if(prob(5))
		to_chat(H, span_danger("Something churns inside you."))
		H.injure(INJURY_TOXIN, 10 * removed, source = src)
		H.vomit(0, 1)
