/*
//////////////////////////////////////
Viral adaptation

	Moderate stealth boost.
	Major Increases to resistance.
	Reduces stage speed.
	No change to transmission
	Critical Level.

BONUS
	Extremely useful for buffing viruses

//////////////////////////////////////
*/
/datum/viral_trait/viraladaptation
	name = "Viral Self-Adaptation"
	desc = "The virus mimics the function of normal body cells, becoming harder to spot and to eradicate, but reducing it's speed."
	stealth = 3
	resistance = 5
	stage_speed = -3
	transmission = 0
	level = 4
	threat = 0

	prefixes = list("Chronic ")

/*
//////////////////////////////////////
Viral evolution

	Moderate stealth reduction.
	Major decreases to resistance.
	increases stage speed.
	increase to transmission
	Critical Level.

BONUS
	Extremely useful for buffing viruses

//////////////////////////////////////
*/
/datum/viral_trait/viralevolution
	name = "Viral Evolutionary Acceleration"
	desc = "The virus quickly adapts to spread as fast as possible both outside and inside a host. This, however, makes the virus easier to spot, and les able to fight off a cure."
	stealth = -2
	resistance = -3
	stage_speed = 5
	transmission = 3
	level = 4

	prefixes = list("Unstable ")

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

/datum/viral_trait/viralreverse
	name = "Viral Aggressive Metabolism"
	desc = "The virus sacrifices its long term survivability to nearly instantly fully spread inside a host. \
	The virus will start at the last stage, but will eventually decay and die off by itself."
	stealth = 1
	resistance = 1
	stage_speed = 3
	transmission = -4
	level = 4
	symptom_delay_min = 1
	symptom_delay_max = 1
	threshold_descs = list(
		"Stage Speed" = "Highest between these determines the amount before self-curing.",
		"Stealth 4" = "Doubles the time before the virus self-cures."
	)

	var/time_to_cure

	prefixes = list("Spontaneous ")

/datum/viral_trait/viralreverse/Activate(datum/affliction/contagion/engineered/A)
	if(!..())
		return
	if(time_to_cure > 0)
		time_to_cure--
	else
		var/mob/living/M = A.host
		Heal(M, A)

/datum/viral_trait/viralreverse/proc/Heal(mob/living/M, datum/affliction/contagion/engineered/A)
	A.set_stage(A.stage - 1)
	if(A.stage < 2)
		to_chat(M, span_notice("You suddenly feel healthy."))
		A.cure(FALSE)

/datum/viral_trait/viralreverse/Start(datum/affliction/contagion/engineered/A)
	if(!..())
		return
	A.set_stage(5)
	if(A.stealth >= 4)
		power = 2
	time_to_cure = max(A.resistance, A.stage_rate) * 10 * power

/datum/viral_trait/viralincubate
	name = "Viral Suspended Animation"
	desc = "The virus has very little effect until it reaches its final stage"
	stealth = 4
	resistance = -2
	stage_speed = -2
	transmission = 1
	level = 4
	symptom_delay_min = 1
	symptom_delay_max = 1
	var/list/captives
	var/used = FALSE

/datum/viral_trait/viralincubate/Activate(datum/affliction/contagion/engineered/A)
	if(!..())
		return
	if(A.stage >= 5)
		for(var/datum/viral_trait/S as anything in captives)
			S.stopped = FALSE
			rel_remove(src, nameof(captives), S)
		if(!LAZYLEN(captives))
			stopped = TRUE
	else if(!used)
		for(var/datum/viral_trait/S as anything in A.symptoms)
			if(S.neutered)
				continue
			if(S == src)
				continue
			S.stopped = TRUE
			rel_add(src, nameof(captives), S)
		used = TRUE
