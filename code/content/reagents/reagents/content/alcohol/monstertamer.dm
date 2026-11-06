/datum/reagent/ethanol/monstertamer
	name = REAGENT_MONSTERTAMER
	id = REAGENT_ID_MONSTERTAMER
	description = "A questionably-delicious blend of a carnivore's favorite food and a potent neural depressant."
	taste_description = "the gross yet satisfying combination of chewing on a raw steak while downing a shot of whiskey"
	strength = 50
	color = "#d3785d"
	metabolism = REM * 2.5 // about right for mixing nutriment and ethanol.
	var/alt_nutriment_factor = 5 //half as much as protein since it's half protein.
	//using a new variable instead of nutriment_factor so we can call ..() without that adding nutrition for us without taking factors for protein into account

	glass_name = REAGENT_MONSTERTAMER
	glass_desc = "This looks like a vaguely-alcoholic slurry of meat. Gross."

/datum/reagent/ethanol/monstertamer/affect_ingest(mob/living/carbon/M, alien, removed)
	..()

	if(!(HAS_SYNTHETIC_BIOLOGY(M)))
		if(M.species.organic_food_coeff) //it's still food!
			switch(alien)
				if(IS_DIONA) //Diona don't get any nutrition from nutriment or protein.
					pass()
				if(IS_SKRELL)
					M.injure(INJURY_TOXIN, 0.25 * removed, source = src)  //Equivalent to half as much protein, since it's half protein.
				if(IS_TESHARI)
					M.adjust_nutrition(alt_nutriment_factor * 1.2 * removed) //Give them the same nutrition they would get from protein.
				if(IS_UNATHI)
					M.adjust_nutrition(alt_nutriment_factor * 1.125 * removed) //Give them the same nutrition they would get from protein.
					//Takes into account the 0.5 factor for all nutriment which is applied on top of the 2.25 factor for protein.
				//Chimera don't need their own case here since their factors for nutriment and protein cancel out.
				else
					M.adjust_nutrition(alt_nutriment_factor * removed)
		if(ishuman(M))
			var/mob/living/carbon/human/H = M
			var/datum/xenochimera/xc = M.get_xenochimera_state()
			if(xc && xc.feral > 0 && nutrition_of(H) > 150 && H.current_pain() < 20 && H.status_units(STAT_JITTERY) < 100) //Same check as feral triggers to stop them immediately re-feralling
				xc.set_feral(xc.feral - (removed * 3)) // should calm them down quick, provided they're actually in a state to STAY calm.
				if (xc.feral <=0) //check if they're unferalled
					xc.set_feral(0)
					to_chat(H, span_info("Your mind starts to clear, soothed into a state of clarity as your senses return."))
					log_and_message_admins("is no longer feral.", H)

/datum/reagent/ethanol/monstertamer/affect_blood(mob/living/carbon/M, alien, removed)
	..()
	if(M.species.organic_food_coeff)
		if(species_in(M, REAGENT_BLOOD_FED_SPECIES)) //slimes and chimera can get nutrition from injected nutriment and protein
			M.adjust_nutrition(alt_nutriment_factor * removed)
