/datum/affliction/contagion/brainrot
	subcategory = "Fungal"
	immunogenicity = 0.5
	symptom_pool = list(
		/datum/affliction_symptom/confusion = 70,
		/datum/affliction_symptom/drowsy = 60,
		/datum/affliction_symptom/headache = 50,
		/datum/affliction_symptom/fever_sensation = 30
	)
	max_symptoms = 3
	factors = alist(BF_TEMPERATURE = 1.5, BF_ACCURACY = -10)
	name = "Brainrot"
	medical_name = "Encephalonecrosis"
	max_stages = 4
	spread_text = "On contact"
	spread_flags = DISEASE_SPREAD_BLOOD | DISEASE_SPREAD_FLUIDS | DISEASE_SPREAD_CONTACT
	cure_text = REAGENT_ALKYSINE
	cures = list(REAGENT_ID_ALKYSINE)
	agent = "Cryptococcus Cosmosis"
	cure_chance = 15
	desc = "Destroys the braincells, causing brain fever, brain necrosis and general intoxication."
	required_organs = list(/obj/item/organ/internal/brain)
	danger = DISEASE_HARMFUL

/datum/affliction/contagion/brainrot/stage_act()
	..()
	switch(stage)
		if(2)
			if(prob(2))
				host.say("*blink")
			if(prob(2))
				host.say("*yawn")
			if(prob(2))
				to_chat(host, span_danger("You don't feel like yourself."))
			if(prob(5))
				host.injure(INJURY_NEURAL, 1)
		if(3)
			if(prob(2))
				host.say("*stare")
			if(prob(3))
				host.say("*drool")
			if(prob(10) && host.injury_load(INJURY_CATEGORY_NEURAL) < 100)
				host.injure(INJURY_NEURAL, 3)
				if(prob(2))
					to_chat(host, span_danger("Strange buzzing fills your head, removing all thoughts."))
			if(prob(3))
				to_chat(host, span_danger("You lose consciousness..."))
				host.status_at_least(STAT_SLEEPING, rand(5, 10))
				if(prob(1))
					host.emote("snore")
			if(prob(15))
				host.apply_effect(5, STUTTER)
