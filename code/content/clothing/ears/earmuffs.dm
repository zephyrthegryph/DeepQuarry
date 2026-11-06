/*
	Earmuffs
*/
/obj/item/clothing/ears/earmuffs
	name = "earmuffs"
	desc = "Protects your hearing from loud noises, and quiet ones as well."
	icon = 'icons/obj/items.dmi'
	icon_state = "earmuffs"
	item_state_slots = list(slot_r_hand_str = "earmuffs", slot_l_hand_str = "earmuffs")
	ear_protection = 2
	resistance_flags = FIRE_PROOF

CAPABILITIES(/obj/item/clothing/ears/earmuffs)
	configure(item_worn(slots = SLOT_EARS | SLOT_TWOEARS))

/obj/item/clothing/ears/earmuffs/headphones
	name = "headphones"
	desc = "Unce unce unce unce."
	var/headphones_on = 0
	icon_state = "headphones_off"
	item_state_slots = list(slot_r_hand_str = "headphones", slot_l_hand_str = "headphones")

CAPABILITIES(/obj/item/clothing/ears/earmuffs/headphones)
	configure(item_worn(slots = SLOT_EARS | SLOT_TWOEARS))
	op("headphones_togglemusic_verb", menu(), label("Toggle Headphone Music"), needs(carried()), then(PROC_REF(headphones_togglemusic_verb)))

/// Old verb "Toggle Headphone Music".
/obj/item/clothing/ears/earmuffs/headphones/proc/headphones_togglemusic_verb(datum/act/op/A)
	var/mob/user = A.actor
	if(!isliving(user)) return
	if(user.stat) return

	var/base_icon = copytext(icon_state,1,(length(icon_state) - 3 + headphones_on))

	if(headphones_on)
		set_icon_state("[base_icon]_off")
		headphones_on = 0
		to_chat(user, span_notice("You turn the music off."))
	else
		set_icon_state("[base_icon]_on")
		headphones_on = 1
		to_chat(user, span_notice("You turn the music on."))
