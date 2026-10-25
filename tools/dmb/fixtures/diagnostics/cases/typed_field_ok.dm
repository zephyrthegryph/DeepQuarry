/mob/living/carbon/human
	var/hp = 1

/proc/probe(mob/living/carbon/human/H)
	var/x = H.hp
	return x + H:hp
