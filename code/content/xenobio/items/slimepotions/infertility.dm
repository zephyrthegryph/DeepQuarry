/obj/item/slimepotion/infertility/get_mechanics_info(list/additional_information)
	return ..(list("The slime needs to be alive for this to work. It will reduce the amount of slime babies by 2 (to minimum of 2).") + additional_information)

/obj/item/slimepotion/infertility
	name = "slime infertility agent"
	desc = "A potent chemical mix that will reduce the amount of offspring this slime will have."
	icon_state = "potpurple"

/obj/item/slimepotion/infertility/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(!istype(M, /mob/living/simple_mob/slime/xenobio))
		to_chat(user, span_warning("The stabilizer only works on slimes!"))
		return ..()
	var/mob/living/simple_mob/slime/xenobio/xenobio_slime = M

	if(xenobio_slime.stat == DEAD)
		to_chat(user, span_warning("The slime is dead!"))
		return ..()
	if(xenobio_slime.split_amount <= 2)
		to_chat(user, span_warning("The slime cannot get any less fertile!"))
		return ..()

	to_chat(user, span_notice("You feed the slime the infertility agent. It will now have less offspring."))
	xenobio_slime.split_amount = between(2, xenobio_slime.split_amount - 2, 6)
	play_sfx(src, SFX_EFFECTS_BUBBLES)
	consume(src, user)
	return ITEM_INTERACT_SUCCESS
