/mob/living/carbon/alien/on_death(gibbed)
	. = ..()
	if(!gibbed && dead_icon)
		set_icon_state(dead_icon)
