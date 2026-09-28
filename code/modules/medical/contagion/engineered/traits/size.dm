/*
//////////////////////////////////////

Mass Revectoring

	Very noticeable.
	Increases resistance slightly.
	Increases stage speed.
	Decreases transmittablity
	Intense level.

BONUS
	Changes the size of the host.

//////////////////////////////////////
*/

/datum/viral_trait/size
	name = "Mass Revectoring"
	desc = "The virus causes distortion of the host's body, causing it to change size."
	stealth = 1
	resistance = 0
	stage_speed = 2
	transmission = 2
	level = 4
	threat = 0
	symptom_delay_min = 20 SECONDS
	symptom_delay_max = 60 SECONDS
	var/min_size = RESIZE_MINIMUM
	var/max_size = RESIZE_MAXIMUM

/datum/viral_trait/size/Activate(datum/affliction/contagion/engineered/A)
	if(!..())
		return
	var/mob/living/M = A.host
	switch(A.stage)
		if(4, 5)
			M.emote("twitch")
			M.resize(pick(min_size, max_size))

/datum/viral_trait/size/grow
	name = "Enlargement Disorder"
	min_size = RESIZE_NORMAL
	max_size = RESIZE_MAXIMUM

	prefixes = list("Growing ", "Gigantic ")

/datum/viral_trait/size/shrink
	name = "Dwindling Malady"
	min_size = RESIZE_MINIMUM
	max_size = RESIZE_NORMAL

	prefixes = list("Shrinking ", "Micro-")
