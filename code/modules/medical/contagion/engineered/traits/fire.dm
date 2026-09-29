/*
//////////////////////////////////////

Spontaneous Combustion

	Slightly hidden.
	Lowers resistance tremendously.
	Decreases stage tremendously.
	Decreases transmittablity tremendously.
	Fatal Level.

Bonus
	Ignites infected mob.

//////////////////////////////////////
*/

/datum/viral_trait/fire
	name = "Spontaneous Combustion"
	desc = "The virus turns fat into an extremely flammable compound, and raises the body's temperature, making the host burst into flames spontaneously."
	stealth = 1
	resistance = -1
	stage_speed = -2
	transmission = -1
	level = 7
	threat = 4

	base_message_chance = 20
	symptom_delay_min = 40 SECONDS
	symptom_delay_max = 85 SECONDS

	var/infective = FALSE

	threshold_descs = list(
		"Stage Speed 4" = "Increases the intensity of the flames.",
		"Stage Speed 8" = "Further increases the intensity of the flames.",
		"Transmission 8" = "Host will spread the virus through skin flake when bursting into flames.",
		"Stealth 4" = "The symptom remains hidden until active."
	)

	prefixes = list("Burning ")
	bodies = list("Combustion")
	suffixes = list(" Combustion")

/datum/viral_trait/fire/Start(datum/affliction/contagion/engineered/A)
	if(!..())
		return
	if(A.stage_rate >= 4)
		power = 1.5
		if(A.stage_rate >= 8)
			power = 2
	if(A.stealth >= 4)
		supress_warning = TRUE
	if(A.transmission >= 8)
		infective = TRUE

/datum/viral_trait/fire/Activate(datum/affliction/contagion/engineered/A)
	if(!..())
		return
	var/mob/living/M = A.host
	switch(A.stage)
		if(3)
			if(prob(base_message_chance) && !supress_warning && M.stat != DEAD)
				to_chat(M, span_warning(pick("You feel hot.", "You hear a crackling noise.", "You smell smoke.")))
		if(4)
			Firestacks_stage_4(M, A)
			M.ignite_mob()
			to_chat(M, span_userdanger("Your skin bursts into flames!"))
			M.emote("scream")
		if(5)
			Firestacks_stage_5(M, A)
			M.ignite_mob()
			if(M.stat != DEAD)
				to_chat(M, span_userdanger("Your skin erupts into an inferno!"))
				M.emote("scream")
	return

/datum/viral_trait/fire/proc/Firestacks_stage_4(mob/living/M, datum/affliction/contagion/engineered/A)
	M.adjust_fire_stacks(1 * power)
	M.injure(INJURY_BURN, 2 * power)
	if(infective && !(A.spread_flags & DISEASE_SPREAD_FALTERED))
		act_message(M, null, others = span_danger("%U% bursts into flames, spreading burning sparks about the area!"))
	return TRUE

/datum/viral_trait/fire/proc/Firestacks_stage_5(mob/living/M, datum/affliction/contagion/engineered/A)
	M.adjust_fire_stacks(3 * power)
	M.injure(INJURY_BURN, 5 * power)
	if(infective && !(A.spread_flags & DISEASE_SPREAD_FALTERED))
		act_message(M, null, others = span_danger("%U% bursts into flames, spreading burning sparks about the area!"))
	return TRUE
