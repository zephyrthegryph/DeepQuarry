/datum/affliction/contagion/fake_gbs
	symptom_pool = list(
		/datum/affliction_symptom/wet_cough = 60,
		/datum/affliction_symptom/fatigue = 60,
		/datum/affliction_symptom/short_breath = 30
	)
	name = "GBS"
	medical_name = "Neutered Guillain-Barré Syndrome"
	max_stages = 5
	spread_text = "On contact"
	spread_flags = DISEASE_SPREAD_CONTACT | DISEASE_SPREAD_BLOOD | DISEASE_SPREAD_FLUIDS
	cure_text = REAGENT_ADRANOL + " & " + REAGENT_SULFUR
	cures = list(REAGENT_ID_ADRANOL, REAGENT_ID_SULFUR)
	agent = "Gravitokinetic Bipotential SADS-"
	desc = "If left untreated death will occur."
	danger = DISEASE_BIOHAZARD // Mimics real GBS

/datum/affliction/contagion/fake_gbs/stage_act()
	if(!..())
		return FALSE
	switch(stage)
		if(2)
			if(prob(1))
				host.emote("sneeze")
		if(3)
			if(prob(5))
				host.emote("cough")
			else if(prob(5))
				host.emote("gasp")
			if(prob(10))
				to_chat(host, span_danger("You're starting to feel very weak..."))
		if(4)
			if(prob(10))
				host.emote("cough")
		if(5)
			if(prob(10))
				host.emote("cough")
