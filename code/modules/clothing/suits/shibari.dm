// Behaves similar to straight jackets but the effects can be varied easily.
#define SHIBARI_NONE "None"
#define SHIBARI_ARMS "Arms"
#define SHIBARI_LEGS "Legs"
#define SHIBARI_BOTH "Arms and Legs"

/obj/item/clothing/suit/shibari
	name = "shibari bindings"
	desc = "A set of ropes that designed to be tied around another person to restrain them."
	icon_state = "shibari_None"

	var/resist_time = 1 MINUTE

	var/rope_mode = SHIBARI_NONE

	special_handling = TRUE


CAPABILITIES(/obj/item/clothing/suit/shibari)
	op("shibari_worn_hand", hand(), ungated(), then(PROC_REF(shibari_worn_hand)))
	op("shibari_mode_self", in_hand(), label("Choose limbs"), asks(/datum/prompt/choice, fields = list("question" = "Which limbs would you like to restrain with the bindings?", "title" = "Shibari", "choices" = list(SHIBARI_NONE, SHIBARI_ARMS, SHIBARI_LEGS, SHIBARI_BOTH), "timeout" = 0), step = "a1"), then(PROC_REF(shibari_mode_self)))

/// Old attack_hand: the wearer can't take it off themselves.
/obj/item/clothing/suit/shibari/proc/shibari_worn_hand(datum/act/op/A)
	var/mob/living/user = A.actor
	if(ishuman(user))
		var/mob/living/carbon/human/H = user
		if(src == H.get_equipped_item(SLOT_ID_SUIT))
			to_chat(H, span_notice("You need help taking this off!"))
			return TRUE
	return OP_DECLINE

/// Old attack_self: choose which limbs to bind.
/obj/item/clothing/suit/shibari/proc/shibari_mode_self(datum/act/op/A)
	var/_answer_a1 = A.step_answer("a1").answer_value
	rope_mode = _answer_a1
	if(!rope_mode)
		rope_mode = SHIBARI_NONE
	if(rope_mode == SHIBARI_BOTH)
		icon_state = "shibari_Both"
	else
		icon_state = "shibari_[rope_mode]"

/obj/item/clothing/suit/shibari/equipped(mob/living/user,slot)
	. = ..()
	if((rope_mode == SHIBARI_ARMS) || (rope_mode == SHIBARI_BOTH))
		if(slot == SLOT_ID_SUIT)
			if(user.get_left_hand() != src)
				user.drop_l_hand()
			if(user.get_right_hand() != src)
				user.drop_r_hand()
			if(ishuman(user))
				var/mob/living/carbon/human/H = user
				H.drop_from_inventory(H.get_equipped_item(SLOT_ID_HANDCUFFED))
	if((rope_mode == SHIBARI_LEGS) || (rope_mode == SHIBARI_BOTH))
		if(slot == SLOT_ID_SUIT)
			if(ishuman(user))
				var/mob/living/carbon/human/H = user
				// The ropes bind the legs, but the suit can't also sit in the legcuff
				// slot (an item is in one slot): it only forces walking.
				H.drop_from_inventory(H.get_equipped_item(SLOT_ID_LEGCUFFED))
				if(user.m_intent != I_WALK)
					user.m_intent = I_WALK
					if(user.hud_used && user.hud_used.move_intent)
						user.hud_used.move_intent.icon_state = "walking"

/obj/item/clothing/suit/shibari/dropped(mob/user, equipping, slot)
	..()

/obj/item/clothing/suit/shibari/red
	color = "#ff0000"

/obj/item/clothing/suit/shibari/blue
	color = "#006aff"

/obj/item/clothing/suit/shibari/green
	color = "#00ff0d"

/obj/item/clothing/suit/shibari/yellow
	color = "#f6ff00"

/obj/item/clothing/suit/shibari/black
	color = "#000000"

/obj/item/clothing/suit/shibari/pink
	color = "#ff00bf"

#undef SHIBARI_NONE
#undef SHIBARI_ARMS
#undef SHIBARI_LEGS
#undef SHIBARI_BOTH
