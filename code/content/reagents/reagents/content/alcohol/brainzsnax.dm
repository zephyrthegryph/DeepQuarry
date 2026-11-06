////////////////START BrainzSnax Reagents////////////////

/datum/reagent/nutriment/protein/brainzsnax
	name = REAGENT_BRAINPROTEIN
	id = REAGENT_ID_BRAINPROTEIN
	taste_description = "fatty, mushy meat and allspice"
	color = "#caa3c9"
	wiki_flag = WIKI_FOOD|WIKI_SPOILER

/datum/reagent/nutriment/protein/brainzsnax/affect_ingest(mob/living/carbon/M, alien, removed)
	..()
	if(prob(5) && !species_in(M, REAGENT_PRION_IMMUNE_SPECIES))
		M.injure(INJURY_NEURAL, removed, source = src) //Any other species risks prion disease.
		M.status_at_least(STAT_CONFUSED, 5)
		M.status_at_least(STAT_HALLUCINATING, 25)

	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		var/datum/xenochimera/xc = M.get_xenochimera_state()
		if(xc && xc.feral > 0 && nutrition_of(H) > 150 && H.current_pain() < 20 && H.status_units(STAT_JITTERY) < 100) //Same check as feral triggers to stop them immediately re-feralling
			xc.set_feral(xc.feral - (removed * 3)) //Should calm them down quick, provided they're actually in a state to STAY calm.
			if(xc.feral <=0) //Check if they're unferalled
				xc.set_feral(0)
				to_chat(H, span_info("Your mind starts to clear, soothed into a state of clarity as your senses return."))
				log_and_message_admins("is no longer feral.", H)

/datum/reagent/nutriment/protein/brainzsnax/red
	id = REAGENT_ID_REDBRAINPROTEIN
	taste_description = "fatty, mushy meat and cheap tomato sauce"
	color = "#a6898d"
