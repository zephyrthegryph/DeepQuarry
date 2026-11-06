/*
//////////////////////////////////////

Sneezing

	Very Noticable.
	Increases resistance.
	Doesn't increase stage speed.
	Very transmittable.
	Low Level.

Bonus
	Forces a spread type of AIRBORNE
	with extra range!

//////////////////////////////////////
*/

/datum/viral_trait/sneeze
	name = "Sneezing"
	desc = "The virus causes irritation of the nasal cavity, making the host sneeze occasionally."
	stealth = -2
	resistance = 3
	stage_speed = 0
	transmission = 4
	symptom_delay_min = 15 SECONDS
	symptom_delay_max = 40 SECONDS
	level = 1
	threat = 0

	var/infective = FALSE

	threshold_descs = list(
		"Stealth 4" = "The symptom remains hidden until active.",
		"Trasmission 12" = "The host may spread the disease through sneezing."
	)

	prefixes = list("Nasal ")
	bodies = list("Cold")

/datum/viral_trait/sneeze/Start(datum/affliction/contagion/engineered/A)
	if(!..())
		return
	if(A.stealth >= 4)
		supress_warning = TRUE
	if(A.transmission >= 12)
		infective = TRUE

/datum/viral_trait/sneeze/Activate(datum/affliction/contagion/engineered/A)
	if(!..())
		return
	var/mob/living/M = A.host
	switch(A.stage)
		if(1, 2, 3)
			if(!supress_warning)
				M.emote("sniff")
		else
			M.emote("sneeze")
			if(infective && !(A.spread_flags & DISEASE_SPREAD_FALTERED))
				after(A, 2 SECONDS, TYPE_PROC_REF(/datum/affliction/contagion, spread), with = list(4))
