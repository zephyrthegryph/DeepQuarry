/obj/item/slimepotion/sapience/get_mechanics_info(list/additional_information)
	return ..(list("The slime or other animal needs to be alive for this to work. The development is not always immediate and may take indeterminate time before effects show.") + additional_information)

/obj/item/slimepotion/sapience
	name = "slime sapience agent"
	desc = "A potent chemical mix that makes an animal capable of developing more advanced, sapient thought."
	icon_state = "potblue"

/obj/item/slimepotion/sapience/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(!istype(M, /mob/living/simple_mob/slime/xenobio))
		to_chat(user, span_warning("The stabilizer only works on slimes!"))
		return ..()
	var/mob/living/simple_mob/slime/xenobio/xenobio_slime = M

	if(xenobio_slime.stat == DEAD)
		to_chat(user, span_warning("The creature is dead!"))
		return ..()
	if(xenobio_slime.ghostjoin)
		to_chat(user, span_warning("The creature is already developing sapience."))
		return ..()
	if(xenobio_slime.ckey)
		to_chat(user, span_warning("The creature is already sapient!"))
		return ..()

	to_chat(user, span_notice("You feed \the [xenobio_slime] the agent. It may now eventually develop proper sapience."))
	xenobio_slime.set_ghostjoin(1)
	registry_join(REGISTRY_GHOST_PODS, xenobio_slime)
	if(!xenobio_slime.vore_active)
		grant(xenobio_slime, granted_verb(/mob/living/simple_mob/proc/animal_nom), xenobio_slime)
	log_and_message_admins("used a sapience potion on a simple mob: [xenobio_slime]. [ADMIN_FLW(src)]", user)
	play_sfx(src, SFX_EFFECTS_BUBBLES)
	consume(src, user)
	return ITEM_INTERACT_SUCCESS
