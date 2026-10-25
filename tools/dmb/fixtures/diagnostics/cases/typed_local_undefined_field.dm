/mob/living/carbon/human
	var/hp = 1

/proc/probe()
	var/mob/living/carbon/human/H = new
	H.hp = 2
	return H.eggs
