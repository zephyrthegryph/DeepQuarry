/datum/reagent/drink/coffee/nukie/mega/nega //Makes you both jittery and sleepy
	name = REAGENT_NUKIEMEGASLEEP
	id = REAGENT_ID_NUKIEMEGASLEEP
	color = "#00dded"
	taste_description = "the void encompassing you"
	adj_drowsy = 0
	adj_sleepy = 0
	var/adj_tiredness = 5

/datum/reagent/drink/coffee/nukie/mega/nega/affect_ingest(mob/living/carbon/human/M, alien, removed)
	if(M.status_units(STAT_TIREDNESS) < 105)
		M.status_set(STAT_TIREDNESS, (M.status_units(STAT_TIREDNESS) + adj_tiredness))
	..()
