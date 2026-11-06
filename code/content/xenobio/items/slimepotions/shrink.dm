/obj/item/slimepotion/shrink
	name = "slime shrinking agent"
	desc = "A potent chemical mix that will turn adult slime into a baby one."
	icon_state = "potpurple"

/obj/item/slimepotion/shrink/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(!istype(M, /mob/living/simple_mob/slime/xenobio))
		to_chat(user, span_warning("The stabilizer only works on slimes!"))
		return ..()
	var/mob/living/simple_mob/slime/xenobio/xenobio_slime = M

	if(xenobio_slime.stat == DEAD)
		to_chat(user, span_warning("The slime is dead!"))
		return ..()
	if(!(xenobio_slime.is_adult))
		to_chat(user, span_warning("The slime is already a baby!"))
		return ..()

	to_chat(user, span_notice("You feed the slime the shrinking agent. It is now back to being a baby."))
	xenobio_slime.make_baby()
	play_sfx(src, SFX_EFFECTS_BUBBLES)
	consume(src, user)
	return ITEM_INTERACT_SUCCESS
