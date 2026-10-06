/datum/affliction/contagion/food_poisoning
	category = "Abdominal"
	subcategory = "Bacterial"
	presentation = PRESENT_SURFACE | PRESENT_INTERNAL | PRESENT_LAB
	symptom_pool = list(
		/datum/affliction_symptom/nausea = 90,
		/datum/affliction_symptom/abdominal_tenderness = 70,
		/datum/affliction_symptom/fatigue = 40
	)
	max_symptoms = 3
	factors = alist(BF_TEMPERATURE = 0.8)
	name = "Food Poisoning"
	medical_name = "Gastroenteritis"
	max_stages = 3
	stage_prob = 5
	spread_text = "Non-Contagious"
	spread_flags = DISEASE_SPREAD_NON_CONTAGIOUS
	cure_text = "Sleep"
	agent = REAGENT_SALMONELLA
	cures = list(REAGENT_ID_CHICKENSOUP, REAGENT_ID_CHICKENNOODLESOUP)
	virus_modifiers = NONE // Does NOT need all the cures
	cure_chance = 10
	desc = "Nausea, sickness, and vomiting."
	danger = DISEASE_MINOR

/datum/affliction/contagion/food_poisoning/stage_act()
	if(!..())
		return FALSE
	if(host.stat == UNCONSCIOUS && prob(33))
		to_chat(host, span_notice("You feel better."))
		cure()
		return
	switch(stage)
		if(1)
			if(prob(5))
				to_chat(host, span_danger("Your stomach feels weird."))
			if(prob(5))
				to_chat(host, span_danger("You feel queasy."))
		if(2)
			if(host.stat == UNCONSCIOUS && prob(40))
				to_chat(host, span_notice("You feel better."))
				cure()
				return
			if(prob(1) && prob(10))
				to_chat(host, span_notice("You feel better."))
			if(prob(10))
				host.emote("groan")
			if(prob(5))
				to_chat(host, span_danger("Your stomach aches."))
			if(prob(5))
				to_chat(host, span_danger("You feel nauseous"))
		if(3)
			if(host.stat == UNCONSCIOUS && prob(25))
				to_chat(host, span_notice("You feel better."))
				cure()
				return
			if(prob(1) && prob(10))
				to_chat(host, span_notice("You feel better."))
				cure()
				return
			if(prob(10))
				host.emote("moan")
			if(prob(10))
				host.emote("groan")
			if(prob(1))
				to_chat(host, span_danger("Your stomach hurts."))
			if(prob(1))
				to_chat(host, span_danger("You feel sick."))
			if(prob(5))
				if(host.nutrition > 10)
					host.emote("vomit")
				else
					to_chat(host, span_danger("Your stomach lurches painfully"))
					act_message(host, null, others = span_danger("%U% gags and retches!"))
					host.status_at_least(STAT_STUNNED, rand(4, 8))
					host.status_at_least(STAT_WEAKENED, rand(4, 8))
