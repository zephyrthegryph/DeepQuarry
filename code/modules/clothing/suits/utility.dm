/*
 * Contains:
 *		Fire protection
 *		Bomb protection
 *		Radiation protection
 */

/*
 * Fire protection
 */

/obj/item/clothing/suit/fire
	armor_spec = "fire=100"
	name = "emergency firesuit"
	desc = "A suit that protects against fire and heat."
	icon_state = "firesuit"
	item_state_slots = list(slot_r_hand_str = "black_suit", slot_l_hand_str = "black_suit")
	w_class = ITEMSIZE_LARGE//bulky item
	slowdown = 1.0
	resistance_flags = FIRE_PROOF

CAPABILITIES(/obj/item/clothing/suit/fire)
	acceptance(CONSTRAINT_SUIT_STORAGE, req_acceptance_type(list(POCKET_GENERIC, POCKET_EMERGENCY, /obj/item/extinguisher), because = "it doesn't take that"), mode = ACCEPTANCE_REPLACE)
	configure(item_worn(covers = CHEST|LEGS|FEET|ARMS|HANDS, hides = HIDEGLOVES|HIDESHOES|HIDEJUMPSUIT|HIDETAIL|HIDETIE|HIDEHOLSTER, flags = 0))
	configure(item_protection(gas_transfer = 0.90, permeability = 0.50, heat_parts = CHEST|LEGS|FEET|ARMS|HANDS, max_heat = FIRESUIT_MAX_HEAT_PROTECTION_TEMPERATURE, cold_parts = CHEST|LEGS|FEET|ARMS|HANDS, min_pressure = 0.2 * ONE_ATMOSPHERE, max_pressure = 20  * ONE_ATMOSPHERE))


/obj/item/clothing/suit/fire/firefighter
	name = "firesuit"
	icon_state = "firesuit2"

CAPABILITIES(/obj/item/clothing/suit/fire/firefighter)
	configure(item_protection(max_heat = FIRESUIT_MAX_HEAT_PROTECTION_TEMPERATURE+5000))

/obj/item/clothing/suit/fire/heavy
	name = "atmospheric firesuit"
	desc = "A suit that protects against extreme fire and heat."
	icon_state = "atmos_firesuit"
	slowdown = 1.5

CAPABILITIES(/obj/item/clothing/suit/fire/heavy)
	configure(item_protection(max_heat = FIRESUIT_MAX_HEAT_PROTECTION_TEMPERATURE+10000))

/*
 * Bomb protection
 */
/obj/item/clothing/head/bomb_hood
	name = "bomb hood"
	desc = "Use in case of bomb."
	icon_state = "bombsuit"
	armor_spec = "bomb=100"
	resistance_flags = BOMB_PROOF

CAPABILITIES(/obj/item/clothing/head/bomb_hood)
	configure(item_worn(hides = HIDEMASK|HIDEEARS|HIDEEYES|BLOCKHAIR, covers = HEAD|FACE|EYES))
	configure(item_protection(siemens = 0))

/obj/item/clothing/suit/bomb_suit
	name = "bomb suit"
	desc = "A suit designed for safety when handling explosives."
	icon_state = "bombsuit"
	w_class = ITEMSIZE_LARGE//bulky item
	slowdown = 2
	armor_spec = "bomb=100"
	resistance_flags = BOMB_PROOF

CAPABILITIES(/obj/item/clothing/suit/bomb_suit)
	configure(item_worn(hides = HIDEJUMPSUIT|HIDETAIL|HIDETIE|HIDEHOLSTER))
	configure(item_protection(gas_transfer = 0.01, permeability = 0.01, heat_parts = CHEST|LEGS|FEET|ARMS|HANDS, cold_parts = CHEST|LEGS|FEET|ARMS|HANDS, max_heat = ARMOR_MAX_HEAT_PROTECTION_TEMPERATURE, siemens = 0))

/obj/item/clothing/head/bomb_hood/security
	icon_state = "bombsuitsec"

CAPABILITIES(/obj/item/clothing/head/bomb_hood/security)
	configure(item_worn(covers = HEAD))

/obj/item/clothing/suit/bomb_suit/security
	icon_state = "bombsuitsec"

CAPABILITIES(/obj/item/clothing/suit/bomb_suit/security)
	acceptance(CONSTRAINT_SUIT_STORAGE, req_acceptance_type(list(POCKET_SECURITY), because = "it doesn't take that"), mode = ACCEPTANCE_REPLACE)
	configure(item_worn(covers = CHEST|LEGS|FEET|ARMS|HANDS))

/*
 * Radiation protection
 */


/obj/item/clothing/head/radiation
	name = "Radiation hood"
	icon_state = "rad"
	desc = "A hood with radiation protective properties. Label: Made with lead, do not eat insulation"
	armor_spec = "bio=60;rad=100"

CAPABILITIES(/obj/item/clothing/head/radiation)
	configure(item_worn(hides = BLOCKHAIR, flags = THICKMATERIAL, covers = HEAD|FACE|EYES))
	trait(TRAIT_RADIATION_PROTECTED_CLOTHING, examine = RADIATION_CLOTHING_EXAMINE)

/obj/item/clothing/suit/radiation
	name = "Radiation suit"
	desc = "A suit that protects against radiation. Label: Made with lead, do not eat insulation."
	icon_state = "rad"
	w_class = ITEMSIZE_LARGE//bulky item
	slowdown = 1.5
	armor_spec = "bio=60;rad=100"


CAPABILITIES(/obj/item/clothing/suit/radiation)
	acceptance(CONSTRAINT_SUIT_STORAGE, req_acceptance_type(list(POCKET_GENERIC, POCKET_EMERGENCY, /obj/item/clothing/head/radiation), because = "it doesn't take that"), mode = ACCEPTANCE_REPLACE)
	configure(item_worn(covers = CHEST|LEGS|ARMS|HANDS|FEET, hides = HIDEJUMPSUIT|HIDETAIL|HIDETIE|HIDEHOLSTER, flags = THICKMATERIAL))
	configure(item_protection(gas_transfer = 0.90, permeability = 0.50))
	trait(TRAIT_RADIATION_PROTECTED_CLOTHING, examine = RADIATION_CLOTHING_EXAMINE)

/obj/item/clothing/suit/radiation/teshari
	name = "Small radiation suit"
	desc = "A specialist suit that protects against radiation, designed specifically for use by Teshari. Made to order by Aether."
	icon = 'icons/inventory/suit/item_teshari.dmi'
	icon_override = 'icons/inventory/suit/mob_teshari.dmi'
	icon_state = "rad_fitted"
	slowdown = 0.5


/obj/item/clothing/head/radiation/teshari
	name = "Small radiation hood"
	desc = "A specialist hood with radiation protective properties, designed specifically for use by Teshari. Made to order by Aether."
	icon = 'icons/inventory/head/item_teshari.dmi'
	icon_override = 'icons/inventory/head/mob_teshari.dmi'
	icon_state = "rad_fitted"


/obj/item/clothing/head/bomb_hood/security
	icon_state = "bombsuitsec"

/obj/item/clothing/suit/storage/toggle/paramedic
	name = "paramedic vest"
	desc = "A vest that protects against minor chemical spills."
	icon_state = "paramedic-vest"
	item_state = "paramedic-vest"
	item_state_slots = list(slot_r_hand_str = "blue_labcoat", slot_l_hand_str = "blue_labcoat")
	blood_overlay_type = "coat"
	armor_spec = "bio=50"

CAPABILITIES(/obj/item/clothing/suit/storage/toggle/paramedic)
	acceptance(CONSTRAINT_SUIT_STORAGE, req_acceptance_type(list(POCKET_GENERIC, POCKET_EMERGENCY, POCKET_MEDICAL), because = "it doesn't take that"), mode = ACCEPTANCE_REPLACE)
	configure(item_worn(covers = UPPER_TORSO, hides = HIDEHOLSTER))


/obj/item/clothing/head/radiation
	sprite_sheets = list(
		SPECIES_TESHARI = 'icons/inventory/head/mob_teshari.dmi',
		SPECIES_VOX = 'icons/inventory/head/mob_vox.dmi',
		SPECIES_WEREBEAST = 'icons/inventory/head/mob_werebeast.dmi'
		)

/obj/item/clothing/suit/radiation
	sprite_sheets = list(
		SPECIES_TESHARI = 'icons/inventory/suit/mob_teshari.dmi',
		SPECIES_VOX = 'icons/inventory/suit/mob_vox.dmi',
		SPECIES_WEREBEAST = 'icons/inventory/suit/mob_werebeast.dmi'
		)


CAPABILITIES(/obj/item/clothing/suit/radiation/teshari)
	acceptance(CONSTRAINT_FIT, fits(list(SPECIES_TESHARI)), mode = ACCEPTANCE_REPLACE)


CAPABILITIES(/obj/item/clothing/head/radiation/teshari)
	acceptance(CONSTRAINT_FIT, fits(list(SPECIES_TESHARI)), mode = ACCEPTANCE_REPLACE)
