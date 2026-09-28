/datum/affliction/contagion/flu
	symptom_pool = list(
		/datum/affliction_symptom/fever_sensation = 80,
		/datum/affliction_symptom/fatigue = 70,
		/datum/affliction_symptom/wet_cough = 60,
		/datum/affliction_symptom/headache = 40,
		/datum/affliction_symptom/nausea = 30
	)
	max_symptoms = 3
	factors = alist(BF_TEMPERATURE = 1.5, BF_HEART_RATE = 10, BF_SLOWDOWN = 0.3)
	name = "The Flu"
	medical_name = "Influenza"
	max_stages = 3
	spread_text = "Airborne"
	cure_text = REAGENT_SPACEACILLIN
	cures = list(REAGENT_ID_SPACEACILLIN, REAGENT_ID_CHICKENSOUP, REAGENT_ID_CHICKENNOODLESOUP)
	virus_modifiers = NONE //Does NOT have needs_all_cures
	cure_chance = 10
	agent = "H13N1 flu virion"
	permeability_mod = 0.75
	desc = "If left untreated the subject will feel quite unwell."
	danger = DISEASE_MINOR

/datum/affliction/contagion/flu/stage_act()
	..()
	switch(stage)
		if(2)
			if(host.lying && prob(20))
				to_chat(host, span_notice("You feel better."))
				set_stage(stage - 1)
				return
			if(prob(1))
				host.emote("sneeze")
			if(prob(1))
				host.emote("cough")
			if(prob(1))
				to_chat(host, span_danger("Your muscles ache."))
				if(prob(20))
					host.injure(INJURY_PAIN, 1) // muscle aches
			if(prob(1))
				to_chat(host, span_danger("Your stomach hurts."))
				host.injure(INJURY_TOXIN, 1)
		if(3)
			if(host.lying && prob(15))
				to_chat(host, span_notice("You feel better."))
				set_stage(stage - 1)
				return
			if(prob(1))
				host.emote("sneeze")
			if(prob(1))
				host.emote("cough")
			if(prob(1))
				to_chat(host, span_danger("Your muscles ache."))
				if(prob(20))
					host.injure(INJURY_PAIN, 1) // muscle aches
			if(prob(1))
				to_chat(host, span_danger("Your stomach hurts."))
				host.injure(INJURY_TOXIN, 1)
	return
