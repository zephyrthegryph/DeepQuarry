/datum/reagent/drink/coffee/nukie/mega/shock //Rapidly fills you up and even repairs your NIF, unless you don't have one in which case you'll be confused.
	name = REAGENT_NUKIEMEGASHOCK
	id = REAGENT_ID_NUKIEMEGASHOCK
	color = "#ede500"
	taste_description = "a thousand volts running down your spine"

/datum/reagent/drink/coffee/nukie/mega/shock/affect_ingest(mob/living/carbon/M, alien, removed)
	..()
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		if(H.nif)
			var/obj/item/nif/nif = H.nif //L o c a l
			if(nif.stat == NIF_TEMPFAIL)
				nif.set_stat(NIF_INSTALLING)
			nif.repair(removed)
		else if(prob(5))
			M.status_set(STAT_CONFUSED, max(M.status_units(STAT_CONFUSED), 20))
			M.emote(pick("shudder", "seem lost", "blank for a moment"))
	M.adjust_nutrition(4 * removed)
