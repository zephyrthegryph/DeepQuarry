/datum/affliction/contagion/beesease
	subcategory = "Parasitic"
	symptom_pool = list(
		/datum/affliction_symptom/abdominal_tenderness = 60,
		/datum/affliction_symptom/nausea = 50,
		/datum/affliction_symptom/internal_pressure = 40
	)
	name = "Beesease"
	medical_name = "Apidaemia"
	form = "Infection"
	max_stages = 4
	spread_text = "On contact"
	spread_flags = DISEASE_SPREAD_BLOOD | DISEASE_SPREAD_FLUIDS | DISEASE_SPREAD_CONTACT
	cure_text = REAGENT_SUGAR
	cures = list(REAGENT_ID_SUGAR)
	agent = "Apidae Infection"
	desc = "If left untreated, subject will regurgitate bees."
	danger = DISEASE_MEDIUM

/datum/affliction/contagion/beesease/stage_act()
	..()
	switch(stage)
		if(2)
			if(prob(2))
				to_chat(host, span_notice("You tastey hone in your mouth."))
		if(3)
			if(prob(10))
				to_chat(host, span_notice("Your stomach rumbles"))
			if(prob(2))
				to_chat(host, span_notice("Your stomach stings painfully."))
				if(prob(20))
					host.injure(INJURY_TOXIN, 2, affliction = /datum/affliction/apid_infestation)
		if(4)
			if(prob(10))
				host.visible_message(span_danger("[host] buzzles loudly"), span_userdanger("Your stomach buzzles violently!"))
			if(prob(5))
				to_chat(host, span_danger("You feel something moving in your throat."))
			if(prob(1))
				host.visible_message(span_danger("[host] coughs up a swarm of bees!"), span_userdanger("You cough up a swarm of bees!"))
				new /mob/living/simple_mob/vore/bee(host.loc)
	return
