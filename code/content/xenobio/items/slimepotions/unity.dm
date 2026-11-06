// Makes slimes not try to murder other slime colors.
/obj/item/slimepotion/unity/get_mechanics_info(list/additional_information)
	return ..(list("The slime needs to be alive for this to work. Slimes unified will not attack or be attacked by other colored slimes, and this will \
	carry over to offspring when reproducing.") + additional_information)

/obj/item/slimepotion/unity
	name = "slime unity agent"
	desc = "A potent chemical mix that makes the slime feel and be seen as all the colors at once, and as a result not be considered an enemy to any other color."
	icon_state = "potpink"

/obj/item/slimepotion/unity/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(!istype(M, /mob/living/simple_mob/slime/xenobio))
		to_chat(user, span_warning("The stabilizer only works on slimes!"))
		return ..()
	var/mob/living/simple_mob/slime/xenobio/xenobio_slime = M

	if(xenobio_slime.stat == DEAD)
		to_chat(user, span_warning("The slime is dead!"))
		return ..()
	if(xenobio_slime.unity == TRUE)
		to_chat(user, span_warning("The slime is already unified!"))
		return ..()

	to_chat(user, span_notice("You feed the slime the agent. It will now be friendly to all other slimes."))
	to_chat(xenobio_slime, span_notice("\The [user] feeds you \the [src], and you suspect that all the other slimes will be \
	your friends, at least if you don't attack them first."))
	xenobio_slime.unify()
	play_sfx(src, SFX_EFFECTS_BUBBLES)
	consume(src, user)
	return ITEM_INTERACT_SUCCESS
