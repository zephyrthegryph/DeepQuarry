/obj/structure/privacyswitch
	name = "privacy switch"
	desc = "A special switch to increase the room's privavy. (Blocks ghosts from seeing the area, green indicates that ghosts are blocked.) Please disable this after use so that people can see the room is free more easily."
	icon = 'icons/obj/power_vr.dmi'
	icon_state = "privacy0"
	var/nextUse = 0

/obj/structure/privacyswitch/Initialize(mapload)
	var/area/A = get_area(src)
	if(A?.flag_check(AREA_BLOCK_GHOST_SIGHT))
		icon_state = "privacy1"
	. = ..()

/obj/structure/privacyswitch
	silicon_use = SILICON_USE_HAND

DECLARE_INTERACTIONS(/obj/structure/privacyswitch, INTERACT_HAND_UNGATED(null, PROC_REF(interaction_hand)))

/// Old attack_hand.
/obj/structure/privacyswitch/proc/interaction_hand(mob/user, obj/item/held, datum/interaction/interaction)
	if(nextUse - world.time > 0)
		to_chat(user, span_warning("The area can not be altered so soon again!"))
		return TRUE
	var/area/A = get_area(src)
	if(!A)
		return TRUE

	var/_answer_k25 = rerun_prompt(user, "k25", list("message" = "Do you want to toggle ghost vision for this area [A.flag_check(AREA_BLOCK_GHOST_SIGHT) ? "on" : "off"]?", "title" = "Toggle ghost vision?", "choices" = list("Yes", "No")), TYPE_PROC_REF(/atom, attack_hand), args)
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
	nextUse = world.time + 5 MINUTES
	return TRUE
