/datum/affliction/contagion/roanoke
	subcategory = "Cellular"
	immunogenicity = 0.2
	symptom_pool = list(
		/datum/affliction_symptom/fever_sensation = 80,
		/datum/affliction_symptom/chills = 50,
		/datum/affliction_symptom/fatigue = 40
	)
	factors = alist(BF_TEMPERATURE = 2, BF_HEART_RATE = 15)
	name = "Roanoke Syndrome"
	medical_name = "Roanoke Syndrome"
	max_stages = 6
	stage_prob = 2
	spread_text = "Blood and close contact"
	spread_flags = DISEASE_SPREAD_BLOOD
	cure_text = REAGENT_SPACEACILLIN
	agent = "Chimera cells"
	cures = list(REAGENT_ID_SPACEACILLIN)
	cure_chance = 10
	desc = "If left untreated, subject will become a xenochimera upon perishing."
	danger = DISEASE_BIOHAZARD
	disease_flags = CURABLE | CAN_CARRY | CAN_NOT_POPULATE
	virus_modifiers = BYPASSES_IMMUNITY | SPREAD_DEAD


/// A random organ of the host (the old cached organ list held hard refs).
/datum/affliction/contagion/roanoke/proc/pick_organ()
	var/list/candidates = host.organs + host.internal_organs
	return length(candidates) ? pick(candidates) : null

/datum/affliction/contagion/roanoke/stage_act()
	if(!..())
		return FALSE
	var/mob/living/carbon/human/M = host
	switch(stage)
		if(2)
			if(prob(1))
				to_chat(M, span_notice("You feel a slight shiver through your spine..."))
			if(prob(1))
				to_chat(M, span_warning(pick("You feel hot.", "You feel like you're burning.")))
				if(M.bodytemperature < BODYTEMP_HEAT_DAMAGE_LIMIT)
					fever(M)
		if(3)
			if(prob(1))
				to_chat(M, span_notice("You shiver a bit."))
			if(prob(1))
				to_chat(M, span_warning(pick("You feel hot.", "You feel like you're burning.")))
				if(M.bodytemperature < BODYTEMP_HEAT_DAMAGE_LIMIT)
					fever(M)
			if(prob(1))
				var/obj/item/organ/O = pick_organ()
				O?.adjust_germ_level(rand(5, 10))
		if(4)
			if(prob(1))
				to_chat(M, span_warning(pick("You feel hot.", "You feel like you're burning.")))
				if(M.bodytemperature < BODYTEMP_HEAT_DAMAGE_LIMIT)
					fever(M)
			if(prob(2))
				var/obj/item/organ/O = pick_organ()
				O?.adjust_germ_level(rand(5, 10))
		if(5)
			if(prob(1))
				to_chat(M, span_warning(pick("You feel hot.", "You feel like you're burning.")))
				if(M.bodytemperature < BODYTEMP_HEAT_DAMAGE_LIMIT)
					fever(M)
			if(prob(2))
				var/obj/item/organ/O = pick_organ()
				O?.adjust_germ_level(rand(5, 10))
			if(prob(1))
				var/obj/item/organ/O = pick_organ()
				M.injure(INJURY_BLUNT, rand(1, 3), O)
		if(6)
			if(prob(1))
				to_chat(M, span_warning(pick("You feel hot.", "You feel like you're burning.")))
				if(M.bodytemperature < BODYTEMP_HEAT_DAMAGE_LIMIT)
					fever(M)

			if(prob(2))
				var/obj/item/organ/O = pick_organ()
				O?.adjust_germ_level(rand(5, 10))

			if(prob(2))
				var/obj/item/organ/O = pick_organ()
				M.injure(INJURY_BLUNT, rand(1, 3), O)

			if(prob(1) && prob(10))
				var/obj/item/organ/O = pick_organ()
				var/obj/item/organ/external/E = istype(O, /obj/item/organ/external) ? O : M.get_organ(O?.parent_organ)
				if(istype(E))
					E.add_wound(new /datum/affliction/wound/internal_bleeding(E, 5))
				M.process_organs(TRUE) //Force an update so we start processing the internal bleeding.

			if(M.stat == DEAD || M.allow_spontaneous_tf)
				M.LoadComponent(/datum/component/xenochimera)
				cure()
	return

/datum/affliction/contagion/roanoke/proc/fever(mob/living/M, datum/affliction/contagion/D)
	M.bodytemperature = min(M.bodytemperature + (2 * stage), BODYTEMP_HEAT_DAMAGE_LIMIT - 1)
	return TRUE
