/obj/item/clothing/mask/altevian_breath
	name = "Spacer Tuned Mask"
	desc = "A mask designed for long-term use in areas where breathing comes at a premium."
	icon_state = "altevian-mask"
	sprite_sheets = null
	item_state_slots = list(slot_r_hand_str = "breath", slot_l_hand_str = "breath")
	w_class = ITEMSIZE_SMALL

CAPABILITIES(/obj/item/clothing/mask/altevian_breath)
	fits_as(FIT_ALTEVIAN)
	configure(item_worn(flags = AIRTIGHT|FLEXIBLEMATERIAL, covers = FACE))
	configure(item_protection(gas_transfer = 0.10, permeability = 0.50))
	configure(item_sounds(pickup = SFX_ITEMS_PICKUP_COMPONENT, drop = SFX_ITEMS_DROP_COMPONENT))
