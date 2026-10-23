/*
//////////////////////////////////////

Flippinov

	Slightly hidden.
	No change to resistance.
	Increases stage speed.
	Little transmittable.
	Low Level.

BONUS
	Makes the host FLIP.

//////////////////////////////////////
*/

/datum/viral_trait/flip
	name = "Flippinov"
	desc = "The virus hijacks the host's motor system, making them flip incontrollably."
	stealth = 2
	resistance = 0
	stage_speed = 3
	transmission = 1
	symptom_delay_min = 15 SECONDS
	symptom_delay_max = 40 SECONDS
	level = 1
	threat = 0

	prefixes = list("Acrobat's ", "Flippin' ")
	bodies = list("Flip")

/datum/viral_trait/flip/Activate(datum/affliction/contagion/engineered/A)
	if(!..())
		return
	var/mob/living/M = A.host
	M.emote("flip")
