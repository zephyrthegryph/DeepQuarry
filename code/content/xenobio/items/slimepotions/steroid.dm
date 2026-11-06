// Makes slimes make more extracts.
/obj/item/slimepotion/steroid/get_mechanics_info(list/additional_information)
	return ..(list("The slime needs to be alive and not an adult for this to work. It will increase the amount of extracts gained by one, up to a max of five per slime. \
	Extra extracts are not passed down to offspring when reproducing.") + additional_information)

/obj/item/slimepotion/steroid
	name = "slime steroid agent"
	desc = "A potent chemical mix that will increase the amount of extracts obtained from harvesting a slime."
	icon_state = "potpurple"

/obj/item/slimepotion/steroid/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(!istype(M, /mob/living/simple_mob/slime/xenobio))
		to_chat(user, span_warning("The stabilizer only works on slimes!"))
		return ..()
	var/mob/living/simple_mob/slime/xenobio/xenobio_slime = M

	if(xenobio_slime.stat == DEAD)
		to_chat(user, span_warning("The slime is dead!"))
		return ..()
	if(xenobio_slime.is_adult) //Can't steroidify adults
		to_chat(user, span_warning("Only baby slimes can use the steroid!"))
		return ..()
	if(xenobio_slime.cores >= 5)
		to_chat(user, span_warning("The slime already has the maximum amount of extract!"))
		return ..()

	to_chat(user, span_notice("You feed the slime the steroid. It will now produce one more extract."))
	xenobio_slime.cores++
	play_sfx(src, SFX_EFFECTS_BUBBLES)
	consume(src, user)
	return ITEM_INTERACT_SUCCESS
