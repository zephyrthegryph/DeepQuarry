/// The hat it wears sits on its head; its sprite follows its state.
/mob/living/carbon/alien/diona/draw(datum/look/look)
	..()
	if(stat == DEAD)
		look.state("[initial(icon_state)]_dead")
	else if(lying || resting || has_status(STAT_STUNNED))
		look.state("[initial(icon_state)]_sleep")
	else
		look.state("[initial(icon_state)]")
	look.watch(hat)
	if(hat)
		look.overlay(get_hat_icon(hat, 0, -8))
