/transformation/crafting/stunprod
CAPABILITIES(/transformation/crafting/stunprod)
	configure(transformation(name = "Stunprod", makes = list(item_term(/obj/item/melee/baton/cattleprod, 1)),
		crafted = crafted(reqs = list(list(/obj/item/handcuffs/cable = 1), list(/obj/item/stack/rods = 1), list(/obj/item/tool/wirecutters = 1)),
			build_time = 4 SECONDS,
			category = CAT_WEAPONRY,
			subcategory = CAT_WEAPON)))


/transformation/crafting/spear
CAPABILITIES(/transformation/crafting/spear)
	configure(transformation(name = "Spear", makes = list(item_term(/obj/item/material/twohanded/spear, 1)),
		crafted = crafted(reqs = list(list(/obj/item/handcuffs/cable = 1), list(/obj/item/stack/rods = 1), list(/obj/item/material/shard = 1, /obj/item/material/butterflyblade = 1)),
			parts = list(/obj/item/material/shard = 1, /obj/item/material/butterflyblade = 1),
			build_time = 4 SECONDS,
			category = CAT_WEAPONRY,
			subcategory = CAT_WEAPON)))


/transformation/crafting/shortbow
CAPABILITIES(/transformation/crafting/shortbow)
	configure(transformation(name = "Shortbow", makes = list(item_term(/obj/item/gun/launcher/crossbow/bow, 1)),
		crafted = crafted(reqs = list(list(/obj/item/stack/material/wood = 10), list(/obj/item/stack/material/cloth = 5)),
			build_time = 12 SECONDS,
			category = CAT_WEAPONRY,
			subcategory = CAT_WEAPON)))


/transformation/crafting/arrow_sandstone
CAPABILITIES(/transformation/crafting/arrow_sandstone)
	configure(transformation(name = "Wood arrow (sandstone tip)", makes = list(item_term(/obj/item/arrow/standard, 1)),
		crafted = crafted(reqs = list(list(/obj/item/stack/material/wood = 2), list(/obj/item/stack/material/sandstone = 2)),
			build_time = 4 SECONDS,
			category = CAT_WEAPONRY,
			subcategory = CAT_AMMO)))


/transformation/crafting/arrow_marble
CAPABILITIES(/transformation/crafting/arrow_marble)
	configure(transformation(name = "Wood arrow (marble tip)", makes = list(item_term(/obj/item/arrow/standard, 1)),
		crafted = crafted(reqs = list(list(/obj/item/stack/material/wood = 2), list(/obj/item/stack/material/marble = 2)),
			build_time = 4 SECONDS,
			category = CAT_WEAPONRY,
			subcategory = CAT_AMMO)))


/transformation/crafting/primitive_shield
CAPABILITIES(/transformation/crafting/primitive_shield)
	configure(transformation(name = "Primitive Shield", makes = list(item_term(/obj/item/shield/primitive, 1)),
		crafted = crafted(reqs = list(list(/obj/item/stack/material/wood = 2), list(/obj/item/reagent_containers/glass/bucket/wood =1), list(/obj/item/stack/material/cloth = 5)),
			build_time = 12 SECONDS,
			category = CAT_WEAPONRY,
			subcategory = CAT_WEAPON)))


/transformation/crafting/scopedrifle
CAPABILITIES(/transformation/crafting/scopedrifle)
	configure(transformation(name = "Bolt scope to bolt-action (cannot be removed)", makes = list(item_term(/obj/item/gun/projectile/shotgun/pump/rifle/scoped, 1)),
		crafted = crafted(reqs = list(list(/obj/item/binoculars/scope = 1), list(/obj/item/gun/projectile/shotgun/pump/rifle = 1)),
			build_time = 18 SECONDS,
			category = CAT_WEAPONRY,
			subcategory = CAT_WEAPON)))


/transformation/crafting/ziplaser
CAPABILITIES(/transformation/crafting/ziplaser)
	configure(transformation(name = "Ziplaser", makes = list(item_term(/obj/item/gun/energy/zip/craftable, 1)),
		crafted = crafted(reqs = list(list(/obj/item/cell/high = 1), list(/obj/item/stack/rods = 2), list(/obj/item/stack/material/steel = 8), list(/obj/item/stack/material/plastic = 5), list(/obj/item/cell/device = 2)),
			build_time = 12 SECONDS,
			category = CAT_WEAPONRY,
			subcategory = CAT_WEAPON)))

