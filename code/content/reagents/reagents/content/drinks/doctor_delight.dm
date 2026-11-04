/datum/reagent/drink/doctor_delight
	treatment_tags = list(
		TREAT_TISSUE_REPAIR = 0.4,
		TREAT_BURN_CARE = 0.4,
		TREAT_OXYGENATION = 0.2,
		TREAT_ANTITOXIN = 0.3,
	)
	name = REAGENT_DOCTORSDELIGHT
	id = REAGENT_ID_DOCTORSDELIGHT
	description = "A gulp a day keeps the MediBot away. That's probably for the best."
	taste_description = "homely fruit smoothie"
	reagent_state = LIQUID
	color = "#FF8CFF"
	nutrition = 1

	glass_name = REAGENT_DOCTORSDELIGHT
	glass_desc = "A healthy mixture of juices, guaranteed to keep you healthy until the next toolboxing takes place."
	allergen_type = ALLERGEN_FRUIT|ALLERGEN_DAIRY //Made from several fruit juices, and cream.
	medallergen_type = MEDALLERGEN_TRICORD // this too!

/datum/reagent/drink/doctor_delight/affect_ingest(mob/living/carbon/M, alien, removed)
	..()
	if(inert_for(M))
		return
	// Its healing is the treatment_tags profile.
	M.status_adjust(STAT_DIZZY, -15)
	if(M.has_status(STAT_CONFUSED))
		M.status_at_least(STAT_CONFUSED, -5)
