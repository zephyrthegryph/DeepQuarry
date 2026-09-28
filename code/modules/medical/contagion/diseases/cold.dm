/datum/affliction/contagion/cold
	symptom_pool = list(
		/datum/affliction_symptom/wet_cough = 70,
		/datum/affliction_symptom/fatigue = 40,
		/datum/affliction_symptom/headache = 30
	)
	factors = alist(BF_TEMPERATURE = 0.5)
	name = "The Cold"
	medical_name = "Common Cold"
	max_stages = 3
	spread_text = "Airborne"
	spread_flags = DISEASE_SPREAD_AIRBORNE
	cure_text = "Rest & " + REAGENT_SPACEACILLIN
	cures = list(REAGENT_ID_SPACEACILLIN, REAGENT_ID_CHICKENSOUP, REAGENT_ID_CHICKENNOODLESOUP)
	virus_modifiers = NONE //Does NOT have needs_all_cures
	agent = "XY-rhinovirus"
	permeability_mod = 0.5
	desc = "If left untreated the subject will contract the flu."
	danger = DISEASE_MINOR

/datum/affliction/contagion/cold/stage_act()
	..()
	switch(stage)
		if(2)
			if(host.stat == UNCONSCIOUS && prob(40))
				to_chat(host, span_notice("You feel better."))
				cure()
				return
			if(host.lying && prob(10))
				to_chat(host, span_notice("You feel better."))
				cure()
				return
			if(prob(1) && prob(5))
				to_chat(host, span_notice("You feel better."))
				cure()
				return
			if(prob(1))
				host.emote("sneeze")
			if(prob(1))
				host.emote("cough")
			if(prob(1))
				to_chat(host, span_notice("Your throat feels sore."))
			if(prob(1))
				to_chat(host, span_notice("Mucous runs down the back of your throat."))
		if(3)
			if(host.stat == UNCONSCIOUS && prob(25))
				to_chat(host, span_notice("You feel better."))
				cure()
				return
			if(host.lying && prob(5))
				to_chat(host, span_notice("You feel better."))
				cure()
				return
			if(prob(1) && prob(1))
				to_chat(host, span_notice("You feel better."))
				cure()
				return
			if(prob(1))
				host.emote("sneeze")
			if(prob(1))
				host.emote("cough")
			if(prob(1))
				to_chat(host, span_notice("Your throat feels sore."))
			if(prob(1))
				to_chat(host, span_notice("Mucous runs down the back of your throat."))
			if(prob(1) && prob(50))
				// Untreated, a cold can turn into the flu.
				if(!host.has_contagion_immunity(/datum/affliction/contagion/flu))
					var/datum/affliction/contagion/Flu = new /datum/affliction/contagion/flu
					var/mob/living/carbon/human/sufferer = host
					log_game("CONTAGION: [key_name(sufferer)]'s cold progressed into the flu.")
					cure(FALSE)
					sufferer.force_contagion(Flu)
