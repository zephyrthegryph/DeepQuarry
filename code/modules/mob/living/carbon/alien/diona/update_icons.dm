/mob/living/carbon/alien/diona/update_icons()

	if(stat == DEAD)
		icon_state = "[initial(icon_state)]_dead"
	else if(lying || resting || has_status(EFFECT_STUNNED))
		icon_state = "[initial(icon_state)]_sleep"
	else
		icon_state = "[initial(icon_state)]"

	cut_overlays()
	if(hat)
		add_overlay(get_hat_icon(hat, 0, -8))
