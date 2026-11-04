//Neo Ranger Poncho

/obj/item/clothing/accessory/poncho/roles/neo_ranger
	name = "ranger poncho"
	desc = "Aim for the Heart, Ramon."
	icon_state = "neo_ranger"
	item_state = "neo_ranger"
	special_handling = TRUE

CAPABILITIES(/obj/item/clothing/accessory/poncho/roles/neo_ranger)
	configure(item_rules(actions_types = list(/datum/action/item_action/adjust_poncho)))
	op("neo_ranger_adjust_self", in_hand(), label("Adjust"), then(PROC_REF(neo_ranger_adjust_self)))

/// Old attack_self.
/obj/item/clothing/accessory/poncho/roles/neo_ranger/proc/neo_ranger_adjust_self(datum/act/op/A)
	var/mob/user = A.actor
	if(src.icon_state == initial(icon_state))
		set_icon_state("[icon_state]_open")
		set_item_state("[item_state]_open")
		set_flags_inv(HIDETIE|HIDEHOLSTER)
		to_chat(user, "You adjust your poncho.")
	else
		set_icon_state(initial(icon_state))
		set_item_state(initial(item_state))
		set_flags_inv(HIDEHOLSTER)
		to_chat(user, "You adjust your poncho.")
