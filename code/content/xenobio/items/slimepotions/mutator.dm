// The opposite, makes the slime more likely to mutate.
/obj/item/slimepotion/mutator/get_mechanics_info(list/additional_information)
	return ..(list("The slime needs to be alive for this to work. It will increase the chances of mutation by 12%.") + additional_information)

/obj/item/slimepotion/mutator
	name = "slime mutator agent"
	desc = "A potent chemical mix that will increase the chance of a slime mutating."
	icon_state = "potred"

/obj/item/slimepotion/mutator/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(!istype(M, /mob/living/simple_mob/slime/xenobio))
		to_chat(user, span_warning("The stabilizer only works on slimes!"))
		return ..()
	var/mob/living/simple_mob/slime/xenobio/xenobio_slime = M

	if(xenobio_slime.stat == DEAD)
		to_chat(user, span_warning("The slime is dead!"))
		return ..()
	if(xenobio_slime.mutation_chance == 100)
		to_chat(user, span_warning("The slime is already guaranteed to mutate!"))
		return ..()

	to_chat(user, span_notice("You feed the slime the mutator. It is now more likely to mutate."))
	xenobio_slime.mutation_chance = between(0, xenobio_slime.mutation_chance + 12, 100)
	play_sfx(src, SFX_EFFECTS_BUBBLES)
	consume(src, user)
	return ITEM_INTERACT_SUCCESS
