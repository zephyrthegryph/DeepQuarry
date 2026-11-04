/obj/item/clothing/accessory/poncho/roles/cloak/half
	name = "rough half cloak"
	desc = "The latest fashion innovations by the Nanotrasen Uniform & Fashion Department have provided the brilliant invention of slicing a regular cloak in half! All the ponce, half the cost!"
	icon_state = "roughcloak"
	item_state = "roughcloak"
	special_handling = TRUE

CAPABILITIES(/obj/item/clothing/accessory/poncho/roles/cloak/half)
	configure(item_rules(actions_types = list(/datum/action/item_action/adjust_cloak)))
	op("half_cloak_flip_self", in_hand(), label("Flip cloak"), then(PROC_REF(half_cloak_flip_self)))

/// Old attack_self.
/obj/item/clothing/accessory/poncho/roles/cloak/half/proc/half_cloak_flip_self(datum/act/op/A)
	var/mob/user = A.actor
	if(src.icon_state == initial(icon_state))
		set_icon_state("[icon_state]_open")
		set_item_state("[item_state]_open")
		set_flags_inv(HIDETIE|HIDEHOLSTER)
		to_chat(user, "You flip the cloak over your shoulder.")
	else
		set_icon_state(initial(icon_state))
		set_item_state(initial(item_state))
		set_flags_inv(HIDEHOLSTER)
		to_chat(user, "You pull the cloak over your shoulder.")
