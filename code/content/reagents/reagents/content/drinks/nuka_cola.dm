/datum/reagent/drink/soda/nuka_cola
	factors = alist(STAT_SLOWDOWN = -1, STAT_PENALTY_SCALE = 0.5)
	name = REAGENT_NUKACOLA
	id = REAGENT_ID_NUKACOLA
	description = "Cola, cola never changes."
	taste_description = "cola"
	nutriment_factor = 1.5
	color = "#100800"
	adj_temp = -5
	adj_sleepy = -2

	glass_name = "Nuka-Cola"
	glass_desc = "Don't cry, Don't raise your eye, It's only nuclear wasteland"
	glass_special = list(DRINK_FIZZ)
	allergen_type = ALLERGEN_STIMULANT

/datum/reagent/drink/soda/nuka_cola/affect_ingest(mob/living/carbon/M, alien, removed)
	..()
	M.status_adjust(STAT_JITTERY, 20)
	M.status_at_least(STAT_DRUGGED, 30)
	M.status_adjust(STAT_DIZZY, 5)
	M.status_set(STAT_DROWSY, 0)
