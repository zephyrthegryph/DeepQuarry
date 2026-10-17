/mob/living/carbon/alien/diona/update_icons()

	if(stat == DEAD)
		set_icon_state("[initial(icon_state)]_dead")
	else if(lying || resting || has_status(STAT_STUNNED))
		set_icon_state("[initial(icon_state)]_sleep")
	else
		set_icon_state("[initial(icon_state)]")

/// The hat it wears sits on its head.
/mob/living/carbon/alien/diona/draw(datum/look/look)
	..()
	look.watch(hat)
	if(hat)
		look.overlay(get_hat_icon(hat, 0, -8))
