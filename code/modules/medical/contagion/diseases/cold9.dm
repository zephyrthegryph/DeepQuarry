/datum/affliction/contagion/cold9
	symptom_pool = list(
		/datum/affliction_symptom/chills = 80,
		/datum/affliction_symptom/wet_cough = 50,
		/datum/affliction_symptom/cold_mottled_skin = 50,
		/datum/affliction_symptom/limb_weakness = 40
	)
	max_symptoms = 3
	factors = alist(BF_SLOWDOWN = 1.5, BF_TEMPERATURE = -1.5, BF_MOTOR_CONTROL = 0.97)
	name = "The Cold"
	medical_name = "ICE9 Cold"
	max_stages = 3
	spread_text = "On contact"
	spread_flags = DISEASE_SPREAD_CONTACT | DISEASE_SPREAD_BLOOD | DISEASE_SPREAD_FLUIDS
	cure_text = REAGENT_SPACEACILLIN
	cures = list(REAGENT_ID_SPACEACILLIN)
	agent = "ICE9-rhinovirus"
	desc = "If left untreated the subject will slow, as if partly frozen."
	danger = DISEASE_HARMFUL

/datum/affliction/contagion/cold9/stage_act()
	..()
	switch(stage)
		if(1)
			if(prob(1))
				host.emote("sniff")
		if(2)
			if(prob(10))
				host.adjust_bodytemperature(-(2))
			if(prob(1) && prob(10))
				to_chat(host, span_notice("You feel better."))
				cure()
				return
			if(prob(1))
				host.emote("sneeze")
			if(prob(1))
				host.emote("cough")
			if(prob(1))
				to_chat(host, span_danger("Your throat feels sore."))
			if(prob(5))
				to_chat(host, span_danger("You feel stiff."))
		if(3)
			if(prob(10))
				host.adjust_bodytemperature(-(5))
			if(prob(1))
				host.emote("sneeze")
			if(prob(1))
				host.emote("cough")
			if(prob(1))
				to_chat(host, span_danger("Your throat feels sore."))
			if(prob(10))
				to_chat(host, span_danger("You feel stiff."))
