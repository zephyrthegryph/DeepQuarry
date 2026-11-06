/datum/reagent/numbing_enzyme
	factors = alist(STAT_ANALGESIA = 200)
	name = REAGENT_NUMBENZYME
	id = REAGENT_ID_NUMBENZYME
	description = "Some sort of organic painkiller."
	taste_description = "sourness"
	reagent_state = LIQUID
	color = "#800080"
	metabolism = 0.1 //Lasts up to 200 seconds if you give 20u which is OD.
	mrate_static = TRUE
	overdose = 20 //High OD. This is to make numbing bites have somewhat of a downside if you get bit too much. Have to go to medical for dialysis.
	scannable = SCANNABLE_ADVANCED //Let's not have medical mechs able to make an extremely strong organic painkiller
	wiki_flag = WIKI_SPOILER
	supply_conversion_value = REFINERYEXPORT_VALUE_RARE
	industrial_use = REFINERYEXPORT_REASON_DRUG

/datum/reagent/numbing_enzyme/affect_blood(mob/living/carbon/M, alien, removed)
	if(prob(0.01)) //1 in 10000 chance per tick. Extremely rare.
		to_chat(M,span_warning("Your body feels numb as a light, tingly sensation spreads throughout it, like some odd warmth."))
	//Not noted here, but a movement debuff of 1.5 is handed out in human_movement.dm when numbing_enzyme is in a person's bloodstream!

/datum/reagent/numbing_enzyme/overdose(mob/living/carbon/M, alien)
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		if(prob(1))
			to_chat(H,span_warning("Your entire body feels numb and the sensation of pins and needles continually assaults you. You blink and the next thing you know, your legs give out momentarily!"))
			H.status_adjust(STAT_WEAKENED, 5) //Fall onto the floor for a few moments.
			H.status_at_least(STAT_CONFUSED, 15) //Be unable to walk correctly for a bit longer.
		if(prob(1))
			if(H.losebreath() <= 1 && H.oxygen_debt() <= 20) //Let's not suffocate them to the point that they pass out.
				to_chat(H,span_warning("You feel a sharp stabbing pain in your chest and quickly realize that your lungs have stopped functioning!")) //Let's scare them a bit.
				H.set_losebreath(10)
		if(prob(2))
			to_chat(H,span_warning("You feel a dull pain behind your eyes and at the back of your head..."))
			H.status_adjust(STAT_HALLUCINATING, 20) //It messes with your mind for some reason.
			H.status_adjust(STAT_BLURRY, 20) //Groggy vision for a small bit.
		if(prob(3))
			to_chat(H,span_warning("You shiver, your body continually being assaulted by the sensation of pins and needles."))
			H.emote("shiver")
			H.status_adjust(STAT_JITTERY, 10)
		if(prob(3))
			to_chat(H,span_warning("Your tongue feels numb and unresponsive."))
			H.status_adjust(STAT_STUTTERING, 20)
