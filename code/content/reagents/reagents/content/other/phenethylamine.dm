/datum/reagent/phenethylamine
	name = REAGENT_PHENETHYLAMINE
	id = REAGENT_ID_PHENETHYLAMINE
	description = "Just looking at this makes you feel odd. Whether or not this would be good to consume is likely a gamble."
	color = "#463667"
	data = list("count"=1)
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_RECDRUG

/datum/reagent/phenethylamine/on_mob_life(mob/living/M as mob)
	if(!M) M = holder.my_atom
	if(data)
		switch(data["count"])
			if(1 to 30)
				if(prob(9)) M.visible_emote("blushes")
				if(prob(9)) to_chat(M, span_warning("You feel so needy.."))
			if (30 to INFINITY)
				if(prob(3)) M.visible_emote("blushes")
				if(prob(5)) M.audible_emote("moans out lewdly!")
				if(prob(9)) to_chat(M, span_warning("You can't help but want to touch yourself then and now!"))
		data["count"]++
	holder.remove_reagent(src.id, 0.2)
	return
