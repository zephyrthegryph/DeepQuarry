/datum/affliction/contagion/revblight
	subcategory = "Anomalous"
	immunogenicity = 2
	symptom_pool = list(
		/datum/affliction_symptom/pallor = 90,
		/datum/affliction_symptom/chills = 60,
		/datum/affliction_symptom/confusion = 50,
		/datum/affliction_symptom/fatigue = 60
	)
	max_symptoms = 3
	name = "Unnatural Wasting"
	medical_name = "Chameleonic Acute Depression"
	desc = "A strange condition which causes the victim to feel as if they were wasting away, despite being otherwise (almost) perfectly healthy."
	form = "Condition"
	max_stages = 5
	stage_prob = 5
	spread_flags = DISEASE_SPREAD_NON_CONTAGIOUS
	cure_text = REAGENT_HOLYWATER + " or rest"
	spread_text = "None"
	cures = list(REAGENT_ID_HOLYWATER)
	cure_chance = 30
	agent = "Unholy Forces"
	disease_flags = CURABLE | CAN_NOT_POPULATE
	permeability_mod = 1
	danger = DISEASE_HARMFUL
	var/stagedamage = 0
	var/finalstage = 0
	var/list/original_hair_colour

/datum/affliction/contagion/revblight/cure(add_resistance = FALSE)
	if(host)
		host.remove_atom_colour(TEMPORARY_COLOUR_PRIORITY, "#1d2953")
		if(original_hair_colour)
			var/mob/living/carbon/human/human = host
			human.change_hair_color(original_hair_colour[1], original_hair_colour[2], original_hair_colour[3])
		to_chat(host, span_notice("You feel better"))
		var/datum/affliction/blight = host.find_affliction(/datum/affliction/spectral_blight)
		blight?.cure()
	..()

/datum/affliction/contagion/revblight/stage_act(seconds_per_tick = 2)
	. = ..()
	if(!.)
		return

	if(!finalstage)
		if(host.lying && SPT_PROB(3 * stage, seconds_per_tick))
			cure()
			return FALSE
		if(SPT_PROB(1.5 * stage, seconds_per_tick))
			to_chat(host, span_danger("You suddenly feel [pick("sick and tired", "disoriented", "tired and confused", "nauseated", "faint", "dizzy")]..."))
			host.status_at_least(STAT_CONFUSED, 10)
			new /obj/effect/temp_visual/revenant(host.loc)
		if(stagedamage < stage)
			stagedamage++
			host.injure(INJURY_TOXIN, 1 * stage * seconds_per_tick, affliction = /datum/affliction/spectral_blight)
			new /obj/effect/temp_visual/revenant(host.loc)

	switch(stage)
		if(2)
			if(prob(5))
				host.emote("pale")
		if(3)
			if(prob(10))
				host.emote(pick("pale", "shiver"))
		if(4)
			if(prob(15))
				host.emote(pick("pale", "shiver", "cry"))
		if(5)
			if(!finalstage)
				finalstage = TRUE
				to_chat(host, span_danger("You feel like [pick("nothing's worth it anymore", "nobody ever needed your help", "nothing you did mattered", "everything you did was worthless.")]."))
				new /obj/effect/temp_visual/revenant(host.loc)
				if(ishuman(host))
					var/mob/living/carbon/human/human = host
					original_hair_colour = list(human.r_hair, human.g_hair, human.b_hair)
					human.change_hair_color(255, 255, 255)
				host.visible_message(span_warning("[host] looks terrifyingly gaunt..."), span_danger("You suddenly feel like your skin is <i>wrong</i>..."))
				host.add_atom_colour("#1d2953", TEMPORARY_COLOUR_PRIORITY)
				after(src, 10 SECONDS, PROC_REF(cure))
