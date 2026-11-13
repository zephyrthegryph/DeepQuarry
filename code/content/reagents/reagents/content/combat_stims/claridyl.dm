/datum/reagent/claridyl
	treatment_tags = list(TREAT_TISSUE_REPAIR = 0.25)
	factors = alist(STAT_ANALGESIA = 40, STAT_STABILIZATION = 30)
	species_factors = alist(IS_DIONA = null)
	name = REAGENT_CLARIDYL
	id = REAGENT_ID_CLARIDYL
	description = "Claridyl is an advanced medicine that cures all of your problems. Notice: Clarydil does not claim to fix marriages, car loans, student debt or insomnia and may cause severe pain."
	taste_description = "sugar"
	reagent_state = LIQUID
	color = "#AAAAFF"
	overdose = REAGENTS_OVERDOSE * 100
	metabolism = REM * 0.1
	dermal_absorption = 1
	scannable = 1
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_DRUG
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA)

/datum/reagent/claridyl/affect_blood(mob/living/carbon/M, alien, removed)
	// Its trauma repair is the treatment_tags profile; mending hurts.
	if(M.injury_load(INJURY_CATEGORY_PHYSICAL))
		M.injure(INJURY_PAIN, 1.5, source = src)
	if(prob(0.0001))
		M.injure(INJURY_TOXIN, 50, source = src)//instant crit for tesh

	if(prob(0.1))
		claridyl_side_effect(M, rand(1, 10))

/// One of claridyl's rare side effects (B5: pick() used to evaluate all ten at once).
/datum/reagent/claridyl/proc/claridyl_side_effect(mob/living/carbon/M, which)
	switch(which)
		if(1)
			M.custom_pain("You suddenly feel inexplicably angry!",30)
		if(2)
			M.custom_pain("You suddenly lose your train of thought!",30)
		if(3)
			M.custom_pain("Your mouth feels dry!",30)
		if(4)
			M.status_adjust(STAT_DIZZY, 2)
		if(5)
			M.status_adjust(STAT_WEAKENED, 10)
		if(6)
			M.status_adjust(STAT_STUNNED, 1)
		if(7)
			M.status_adjust(STAT_PARALYZED, 0.1)
		if(8)
			M.status_set(STAT_HALLUCINATING, max(M.status_units(STAT_HALLUCINATING), 2))
		if(9)
			M.flash_eyes()
		else
			M.custom_pain("Your vision becomes blurred!",30)
