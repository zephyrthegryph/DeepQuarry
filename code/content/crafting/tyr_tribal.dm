/transformation/crafting/arrow_agate
CAPABILITIES(/transformation/crafting/arrow_agate)
	configure(transformation(name = "Wood arrow (agate tip)", makes = list(item_term(/obj/item/arrow/standard, 1)),
		crafted = crafted(reqs = list(list(/obj/item/stack/material/wood = 2), list(/obj/item/stack/material/weathered_agate = 2)),
			build_time = 4 SECONDS,
			category = CAT_WEAPONRY,
			subcategory = CAT_AMMO)))


/transformation/crafting/agate_blade
CAPABILITIES(/transformation/crafting/agate_blade)
	configure(transformation(name = "agate blade", makes = list(item_term(/obj/item/melee/agate_sword, 1)),
		crafted = crafted(reqs = list(list(/obj/item/stack/material/wood = 2), list(/obj/item/stack/material/weathered_agate = 6)),
			build_time = 4 SECONDS,
			category = CAT_WEAPONRY,
			subcategory = CAT_WEAPON)))


/transformation/crafting/agate_hammer
CAPABILITIES(/transformation/crafting/agate_hammer)
	configure(transformation(name = "agate hammer", makes = list(item_term(/obj/item/melee/agate_hammer, 1)),
		crafted = crafted(reqs = list(list(/obj/item/stack/material/wood = 4), list(/obj/item/stack/material/weathered_agate = 2)),
			build_time = 4 SECONDS,
			category = CAT_WEAPONRY,
			subcategory = CAT_WEAPON)))


/transformation/crafting/agate_spear
CAPABILITIES(/transformation/crafting/agate_spear)
	configure(transformation(name = "agate spear", makes = list(item_term(/obj/item/melee/agate_spear, 1)),
		crafted = crafted(reqs = list(list(/obj/item/stack/material/wood = 3), list(/obj/item/stack/material/weathered_agate = 3)),
			build_time = 4 SECONDS,
			category = CAT_WEAPONRY,
			subcategory = CAT_WEAPON)))


/transformation/crafting/tyr_leaf_cloak
CAPABILITIES(/transformation/crafting/tyr_leaf_cloak)
	configure(transformation(name = "tyr leaf cloak", makes = list(item_term(/obj/item/clothing/suit/armor/tyrtribalcloak, 1)),
		crafted = crafted(reqs = list(list(/obj/item/reagent_containers/food/snacks/weatherlily = 1), list(/obj/item/stack/material/fiber = 6), list(/obj/item/stack/material/cloth = 3)),
			build_time = 12 SECONDS,
			category = CAT_CLOTHING)))


