/obj/item/clothing/glasses/hud/security/eyepatch
	name = "Security Hudpatch"
	desc = "An eyepatch with built in scanners, that analyzes those in view and provides accurate data about their ID status and security records."
	icon_state = "eyepatch"
	item_state_slots = list(slot_r_hand_str = "blindfold", slot_l_hand_str = "blindfold")
	enables_planes = list(VIS_CH_ID,VIS_CH_WANTED,VIS_CH_IMPTRACK,VIS_CH_IMPLOYAL,VIS_CH_IMPCHEM)
	var/eye = null

CAPABILITIES(/obj/item/clothing/glasses/hud/security/eyepatch)
	configure(item_worn(covers = 0))
	op("switch_eye", menu(), label("Switch Eyepatch"), needs(carried(), req(PROC_REF(eye_switch_allowed), because = MSG(op/not_available))), then(PROC_REF(eye_switched)))


/obj/item/clothing/glasses/hud/security/eyepatch/proc/eye_switch_allowed(datum/act/op/A)
	var/mob/living/user = A.actor
	return (istype(user) && user.stat == CONSCIOUS) ? null : MSG(op/not_available)

/obj/item/clothing/glasses/hud/security/eyepatch/proc/eye_switched(datum/act/op/A)
	set_eye(!eye)
	if(eye)
		set_icon_state("[icon_state]_1")
	else
		set_icon_state(initial(icon_state))
	return OP_OK
