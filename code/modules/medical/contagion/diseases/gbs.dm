/datum/affliction/contagion/gbs
	immunogenicity = 0.25
	symptom_pool = list(
		/datum/affliction_symptom/fatigue = 90,
		/datum/affliction_symptom/limb_weakness = 70,
		/datum/affliction_symptom/pallor = 60,
		/datum/affliction_symptom/short_breath = 40
	)
	max_symptoms = 3
	factors = alist(BF_SLOWDOWN = 1, BF_MOTOR_CONTROL = 0.95, BF_HEART_RATE = 20)
	name = "GBS"
	medical_name = "Guillain-Barré Syndrome"
	desc = "If left untreated death will occur."
	max_stages = 5
	spread_text = "On contact"
	spread_flags = DISEASE_SPREAD_CONTACT | DISEASE_SPREAD_BLOOD | DISEASE_SPREAD_FLUIDS
	cure_text = REAGENT_ADRANOL + " & " + REAGENT_SULFUR
	cures = list(REAGENT_ID_ADRANOL, REAGENT_ID_SULFUR)
	cure_chance = 15
	agent = "Gravitokinetic Bipotential SADS+"
	danger = DISEASE_PANDEMIC
	disease_flags = CAN_NOT_POPULATE

/datum/affliction/contagion/gbs/stage_act()
	if(!..())
		return FALSE
	switch(stage)
		if(2)
			if(prob(45))
				host.injure(INJURY_TOXIN, 5, affliction = /datum/affliction/cytolytic_toxaemia)
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
			host.injure(INJURY_TOXIN, 5, affliction = /datum/affliction/cytolytic_toxaemia)
		if(5)
			to_chat(host, span_danger("Your body feels as if it's trying to rip itself open..."))
			if(prob(50))
				host.delayed_gib()
		else
			return

/datum/affliction/contagion/gbs/curable
	name = "Non-Contagious GBS"
	medical_name = "Non-Contagious Guillain-Barré Syndrome"
	desc = "If left untreated death will occur."
	stage_prob = 5
	spread_text = "Non-contagious"
	spread_flags = DISEASE_SPREAD_NON_CONTAGIOUS
	cure_text = REAGENT_CRYOXADONE
	cures = list(REAGENT_ID_CRYOXADONE)
	cure_chance = 10
	agent = "gibbis"
	disease_flags = CURABLE|CAN_NOT_POPULATE
