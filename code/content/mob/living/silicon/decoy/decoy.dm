/mob/living/silicon/decoy
	name = "AI"
	body_type = /datum/body/simple/machine
	icon = 'icons/mob/AI.dmi'//
	icon_state = "ai"
	anchored = TRUE // -- TLE
	canmove = 0

CAPABILITIES(/mob/living/silicon/decoy)
	configure(living_rules(life_set = LIFE_SET_DECOY))

/mob/living/silicon/decoy
	decoy = TRUE
