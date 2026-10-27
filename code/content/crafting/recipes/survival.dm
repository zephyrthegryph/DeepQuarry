/transformation/crafting/shovel
CAPABILITIES(/transformation/crafting/shovel)
	configure(transformation(name = "Wooden Shovel", makes = list(item_term(/obj/item/shovel/wood, 1)),
		crafted = crafted(reqs = list(list(/obj/item/stack/material/stick = 5), list(/obj/item/stack/material/wood = 1), list(/obj/item/stack/material/fiber = 3), list(/obj/item/stack/material/flint = 1)),
			build_time = 12 SECONDS,
			category = CAT_WEAPONRY,
			subcategory = CAT_WEAPON)))


/transformation/crafting/stoneblade
CAPABILITIES(/transformation/crafting/stoneblade)
	configure(transformation(name = "stone blade", makes = list(item_term(/obj/item/material/knife/stone, 1)),
		crafted = crafted(reqs = list(list(/obj/item/stack/material/flint = 2)),
			build_time = 6 SECONDS,
			category = CAT_WEAPONRY,
			subcategory = CAT_WEAPON)))


/transformation/crafting/stonewoodknife
CAPABILITIES(/transformation/crafting/stonewoodknife)
	configure(transformation(name = "stone knife", makes = list(item_term(/obj/item/material/knife/stone/wood, 1)),
		crafted = crafted(reqs = list(list(/obj/item/material/knife/stone = 1), list(/obj/item/stack/material/flint = 1), list(/obj/item/stack/material/wood = 1), list(/obj/item/stack/material/fiber = 3)),
			build_time = 12 SECONDS,
			category = CAT_WEAPONRY,
			subcategory = CAT_WEAPON)))


/transformation/crafting/stoneboneknife
CAPABILITIES(/transformation/crafting/stoneboneknife)
	configure(transformation(name = "stone knife", makes = list(item_term(/obj/item/material/knife/stone/bone, 1)),
		crafted = crafted(reqs = list(list(/obj/item/material/knife/stone = 1), list(/obj/item/stack/material/flint = 1), list(/obj/item/bone = 1), list(/obj/item/stack/material/fiber = 3)),
			build_time = 12 SECONDS,
			category = CAT_WEAPONRY,
			subcategory = CAT_WEAPON)))


/transformation/crafting/woodbucket
CAPABILITIES(/transformation/crafting/woodbucket)
	configure(transformation(name = "wooden bucket", makes = list(item_term(/obj/item/reagent_containers/glass/bucket/wood, 1)),
		crafted = crafted(reqs = list(list(/obj/item/stack/material/wood = 1), list(/obj/item/stack/material/stick = 1), list(/obj/item/stack/material/fiber = 2)),
			build_time = 6 SECONDS,
			category = CAT_TOOL)))


/transformation/crafting/sticks
CAPABILITIES(/transformation/crafting/sticks)
	configure(transformation(name = "sticks", makes = list(item_term(/obj/item/stack/material/stick/fivestack, 1)),
		crafted = crafted(reqs = list(list(/obj/item/stack/material/wood = 1)),
			tool_paths = list(/obj/item/material/knife),
			build_time = 20 SECONDS,
			category = CAT_MISC)))


/transformation/crafting/stonewoodaxe
CAPABILITIES(/transformation/crafting/stonewoodaxe)
	configure(transformation(name = "stone axe", makes = list(item_term(/obj/item/material/knife/machete/hatchet/stone, 1)),
		crafted = crafted(reqs = list(list(/obj/item/material/knife/stone = 1), list(/obj/item/stack/material/flint = 1), list(/obj/item/stack/material/stick = 1), list(/obj/item/stack/material/fiber = 3)),
			build_time = 12 SECONDS,
			category = CAT_WEAPONRY,
			subcategory = CAT_WEAPON)))


/transformation/crafting/stoneboneaxe
CAPABILITIES(/transformation/crafting/stoneboneaxe)
	configure(transformation(name = "stone axe", makes = list(item_term(/obj/item/material/knife/machete/hatchet/stone/bone, 1)),
		crafted = crafted(reqs = list(list(/obj/item/material/knife/stone = 1), list(/obj/item/stack/material/flint = 1), list(/obj/item/bone = 1), list(/obj/item/stack/material/fiber = 3)),
			build_time = 12 SECONDS,
			category = CAT_WEAPONRY,
			subcategory = CAT_WEAPON)))


/transformation/crafting/stonewoodspear
CAPABILITIES(/transformation/crafting/stonewoodspear)
	configure(transformation(name = "stone spear", makes = list(item_term(/obj/item/material/twohanded/spear/flint, 1)),
		crafted = crafted(reqs = list(list(/obj/item/material/knife/stone = 1), list(/obj/item/stack/material/flint = 1), list(/obj/item/stack/material/wood = 2), list(/obj/item/stack/material/fiber = 3)),
			build_time = 12 SECONDS,
			category = CAT_WEAPONRY,
			subcategory = CAT_WEAPON)))


/transformation/crafting/stonebonespear
CAPABILITIES(/transformation/crafting/stonebonespear)
	configure(transformation(name = "stone spear", makes = list(item_term(/obj/item/material/twohanded/spear/flint, 1)),
		crafted = crafted(reqs = list(list(/obj/item/material/knife/stone = 1), list(/obj/item/stack/material/flint = 1), list(/obj/item/bone = 2), list(/obj/item/stack/material/fiber = 3)),
			build_time = 12 SECONDS,
			category = CAT_WEAPONRY,
			subcategory = CAT_WEAPON)))


/transformation/crafting/ropebindings
CAPABILITIES(/transformation/crafting/ropebindings)
	configure(transformation(name = "rope bindings", makes = list(item_term(/obj/item/handcuffs/cable/plantfiber, 1)),
		crafted = crafted(reqs = list(list(/obj/item/stack/material/fiber = 3)),
			build_time = 6 SECONDS,
			category = CAT_MISC)))

