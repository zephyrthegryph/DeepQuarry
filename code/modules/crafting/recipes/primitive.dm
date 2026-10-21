/*
 * Misc
 */
/transformation/crafting/cloth
CAPABILITIES(/transformation/crafting/cloth)
	configure(transformation(name = "Cloth bolt", makes = list(item_term(/obj/item/stack/material/cloth, 1)),
		crafted = crafted(reqs = list(list(/obj/item/stack/material/fiber = 3)),
			build_time = 4 SECONDS,
			category = CAT_PRIMAL)))


/transformation/crafting/crude_bandage
CAPABILITIES(/transformation/crafting/crude_bandage)
	configure(transformation(name = "Crude bandages (x10)", makes = list(item_term(/obj/item/stack/medical/crude_pack, 1)),
		crafted = crafted(reqs = list(list(/obj/item/stack/material/cloth = 2)),
			build_time = 4 SECONDS,
			category = CAT_PRIMAL)))


/*
 * Primitive Clothing
 */
/transformation/crafting/primitive_clothes
CAPABILITIES(/transformation/crafting/primitive_clothes)
	configure(transformation(name = "primitive clothes", makes = list(item_term(/obj/item/clothing/under/primitive, 1)),
		crafted = crafted(reqs = list(list(/obj/item/stack/material/fiber = 4), list(/obj/item/stack/material/cloth = 6)),
			build_time = 9 SECONDS,
			category = CAT_CLOTHING)))


/transformation/crafting/primitive_shoes
CAPABILITIES(/transformation/crafting/primitive_shoes)
	configure(transformation(name = "primitive shoes", makes = list(item_term(/obj/item/clothing/shoes/primitive, 1)),
		crafted = crafted(reqs = list(list(/obj/item/stack/material/fiber = 2), list(/obj/item/stack/material/cloth = 3)),
			build_time = 6 SECONDS,
			category = CAT_CLOTHING)))

