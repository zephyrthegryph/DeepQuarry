/mob/living/simple_mob

/mob/living/simple_mob/can_butcher(mob/user, obj/item/I)	// Override for special butchering checks.
	. = ..()

	if(. && (!is_sharp(I) || !has_edge(I)))
		return FALSE

CAPABILITIES(/mob/living/simple_mob)
	configure(butchery_config(gib_on_butchery = TRUE, butchery_drops_organs = FALSE))
