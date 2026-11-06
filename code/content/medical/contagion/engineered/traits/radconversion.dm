/datum/viral_trait/radconversion
	name = "Aptopic Culling"
	desc = "The virus causes infected cells to die off when exposed to radiation, causing open wounds to appear on the host's flesh. The end result of this process is the removal of radioactive contamination from the host."
	stealth = 1
	resistance = 1
	stage_speed = 1
	transmission = -2
	level = 8
	threat = 0
	symptom_delay_min = 1
	symptom_delay_max = 1

	var/toxheal = FALSE
	var/cellheal = FALSE

	threshold_descs = list(
		"Stage Speed 6" = "The disease also kills off contaminated cells, converting Toxin damage to Brute damage, at an efficient rate.",
		"Resistance 12" = "The disease also kills off genetically damaged cells, coverting Genetic damage to Burn damage, an inefficient rate."
	)

	suffixes = list(" Aptosis")

/datum/viral_trait/radconversion/severityset(datum/affliction/contagion/engineered/A)
	. = ..()
	if(A.stage_rate >= 6)
		threat -= 1
	if(A.resistance >= 12)
		threat -= 1

/datum/viral_trait/radconversion/Start(datum/affliction/contagion/engineered/A)
	if(!..())
		return
	if(A.stage_rate >= 6)
		toxheal = TRUE
	if(A.resistance >= 12)
		cellheal = TRUE

/datum/viral_trait/radconversion/Activate(datum/affliction/contagion/engineered/A)
	if(!..())
		return
	var/mob/living/carbon/human/H = A.host
	if(A.stage >= 4)
		if(H.radiation)
			H.purge_radiation(max(H.radiation * 0.05, min(10, H.radiation)))
			H.injure(INJURY_CUT, 2)
			if(prob(5))
				if(H.stat != DEAD)
					to_chat(H, span_userdanger("A tear opens in your flesh!"))
				blood_splatter(H.loc, H)
		if(toxheal && H.injury_load(INJURY_CATEGORY_TOXIC))
			H.mend(TREAT_ANTITOXIN, 2)
			H.injure(INJURY_CUT, 1)
			if(prob(5))
				if(H.stat != DEAD)
					to_chat(H, span_userdanger("A tear opens in your flesh!"))
				blood_splatter(H.loc, H)
		if(cellheal && H.injury_load(INJURY_CATEGORY_GENETIC))
			H.mend(TREAT_GENETIC_REPAIR, 1)
			H.injure(INJURY_BURN, 2)
			if(prob(5) && H.stat != DEAD)
				to_chat(H, span_userdanger("A nasty rash appears on your skin!"))
	else if (prob(2) && ((cellheal && H.injury_load(INJURY_CATEGORY_GENETIC)) || (toxheal && H.injury_load(INJURY_CATEGORY_TOXIC)) || H.radiation) && H.stat != DEAD)
		to_chat(H, span_notice("You feel a tingling sensation."))
