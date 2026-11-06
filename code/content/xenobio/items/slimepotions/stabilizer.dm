// Makes slimes less likely to mutate.
/obj/item/slimepotion/stabilizer/get_mechanics_info(list/additional_information)
	return ..(list("The slime needs to be alive for this to work. It will reduce the chances of mutation by 15%.") + additional_information)

/obj/item/slimepotion/stabilizer
	name = "slime stabilizer agent"
	desc = "A potent chemical mix that will reduce the chance of a slime mutating."
	icon_state = "potcyan"

/obj/item/slimepotion/stabilizer/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(!istype(M, /mob/living/simple_mob/slime/xenobio))
		to_chat(user, span_warning("The stabilizer only works on slimes!"))
		return ..()
	var/mob/living/simple_mob/slime/xenobio/xenobio_slime = M

	if(xenobio_slime.stat == DEAD)
		to_chat(user, span_warning("The slime is dead!"))
		return ..()
	if(xenobio_slime.mutation_chance == 0)
		to_chat(user, span_warning("The slime already has no chance of mutating!"))
		return ..()

	to_chat(user, span_notice("You feed the slime the stabilizer. It is now less likely to mutate."))
	xenobio_slime.mutation_chance = between(0, xenobio_slime.mutation_chance - 15, 100)
	play_sfx(src, SFX_EFFECTS_BUBBLES)
	consume(src, user)
	return ITEM_INTERACT_SUCCESS
