/// A young alien's sprite follows its growth and its state.
/mob/living/carbon/alien/draw(datum/look/look)
	..()
	var/state = 0
	if(amount_grown > max_grown*0.75)
		state = 2
	else if(amount_grown > max_grown*0.25)
		state = 1

	if(stat == DEAD)
		look.state("[initial(icon_state)][state]_dead")
	else if (has_status(STAT_STUNNED))
		look.state("[initial(icon_state)][state]_stun")
	else if(lying || resting)
		look.state("[initial(icon_state)][state]_sleep")
	else
		look.state("[initial(icon_state)][state]")
