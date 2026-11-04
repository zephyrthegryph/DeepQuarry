/datum/reagent/ethanol/burnout
	name = REAGENT_BURNOUT
	id = REAGENT_ID_BURNOUT
	description = "A bubbling orange alcoholic fluid that radiates a large amount of heat."
	taste_description = "powerful alcoholic inferno"
	color = "#cc5500"
	taste_mult = 5
	strength = 10
	adj_temp = 10
	targ_temp = 380

	glass_name = REAGENT_BURNOUT
	glass_desc = "A swirling brew of fluids that leaves even the glass itself hot to the touch."

/datum/reagent/ethanol/burnout/affect_ingest(mob/living/carbon/M, alien, removed)
	..()
	// Deathbell effects.
	if(M.species.robo_ethanol_drunk || !(HAS_SYNTHETIC_BIOLOGY(M)))
		if(dose * strength >= strength)
			M.status_adjust(STAT_DIZZY, 24)
		if(dose * strength >= strength * 2.5)
			M.status_at_least(STAT_SLURRING, 30)
		// Simulating heat effects of spice. Without spice. Plant people don't feel it.
		if(species_in(M, SPECIES_TAG_BIT(IS_DIONA) | SPECIES_TAG_BIT(IS_ALRAUNE)))
			return
		else if(ishuman(M))
			var/mob/living/carbon/human/H = M
			if(!H.can_feel_pain())
				return
			else
				if((dose < 5) && (dose == metabolism || prob(5)))
					to_chat(M, span_danger("Your insides feel uncomfortably hot!"))
				if(dose >= 5 && prob(5))
					act_message(M, null, MSG_SELF(pick(span_danger("You feel like your insides are burning!"), span_danger("You feel like your insides are on fire!"), span_danger("You feel like your belly is full of lava!"))), \
						MSG_OTHERS(span_warning("%U% [pick("dry heaves!","coughs!","splutters!")]")))
