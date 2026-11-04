/datum/viral_trait/viralpower
	name = "Viral Power Multiplier"
	desc = "The vrus has more powerful symptoms. May have unpredictable effects."
	stealth = 2
	resistance = 2
	stage_speed = 2
	transmission = 2
	level = -1
	var/maxpower
	var/powerbudget
	var/scramble = FALSE
	var/used = FALSE

	threshold_descs = list(
		"Transmission 8" = "Constantly scrambles the power of all symptoms.",
		"Stage Speed 8" = "Doubles the power boost."
	)

/datum/viral_trait/viralpower/Start(datum/affliction/contagion/engineered/A)
	if(!..())
		return
	if(A.speed >= 8)
		power = 2
	if(A.transmission >= 8)
		scramble = TRUE

/datum/viral_trait/viralpower/Activate(datum/affliction/contagion/engineered/A)
	if(!..())
		return
	if(!used)
		for(var/datum/viral_trait/S as anything in A.symptoms)
			if(S == src)
				return
			S.power += power
			maxpower += S.power
		if(scramble)
			powerbudget += power
			maxpower += power
			power = 0
		used = TRUE
	if(scramble)
		var/datum/viral_trait/S = pick(A.symptoms)
		if(S == src)
			return
		if(powerbudget && (prob(50) || powerbudget == maxpower))
			S.power += 1
			powerbudget -= 1
		else if(S.power >= 2)
			S.power -= 1
			powerbudget += 1
