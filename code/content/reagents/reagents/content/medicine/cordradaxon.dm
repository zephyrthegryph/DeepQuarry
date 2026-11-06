/datum/reagent/cordradaxon/affect_blood(mob/living/carbon/M, alien, removed)
	daxon_affect(M, removed)

/datum/reagent/cordradaxon
	treatment_tags = list(TREAT_CARDIAC = 1.0, TREAT_OXYGENATION = 0.6)
	name = REAGENT_CORDRADAXON
	id = REAGENT_ID_CORDRADAXON
	description = "Used to repair the specialized tissues involved in the circulatory system."
	taste_description = "rust"
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#FF4444"
	metabolism = REM * 1.5
	overdose = 10
	overdose_mod = 1.75
	scannable = SCANNABLE_BENEFICIAL
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_SPECIALDRUG

TYPE_TABLE(/datum/reagent/cordradaxon, daxon_organs, list(O_HEART, O_SPLEEN, O_RESPONSE, O_ANCHOR, O_EGG))

TYPE_TABLE(/datum/reagent/cordradaxon, daxon_partners, list(REAGENT_ID_HYRONALIN, REAGENT_ID_PERIDAXON))

/datum/reagent/cordradaxon/daxon_clash(mob/living/carbon/human/H, removed)
	H.set_losebreath(CLAMP(H.losebreath() + 1, 0, 10))
