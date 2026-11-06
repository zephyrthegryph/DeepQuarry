/datum/reagent/frostoil
	name = REAGENT_FROSTOIL
	id = REAGENT_ID_FROSTOIL
	description = "A special oil that noticably chills the body. Extracted from Ice Peppers."
	taste_description = "mint"
	taste_mult = 1.5
	reagent_state = LIQUID
	ingest_met = REM
	color = "#B31008"
	wiki_flag = WIKI_FOOD
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_FOOD
	coolant_modifier = 2.5

/datum/reagent/frostoil
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA) // P2-S13

/datum/reagent/frostoil/affect_blood(mob/living/carbon/M, alien, removed)
	warm_body(M, -10 * TEMPERATURE_DAMAGE_COEFFICIENT, removed, min_temp = min(M.body_temperature(), 215))
	if(prob(1))
		M.emote("shiver")
	holder.remove_reagent(REAGENT_ID_CAPSAICIN, 5)

/datum/reagent/frostoil
	immune_species_ingest = SPECIES_TAG_BIT(IS_DIONA) // P2-S13

/datum/reagent/frostoil/affect_ingest(mob/living/carbon/M, alien, removed) // Eating frostoil now acts like capsaicin. Wee!
	// Kept: plant people get a different, mild effect (not a strength).
	if(alien == IS_ALRAUNE) // It wouldn't affect plants that much.
		if(prob(5))
			to_chat(M, span_rose("You feel a chilly, tingling sensation in your mouth."))
		warm_body(M, -rand(10, 25), removed)
		return
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		if(!H.can_feel_pain())
			return
	var/effective_dose = (dose * M.species.spice_mod)
	if((effective_dose < 5) && (dose == metabolism || prob(5)))
		to_chat(M, span_danger("Your insides suddenly feel a spreading chill!"))
	if(effective_dose >= 5)
		M.apply_effect(2 * M.species.spice_mod, AGONY, 0)
		warm_body(M, -rand(1, 5) * M.species.spice_mod, removed) // Really fucks you up, cause it makes you cold.
		if(prob(5))
			act_message(M, null, MSG_SELF(pick(span_danger("You feel like your insides are freezing!"), span_danger("Your insides feel like they're turning to ice!"))), \
				MSG_OTHERS(span_warning("%U% [pick("dry heaves!","coughs!","splutters!")]")))
	// holder.remove_reagent(REAGENT_ID_CAPSAICIN, 5) // Nop, we don't instadelete spices for free.

/datum/reagent/frostoil/cryotoxin //A longer lasting version of frost oil.
	name = REAGENT_CRYOTOXIN
	id = REAGENT_ID_CRYOTOXIN
	description = "Lowers the body's internal temperature."
	reagent_state = LIQUID
	color = "#B31008"
	metabolism = REM * 0.5
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_MATSCI
	coolant_modifier = 3
