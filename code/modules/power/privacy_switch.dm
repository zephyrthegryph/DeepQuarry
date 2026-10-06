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

DECLARE_INTERACTIONS(/obj/structure/privacyswitch, INTERACT_HAND_UNGATED(null, PROC_REF(interaction_hand), REQ_TARGET_STATE(/obj/structure/privacyswitch/proc/cooled_down)))

/// Requirement: the switch has a use cooldown.
/obj/structure/privacyswitch/proc/cooled_down(mob/user, atom/target, obj/item/held)
	return COOLDOWN_FINISHED(src, use_cooldown) ? TRUE : "the area can not be altered so soon again"

/// Old attack_hand.
/obj/structure/privacyswitch/proc/interaction_hand(mob/user, obj/item/held, datum/interaction/interaction)
	var/area/A = get_area(src)
	if(!A)
		return TRUE

	var/_answer_k25 = rerun_ask(user, "k25", PROC_REF(interaction_hand), args, /datum/prompt/choice, question = "Do you want to toggle ghost vision for this area [A.flag_check(AREA_BLOCK_GHOST_SIGHT) ? "on" : "off"]?", title = "Toggle ghost vision?", choices = list("Yes", "No"), buttons = TRUE)
	if(isnull(_answer_k25))
		return TRUE
	if(_answer_k25 != "Yes")
		return TRUE

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
