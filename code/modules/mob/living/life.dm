/mob/living/proc/update_pulling()
	if(PULLING(src))
		if(incapacitated())
			stop_pulling()

/mob/living/proc/update_sight()
	if(!seedarkness)
		see_invisible = SEE_INVISIBLE_NOLIGHTING
	else
		see_invisible = initial(see_invisible)

	sight = initial(sight)
	sight |= factor(BF_SIGHT_FLAGS)

	return
