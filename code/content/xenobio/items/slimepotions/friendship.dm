// User befriends the slime with this.
/obj/item/slimepotion/friendship/get_mechanics_info(list/additional_information)
	return ..(list("The slime or other animal needs to be alive for this to work. The slime this is applied to will consider the user \
	their 'friend', and will never attack them. This might also work on other things besides slimes.") + additional_information)

/obj/item/slimepotion/friendship
	name = "slime friendship agent"
	desc = "A potent chemical mix that makes an animal deeply loyal to the the specific entity which feeds them this agent."
	icon_state = "potlightpink"

/obj/item/slimepotion/friendship/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(!istype(M, /mob/living/simple_mob))
		to_chat(user, span_warning("The agent only works on creatures!"))
		return ..()
	var/mob/living/simple_mob/SM = M

	if(!(kind_of(SM).mob_class & (MOB_CLASS_SLIME|MOB_CLASS_ANIMAL))) // So you can't use this on Russians/syndies/hivebots/etc.
		to_chat(user, span_warning("\The [M] only works on slimes and animals."))
		return ..()
	if(SM.stat == DEAD)
		to_chat(user, span_warning("\The [M] is dead!"))
		return ..()
	if(user in SM.friends)
		to_chat(user, span_warning("\The [M] is already loyal to you!"))
		return ..()
	if(!(SM.ai_brain != null))
		to_chat(user, span_warning("\The [M] is too strong-willed for this to affect them."))
		return ..()

	var/datum/ai_brain/AI = SM.ai_brain

	to_chat(user, span_notice("You feed \the [SM] the agent. It will now be your best friend."))
	to_chat(SM, span_notice("\The [user] feeds you \the [src], and feel that \the [user] wants to be best friends with you."))
	rel_add(SM, nameof(SM.friends), user)
	AI.remove_target() // So hostile things stop attacking people even if not hostile anymore.
	play_sfx(src, SFX_EFFECTS_BUBBLES)
	consume(src, user)
	return ITEM_INTERACT_SUCCESS
