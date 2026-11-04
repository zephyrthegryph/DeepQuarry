/obj/item/slimepotion/death
	name = "slime death agent"
	desc = "A potent chemical mix that will instantly kill a slime."
	icon_state = "potblue"

/obj/item/slimepotion/death/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(!istype(M, /mob/living/simple_mob/slime/xenobio))
		to_chat(user, span_warning("The stabilizer only works on slimes!"))
		return ..()
	var/mob/living/simple_mob/slime/xenobio/xenobio_slime = M

	if(xenobio_slime.stat == DEAD)
		to_chat(user, span_warning("The slime is already dead!"))
		return ..()

	to_chat(user, span_notice("You feed the slime the death agent. Its face flashes pain of betrayal before it goes still."))
	xenobio_slime.injure(INJURY_TOXIN, xenobio_slime.get_endurance() * 5, source = src, flags = INJURE_IGNORE_RESISTANCE)
	play_sfx(src, SFX_EFFECTS_BUBBLES)
	consume(src, user)
	return ITEM_INTERACT_SUCCESS
