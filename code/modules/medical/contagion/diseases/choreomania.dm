/datum/affliction/contagion/choreomania
	symptom_pool = list(
		/datum/affliction_symptom/jittery = 80,
		/datum/affliction_symptom/unsteady_gait = 40
	)
	name = "Choreomania"
	medical_name = "Choreatic Hyperkinesia"
	max_stages = 3
	spread_text = "Airborne"
	spread_flags = DISEASE_SPREAD_AIRBORNE | DISEASE_SPREAD_CONTACT | DISEASE_SPREAD_BLOOD | DISEASE_SPREAD_FLUIDS
	cure_text = REAGENT_ADRANOL
	cures = list(REAGENT_ID_ADRANOL)
	cure_chance = 10
	agent = "TAP-DAnC3"
	permeability_mod = 0.75
	desc = "If left untreated the subject... Won't stop dancing!"
	danger = DISEASE_MINOR

	var/static/list/dance = list(2,4,8,2,4,8,2,4,8,2,4,8,1,4,1,4,1,4,2,4,8,2)

/datum/affliction/contagion/choreomania/stage_act()
	..()
	switch(stage)
		if(2)
			if(prob(1))
				to_chat(host, span_notice("You feel like dancing like a maniac, maniac..."))
			if(prob(1))
				host.emote("whistle")
		if(3)
			if(prob(1))
				to_chat(host, span_notice("You feel like dancing like a maniac, maniac..."))
			if(prob(1))
				to_chat(host, span_notice("You really want to start a conga line!"))
			if(prob(2))
				for(var/D in dance)
					host.set_dir(D)
					animate(host, pixel_x = 5, time = 5)
					animate(host, pixel_x = -5, time = 5)
					animate(host, pixel_x = host.default_pixel_x, pixel_y = host.default_pixel_x, time = 2)
	return
