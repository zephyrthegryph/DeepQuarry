/mob/living/carbon/alien/on_death(gibbed)
	. = ..()
	if(!gibbed && dead_icon)
		icon_state = dead_icon
