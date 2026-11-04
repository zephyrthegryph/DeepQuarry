/datum/reagent/nutriment/magicdust
	name = REAGENT_MAGICDUST
	id = REAGENT_ID_MAGICDUST
	description = "A dust harvested from gnomes, aptly named by pre-industrial civilizations."
	taste_description = "something tingly"
	taste_mult = 2
	reagent_state = LIQUID
	nutriment_factor = 40 //very filling
	color = "#d169b2"
	coolant_modifier = 3 // HOOH!

/datum/reagent/nutriment/magicdust/affect_ingest(mob/living/carbon/M, alien, removed)
	..()
	play_sfx(M, SFX_ITEMS_HOOH, extrarange = -1)
	if(prob(5))
		to_chat(M, span_warning("You feel like you've been gnomed..."))
