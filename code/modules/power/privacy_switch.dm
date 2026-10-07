/obj/structure/privacyswitch
	name = "privacy switch"
	desc = "A special switch to increase the room's privavy. (Blocks ghosts from seeing the area, green indicates that ghosts are blocked.) Please disable this after use so that people can see the room is free more easily."
	icon = 'icons/obj/power_vr.dmi'
	icon_state = "privacy0"
	COOLDOWN_DECLARE(use_cooldown)

/obj/structure/privacyswitch/Initialize(mapload)
	var/area/A = get_area(src)
	if(A?.flag_check(AREA_BLOCK_GHOST_SIGHT))
		icon_state = "privacy1"
	. = ..()

/obj/structure/privacyswitch
	silicon_use = SILICON_USE_HAND

CAPABILITIES(/obj/structure/privacyswitch)
	op("toggle_privacy", hand(), ungated(), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), needs(req(PROC_REF(cooled_down_holds), because = "the area can not be altered so soon again")),
		asks(/datum/prompt/choice, fields = list("question" = computed(PROC_REF(toggle_question)), "title" = "Toggle ghost vision?", "choices" = list("Yes", "No"), "buttons" = TRUE), when = PROC_REF(has_area)), then(PROC_REF(interaction_hand)))

/// Requirement: the switch has a use cooldown.
/obj/structure/privacyswitch/proc/cooled_down(mob/user, atom/target, obj/item/held)
	return COOLDOWN_FINISHED(src, use_cooldown) ? TRUE : "the area can not be altered so soon again"

/// Old attack_hand.
/obj/structure/privacyswitch/proc/interaction_hand(datum/act/op/action)
	var/mob/user = action.actor
	var/area/A = get_area(src)
	if(!A)
		return TRUE

	if(action.answer?.value != "Yes")
		return OP_OK

	if(A.flag_check(AREA_BLOCK_GHOST_SIGHT))
		A.flags ^= AREA_BLOCK_GHOST_SIGHT
		icon_state = "privacy0"
		GLOB.ghostnet.removeArea(A)
		to_chat(user, span_notice("The area is no longer protected from ghost vison."))
		log_and_message_admins("toggled ghost vision in [A] on.", user)
	else
		A.flags ^= AREA_BLOCK_GHOST_SIGHT
		icon_state = "privacy1"
		GLOB.ghostnet.addArea(A)
		to_chat(user, span_notice("The area is now protected from ghost vison."))
		log_and_message_admins("toggled ghost vision in [A] off.", user)
	COOLDOWN_START(src, use_cooldown, 5 MINUTES)
	return TRUE

/obj/structure/privacyswitch/proc/cooled_down_holds(datum/act/op/A)
	return COOLDOWN_FINISHED(src, use_cooldown)

/obj/structure/privacyswitch/proc/has_area(datum/act/op/A)
	return !!get_area(src)

/obj/structure/privacyswitch/proc/toggle_question(datum/act/op/A)
	var/area/here = get_area(src)
	return "Do you want to toggle ghost vision for this area [here?.flag_check(AREA_BLOCK_GHOST_SIGHT) ? "on" : "off"]?"
