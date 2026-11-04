/obj/item/slimepotion/obedience/get_mechanics_info(list/additional_information)
	return ..(list("The target needs to be alive and currently misbehaving. Effect is equivalent to very strong discipline.") + additional_information)

/obj/item/slimepotion/obedience
	name = "slime obedience agent"
	desc = "A potent chemical mix that makes slime extremely obedient."
	icon_state = "potlightpink"

/obj/item/slimepotion/obedience/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(!istype(M, /mob/living/simple_mob/slime/xenobio))
		to_chat(user, span_warning("The stabilizer only works on slimes!"))
		return ..()
	var/mob/living/simple_mob/slime/xenobio/xenobio_slime = M

	if(xenobio_slime.stat == DEAD)
		to_chat(user, span_warning("The slime is dead!"))
		return ..()

	to_chat(user, span_notice("You feed the slime the agent. It has been disciplined, for better or worse..."))
	var/justified = xenobio_slime.is_justified_to_discipline()
	xenobio_slime.adjust_discipline(10)
	if(xenobio_slime.slime_state && justified)
		xenobio_slime.slime_state.obedience = 10
	play_sfx(src, SFX_EFFECTS_BUBBLES)
	consume(src, user)
	return ITEM_INTERACT_SUCCESS
