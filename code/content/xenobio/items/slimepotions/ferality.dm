/obj/item/slimepotion/ferality
	name = "slime ferality agent"
	desc = "A potent chemical mix that will make a slime untamable."
	icon_state = "potred"

/obj/item/slimepotion/ferality/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(!istype(M, /mob/living/simple_mob/slime/xenobio))
		to_chat(user, span_warning("The stabilizer only works on slimes!"))
		return ..()
	var/mob/living/simple_mob/slime/xenobio/xenobio_slime = M

	if(xenobio_slime.stat == DEAD)
		to_chat(user, span_warning("The slime is already dead!"))
		return ..()
	if(xenobio_slime.untamable && xenobio_slime.untamable_inheirit)
		to_chat(user, span_warning("The slime is already untamable!"))
		return ..()

	to_chat(user, span_notice("You feed the slime the death agent. It will now only get angrier at taming attempts."))
	xenobio_slime.untamable = TRUE
	xenobio_slime.untamable_inheirit = TRUE
	play_sfx(src, SFX_EFFECTS_BUBBLES)
	consume(src, user)
	return ITEM_INTERACT_SUCCESS
