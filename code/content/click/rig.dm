/// Whether `action` on `A` engaged a hardsuit module instead of its usual effect.
/mob/living/proc/hardsuit_intercepts(action, atom/A)
	var/list/actions = HARDSUIT_CLICK_ACTIONS
	return client && actions[preference_or_default(/datum/preference/choiced/hardsuit_activation)] == action && HardsuitClickOn(A)

/mob/living/action_swap_hands(atom/A)
	if(hardsuit_intercepts(INPUT_ACTION_SWAP_HANDS, A))
		return
	..()

// The only /mob/living action_alternate: hardsuit activation first, then ventcrawl entry.
/mob/living/action_alternate(atom/A)
	if(hardsuit_intercepts(INPUT_ACTION_ALTERNATE, A))
		return
	if(is_type_in_list(A, GLOB.ventcrawl_machinery))
		handle_ventcrawl(A)
		return
	..()

/mob/living/action_pull(atom/A)
	if(hardsuit_intercepts(INPUT_ACTION_PULL, A))
		return
	..()

/mob/living/proc/can_use_rig()
	return 0

/mob/living/carbon/human/can_use_rig()
	return 1

/mob/living/carbon/brain/can_use_rig()
	return istype(loc, /obj/item/mmi)

/mob/living/silicon/ai/can_use_rig()
	return carded

/mob/living/silicon/pai/can_use_rig()
	return loc == card

/mob/living/proc/HardsuitClickOn(atom/A, alert_ai = 0)
	if(!can_use_rig())
		return 0
	var/obj/item/rig/rig = get_rig()
	if(istype(rig) && !rig.offline && rig.selected_module)
		if(src != rig.wearer())
			if(rig.ai_can_move_suit(src, check_user_module = 1))
				message_admins("[key_name_admin(src, include_name = 1)] is trying to force \the [key_name_admin(rig.wearer(), include_name = 1)] to use a hardsuit module.")
			else
				return 0
		rig.selected_module.engage(A, alert_ai, src)
		if(ismob(A)) // No instant mob attacking - though modules have their own cooldowns
			setClickCooldown(get_attack_speed())
		return 1
	return 0

