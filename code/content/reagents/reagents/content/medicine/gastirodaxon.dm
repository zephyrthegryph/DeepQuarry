/datum/reagent/gastirodaxon/affect_blood(mob/living/carbon/M, alien, removed)
	daxon_affect(M, removed)

/datum/reagent/gastirodaxon
	treatment_tags = list(TREAT_DIGESTIVE = 1.0, TREAT_ANTITOXIN = 0.6)
	// The gut that is mending absorbs what is swallowed more slowly.
	factors = alist(STAT_INGEST_ABSORPTION = 0.6)
	name = REAGENT_GASTIRODAXON
	id = REAGENT_ID_GASTIRODAXON
	description = "Used to repair the stomach and gut, and to treat appendiceal sepsis. While the gut mends it absorbs swallowed medicine more slowly, so oral doses work later and weaker."
	taste_description = "chalk"
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#8B4513"
	metabolism = REM * 1.5
	overdose = 10
	overdose_mod = 1.75
	scannable = SCANNABLE_BENEFICIAL
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_SPECIALDRUG

TYPE_TABLE(/datum/reagent/gastirodaxon, daxon_organs, list(O_APPENDIX, O_STOMACH, O_INTESTINE, O_NUTRIENT, O_PLASMA, O_POLYP))

TYPE_TABLE(/datum/reagent/gastirodaxon, daxon_partners, list(REAGENT_ID_HEPANEPHRODAXON, REAGENT_ID_PERIDAXON))

/datum/reagent/gastirodaxon/daxon_clash(mob/living/carbon/human/H, removed)
	if(prob(10))
		H.vomit(1)
	else if(nutrition_of(H) > 30)
		H.adjust_nutrition(-removed * 30)
