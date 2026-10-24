//Wizard Rig
/obj/item/clothing/head/helmet/space/void/wizard
	name = "gem-encrusted voidsuit helmet"
	desc = "A bizarre gem-encrusted helmet that radiates magical energies."
	icon_state = "rig0-wiz"
	item_state_slots = list(slot_r_hand_str = "wiz_helm", slot_l_hand_str = "wiz_helm")
	armor_spec = "melee=40;bullet=20;laser=20;energy=20;bomb=35;bio=100;rad=60;cold=60"
	wizard_garb = 1

CAPABILITIES(/obj/item/clothing/head/helmet/space/void/wizard)
	configure(item_rules(sprite_sheets_obj = TRAIT_NONE))
	configure(movable_motion(unacidable = TRUE))
	configure(item_protection(siemens = 0.7))

/obj/item/clothing/suit/space/void/wizard
	icon_state = "rig-wiz"
	name = "gem-encrusted voidsuit"
	desc = "A bizarre gem-encrusted suit that radiates magical energies."
	item_state_slots = list(slot_r_hand_str = "wiz_voidsuit", slot_l_hand_str = "wiz_voidsuit")
	w_class = ITEMSIZE_NORMAL
	armor_spec = "melee=40;bullet=20;laser=20;energy=20;bomb=35;bio=100;rad=60;cold=60"
	wizard_garb = 1

CAPABILITIES(/obj/item/clothing/suit/space/void/wizard)
	configure(item_rules(sprite_sheets_obj = TRAIT_NONE))
	configure(movable_motion(unacidable = TRUE))
	configure(item_protection(siemens = 0.7))
