/datum/affliction/contagion/anxiety
	subcategory = "Parasitic"
	symptom_pool = list(
		/datum/affliction_symptom/jittery = 70,
		/datum/affliction_symptom/nausea = 50,
		/datum/affliction_symptom/palpitations = 40
	)
	factors = alist(BF_HEART_RATE = 25)
	name = "Severe Anxiety"
	medical_name = "Lepidopteric Hyperemesis"
	form = "Infection"
	max_stages = 4
	spread_text = "On contact"
	spread_flags = DISEASE_SPREAD_BLOOD | DISEASE_SPREAD_FLUIDS | DISEASE_SPREAD_CONTACT
	cure_text = REAGENT_ETHANOL
	cures = list(REAGENT_ID_ETHANOL)
	agent = "Excess Lepdopticides"
	desc = "If left untreated subject will regurgitate butterflies."
	danger = DISEASE_MINOR

/datum/affliction/contagion/anxiety/stage_act()
	..()
	switch(stage)
		if(2)
			if(prob(15))
				to_chat(host, span_notice("You feel anxious."))
		if(3)
			if(prob(10))
				to_chat(host, span_notice("Your stomach flutters."))
			if(prob(5))
				to_chat(host, span_notice("You feel panicky."))
			if(prob(2))
				to_chat(host, span_danger("You're overtaken with panic!"))
				host.status_adjust(STAT_CONFUSED, rand(4, 6))
		if(4)
			if(prob(10))
				to_chat(host, span_danger("You feel butterflies in your stomach."))
			if(prob(5))
				host.visible_message(
					span_danger("[host] stumbles around in a panic"),
					span_userdanger("You have a panic attack!")
				)
				host.status_adjust(STAT_CONFUSED, rand(12, 16))
				host.status_adjust(STAT_JITTERY, 100 + rand(12, 16))
			if(prob(2))
				host.visible_message(
					span_danger("[host] coughs up butterflies!"),
					span_userdanger("You cough up butterflies!")
				)
				host.emote("cough")
				for(var/i in 1 to 2)
					var/mob/living/simple_mob/animal/sif/glitterfly/B = new(host.loc)
					after(B, rand(5, 25) SECONDS, TYPE_PROC_REF(/mob/living/simple_mob/animal/sif/glitterfly, decompose))

/mob/living/simple_mob/animal/sif/glitterfly/proc/decompose()
	act_message(src, null, MSG_SELF(span_userdanger("You decompose for being too long out of your habitat!")), \
		MSG_OTHERS(span_notice("%U% decomposes due to being outside of its original habitat for too long!")))
	dust()
