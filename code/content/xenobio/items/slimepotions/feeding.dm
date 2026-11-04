// Feeds the slime instantly.
/obj/item/slimepotion/feeding/get_mechanics_info(list/additional_information)
	return ..(list("The slime needs to be alive for this to work. It will instantly grow the slime enough to reproduce.") + additional_information)

/obj/item/slimepotion/feeding
	name = "slime feeding agent"
	desc = "A potent chemical mix that will instantly sediate the slime."
	icon_state = "potorange"

/obj/item/slimepotion/feeding/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(!istype(M, /mob/living/simple_mob/slime/xenobio))
		to_chat(user, span_warning("The stabilizer only works on slimes!"))
		return ..()
	var/mob/living/simple_mob/slime/xenobio/xenobio_slime = M

	if(xenobio_slime.stat == DEAD)
		to_chat(user, span_warning("The slime is dead!"))
		return ..()

	to_chat(user, span_notice("You feed the slime the feeding agent. It will now instantly reproduce."))
	xenobio_slime.amount_grown = 10
	xenobio_slime.make_adult()
	xenobio_slime.amount_grown = 10
	xenobio_slime.reproduce()
	play_sfx(src, SFX_EFFECTS_BUBBLES)
	consume(src, user)
	return ITEM_INTERACT_SUCCESS
