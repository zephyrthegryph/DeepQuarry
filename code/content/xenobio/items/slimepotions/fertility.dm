/obj/item/slimepotion/fertility/get_mechanics_info(list/additional_information)
	return ..(list("The slime needs to be alive for this to work. It will increase the amount of slime babies by 2 (to maximum of 6).") + additional_information)

/obj/item/slimepotion/fertility
	name = "slime fertility agent"
	desc = "A potent chemical mix that will increase the amount of offspring this slime will have."
	icon_state = "potpurple"

/obj/item/slimepotion/fertility/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(!istype(M, /mob/living/simple_mob/slime/xenobio))
		to_chat(user, span_warning("The stabilizer only works on slimes!"))
		return ..()
	var/mob/living/simple_mob/slime/xenobio/xenobio_slime = M

	if(xenobio_slime.stat == DEAD)
		to_chat(user, span_warning("The slime is dead!"))
		return ..()
	if(xenobio_slime.split_amount >= 6)
		to_chat(user, span_warning("The slime cannot get any more fertile!"))
		return ..()

	to_chat(user, span_notice("You feed the slime the fertility agent. It will now have more offspring."))
	xenobio_slime.split_amount = between(2, xenobio_slime.split_amount + 2, 6)
	play_sfx(src, SFX_EFFECTS_BUBBLES)
	consume(src, user)
	return ITEM_INTERACT_SUCCESS
