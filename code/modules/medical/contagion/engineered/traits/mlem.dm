/*
//////////////////////////////////////

Mlemingtong

	Not noticable or unnoticable.
	Resistant.
	Increases stage speed.
	Little transmittable.
	Low Level.

BONUS
	Mlem. Mlem. Mlem.

//////////////////////////////////////
*/

/datum/viral_trait/mlem
	name = "Mlemington"
	desc = "The host uncontrollably licks their nose. Mlem."
	stealth = 0
	resistance = 3
	stage_speed = 3
	transmission = 1
	level = 1
	threat = 1

	var/infective = FALSE

	threshold_descs = list(
		"Resistance 5" = "The host may occasionally go on a mlemming spree.",
		"Transmission 8" = "The host will spread the virus through saliva when mlemming."
	)

	prefixes = list("Mlemington's ", "Licking-")
	bodies = list("Mlem", "Lick")

/datum/viral_trait/mlem/severityset(datum/affliction/contagion/engineered/A)
	. = ..()
	if(A.transmission >= 8)
		infective = TRUE
		threat += 1

/datum/viral_trait/mlem/Start(datum/affliction/contagion/engineered/A)
	if(!..())
		return
	if(A.resistance >= 5)
		power = 1.5

/datum/viral_trait/mlem/Activate(datum/affliction/contagion/engineered/A)
	if(!..())
		return
	var/mob/living/M = A.host
	if(M.stat == DEAD)
		return
	switch(A.stage)
		if(1, 2, 3)
			if(prob(base_message_chance))
				to_chat(M, span_notice("You think about licking your nose..."))
		else
			M.emote("mlem")
			if(power >= 1.5)
				M.emote("mlem")
				if(A.resistance >= 5)
					M.emote("mlem")
					om_after(M, 2 SECONDS, TYPE_PROC_REF(/mob, emote), "mlem")
					om_after(M, 5 SECONDS, TYPE_PROC_REF(/mob, emote), "mlem")
					om_after(M, 8 SECONDS, TYPE_PROC_REF(/mob, emote), "mlem")
