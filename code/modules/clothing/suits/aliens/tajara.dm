/obj/item/clothing/suit/tajaran/furs
	name = "heavy furs"
	desc = "A traditional Zhan-Khazan garment."
	icon_state = "zhan_furs"

CAPABILITIES(/obj/item/clothing/suit/tajaran/furs)
	configure(item_worn(covers = CHEST|LEGS|FEET|ARMS, hides = HIDEGLOVES|HIDESHOES|HIDEJUMPSUIT|HIDETAIL|HIDETIE|HIDEHOLSTER))
	configure(item_sounds(drop = SFX_ITEMS_DROP_LEATHER, pickup = SFX_ITEMS_PICKUP_LEATHER))

/obj/item/clothing/head/tajaran/scarf	//This stays in /suits because it goes with the furs above
	name = "headscarf"
	desc = "A scarf of coarse fabric. Seems to have ear-holes."
	icon_state = "zhan_scarf"
	item_state_slots = list(slot_r_hand_str = "beret_white", slot_l_hand_str = "beret_white")

CAPABILITIES(/obj/item/clothing/head/tajaran/scarf)
	configure(item_worn(covers = HEAD|FACE))
	configure(item_sounds(drop = SFX_ITEMS_DROP_LEATHER, pickup = SFX_ITEMS_PICKUP_LEATHER))
