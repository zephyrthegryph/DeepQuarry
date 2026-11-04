/datum/reagent/ethanol/thirteenloko
	name = REAGENT_THIRTEENLOKO
	id =REAGENT_ID_THIRTEENLOKO
	description = "A potent mixture of caffeine and alcohol."
	taste_description = "battery acid"
	color = "#102000"
	strength = 25
	nutriment_factor = 1

	glass_name = REAGENT_THIRTEENLOKO
	glass_desc = "This is a glass of Thirteen Loko, it appears to be of the highest quality. The drink, not the glass."
	allergen_type = ALLERGEN_STIMULANT //Holy shit dude.

/datum/reagent/ethanol/thirteenloko/affect_ingest(mob/living/carbon/M, alien, removed)
	..()

	if(!(HAS_SYNTHETIC_BIOLOGY(M)))
		if(inert_for(M))
			return
		M.status_adjust(STAT_DROWSY, -7)
		if(M.body_temperature() > BODYTEMP_NORMAL)
			drive_body_temperature(M, BODYTEMP_NORMAL, 5 * TEMPERATURE_DAMAGE_COEFFICIENT, removed)
		M.status_adjust(STAT_JITTERY, 5)
