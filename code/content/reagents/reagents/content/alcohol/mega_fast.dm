/datum/reagent/drink/coffee/nukie/mega/fast //Like hyperzine, but instead of overdosing, it occassionally burns you
	factors = alist(STAT_SLOWDOWN = -1, STAT_PENALTY_SCALE = 0.5)
	name = REAGENT_NUKIEMEGAFAST
	id = REAGENT_ID_NUKIEMEGAFAST
	color = "#000000"
	taste_description = "more, more, now, quick, get yourself some more, don't stop"

/datum/reagent/drink/coffee/nukie/mega/fast/affect_ingest(mob/living/carbon/M, alien, removed)
	..()
	if(prob(1))
		act_message(M, null, others = span_danger("%U% sizzles!"))
		M.injure(INJURY_BURN, 5, source = src)
