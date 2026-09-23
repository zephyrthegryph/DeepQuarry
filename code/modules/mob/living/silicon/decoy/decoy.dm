/mob/living/silicon/decoy
	name = "AI"
	body_type = /datum/body/simple/machine
	icon = 'icons/mob/AI.dmi'//
	icon_state = "ai"
	anchored = TRUE // -- TLE
	canmove = 0

/mob/living/silicon/decoy/Initialize(mapload)
	. = ..(mapload, TRUE)
