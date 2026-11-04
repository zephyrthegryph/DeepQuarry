/obj/item/clothing/glasses/hud/health/eyepatch
	name = "Medical Hudpatch"
	desc = "An eyepatch with built in scanners, that analyzes those in view and provides accurate data about their health status."
	icon_state = "eyepatch"
	item_state_slots = list(slot_r_hand_str = "blindfold", slot_l_hand_str = "blindfold")
	enables_planes =  list(VIS_CH_STATUS,VIS_CH_HEALTH)
	var/eye = null

CAPABILITIES(/obj/item/clothing/glasses/hud/health/eyepatch)
	configure(item_worn(covers = 0))
	held_verb(/obj/item/clothing/glasses/hud/health/eyepatch/proc/switch_eyepatch, SLOT_ANY_CARRIED)
	op("switch_eye", menu(), label("Switch Eyepatch"), needs(carried(), req(PROC_REF(eye_switch_allowed), because = MSG(op/not_available))), then(PROC_REF(eye_switched)))

/obj/item/clothing/glasses/hud/health/eyepatch/proc/switch_eyepatch()
	set name = "Switch Eyepatch"
	set category = VERB_CAT_OBJECT
	set src in usr
	perform_op(usr, src, "switch_eye", null, ORIGIN_VERB)

/obj/item/clothing/glasses/hud/health/eyepatch/proc/eye_switch_allowed(datum/act/op/A)
	var/mob/living/user = A.actor
	return (istype(user) && user.stat == CONSCIOUS) ? null : MSG(op/not_available)

/obj/item/clothing/glasses/hud/health/eyepatch/proc/eye_switched(datum/act/op/A)
	set_eye(!eye)
	if(eye)
		set_icon_state("[icon_state]_1")
	else
		set_icon_state(initial(icon_state))
	return OP_OK
