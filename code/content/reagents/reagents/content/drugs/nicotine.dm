/datum/reagent/drugs/nicotine
	name = REAGENT_NICOTINE
	id = REAGENT_ID_NICOTINE
	dermal_absorption = 0.5 //Nicotine patches are REAL
	description = "A highly addictive stimulant extracted from the tobacco plant."
	taste_description = "sour staleness"
	color = "#181818"
	high_messages = FALSE
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_RECDRUG

/datum/reagent/drugs/nicotine/handle_addiction(mob/living/carbon/M, alien)
	// A copy of the base with withdrawl, but with much less effects, such as vomiting.
	var/current_addiction = M.get_addiction_to_reagent(id)
	// slow degrade
	if(prob(8))
		current_addiction  -= 1
	// withdrawl mechanics
	if(prob(2))
		if(!M.stabilization) //Without stabilization effects
			if(current_addiction < 90 && prob(10))
				to_chat(M, span_warning("[pick("You feel miserable.","You feel nauseous.","You get a raging headache.")]"))
				M.injure(INJURY_PAIN, 5, source = src)
			else if(current_addiction <= 20)
				to_chat(M, span_danger("You feel absolutely awful. You need some [name]. Now."))
				if(prob(10)) //1 in 10 on top of a 1 in 50, so thats a 1 in 500 chance. Seems low enough to not be disruptive.
					M.emote("vomit")
			else if(current_addiction <= 50)
				to_chat(M, span_warning("You're really craving some [name]."))
			else if(current_addiction <= 100)
				to_chat(M, span_notice("You're feeling the need for some [name]."))
			// effects
			if(current_addiction < 60 && prob(20))
				M.emote(pick("pale","shiver","twitch", "cough"))
		else
			if(current_addiction < 90 && prob(10))
				to_chat(M, span_warning("[pick("You feel a slight craving for some [name].","Your stomach feels slightly upset.","You feel a slight pain in your head.")]"))
	if(current_addiction <= 0) //safety
		current_addiction = 0
	return current_addiction
