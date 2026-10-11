//Unathi clothing.
/obj/item/clothing/suit/unathi/robe
	name = "roughspun robes"
	desc = "A traditional Unathi garment."
	icon_state = "robe-unathi"

CAPABILITIES(/obj/item/clothing/suit/unathi/robe)
	configure(item_worn(covers = CHEST|LEGS, hides = HIDETIE|HIDEHOLSTER))

/obj/item/clothing/suit/unathi/mantle
	name = "hide mantle"
	desc = "A rather grisly selection of cured hides and skin, sewn together to form a ragged mantle."
	icon_state = "mantle-unathi"

CAPABILITIES(/obj/item/clothing/suit/unathi/mantle)
	configure(item_worn(covers = UPPER_TORSO))
