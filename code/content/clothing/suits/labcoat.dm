/obj/item/clothing/suit/storage/toggle/labcoat
	name = "labcoat"
	desc = "A suit that protects against minor chemical spills."
	icon_state = "labcoat"
	item_state_slots = list(slot_r_hand_str = "labcoat", slot_l_hand_str = "labcoat")
	blood_overlay_type = "coat"

CAPABILITIES(/obj/item/clothing/suit/storage/toggle/labcoat)
	variants(nameof(variant), PROC_REF(variant_table))
	configure(atom_rules(armor_spec = "bio=50"))
	suit_storage(list(POCKET_GENERIC, POCKET_EMERGENCY, POCKET_MEDICAL))
	configure(item_worn(covers = UPPER_TORSO|ARMS, hides = HIDEHOLSTER))


/obj/item/clothing/suit/storage/toggle/labcoat/virologist
	name = JOB_ALT_VIROLOGIST + " labcoat"
	desc = "A suit that protects against minor chemical spills. Offers slightly more protection against biohazards than the standard model. Has a green stripe on the shoulder."
	icon_state = "labcoat_vir"
	item_state_slots = list(slot_r_hand_str = "virologist_labcoat", slot_l_hand_str = "virologist_labcoat")

/obj/item/clothing/suit/storage/toggle/labcoat/talon
	name = "Talon labcoat"
	desc = "A large, and extremely sterile labcoat that protects the wearer from chemical spills. This one has ITV Talon colored patterns along the labcoat, the designated shapes list it as a medical officer's labcoat."
	icon = 'icons/inventory/suit/item.dmi'
	icon_state = "talon_labcoat"
	item_state_slots = list(slot_r_hand_str = "talon_labcoat", slot_l_hand_str = "talon_labcoat")

CAPABILITIES(/obj/item/clothing/suit/storage/toggle/labcoat/talon)
	configure(item_worn(worn_icon = 'icons/inventory/suit/mob.dmi'))


// 'Modern' labcoats
/obj/item/clothing/suit/storage/toggle/labcoat/modern
	name = "modern labcoat"
	icon_state = "labcoat_mod"

/obj/item/clothing/suit/storage/toggle/labcoat/modern/cmo
	name = "modern cmo's labcoat"
	desc = "A suit that protects against minor chemical spills. This one has distinct markings on the arms."
	icon_state = "labcoat_cmo_mod"

// 'Modern' biosuits
/obj/item/clothing/suit/bio_suit/modern
	name = "modern bio suit"
	icon_state = "bio_mod"

/obj/item/clothing/head/bio_hood/modern
	name = "modern bio hood"
	icon_state = "bio_mod"

// Labcoat icons from before the fulpstation labcoats became default
// denoted "old" to avoid conflict

/obj/item/clothing/suit/storage/toggle/labcoat/old
	name = "old-school labcoat"
	icon_state = "labcoat_old"

/obj/item/clothing/suit/storage/toggle/labcoat/old/tox
	name = "old-school scientist's labcoat"
	icon_state = "labcoat_old_tox"

/obj/item/clothing/suit/storage/toggle/labcoat/old/chem
	name = "old-school chemist's labcoat"
	icon_state = "labcoat_old_chem"

/obj/item/clothing/suit/storage/toggle/labcoat/old/vir
	name = "old-school virologist's labcoat"
	icon_state = "labcoat_old_vir"

/obj/item/clothing/suit/storage/toggle/labcoat/old/cmo
	name = "old-school CMO's labcoat"
	icon_state = "labcoat_old_cmo"

CAPABILITIES(/obj/item/clothing/suit/storage/toggle/labcoat/virologist)
	configure(atom_rules(armor_spec = "bio=60"))
