/transformation/crafting/primitive_platecarrier
CAPABILITIES(/transformation/crafting/primitive_platecarrier)
	configure(transformation(name = "primitive plate carrier", makes = list(item_term(/obj/item/clothing/suit/armor/pcarrier/primative, 1)),
		crafted = crafted(reqs = list(list(/obj/item/stack/material/leather = 10), list(/obj/item/stack/rods = 4), list(/obj/item/stack/material/cloth = 5)),
			build_time = 12 SECONDS,
			category = CAT_CLOTHING)))


/transformation/crafting/solarcloak
CAPABILITIES(/transformation/crafting/solarcloak)
	configure(transformation(name = "solar cloak", makes = list(item_term(/obj/item/clothing/suit/armor/firecloak, 1)),
		crafted = crafted(reqs = list(list(/obj/item/stack/material/cloth = 10), list(/obj/item/stack/material/wisp = 2)),
			build_time = 6 SECONDS,
			category = CAT_CLOTHING)))


/transformation/crafting/dreamcloak
CAPABILITIES(/transformation/crafting/dreamcloak)
	configure(transformation(name = "solar cloak", makes = list(item_term(/obj/item/clothing/suit/armor/alien/dreamercloak, 1)),
		crafted = crafted(reqs = list(list(/obj/item/stack/material/cloth = 10), list(/obj/item/stack/material/dreamscale = 2)),
			build_time = 6 SECONDS,
			category = CAT_CLOTHING)))


/transformation/crafting/toxinregengloves
CAPABILITIES(/transformation/crafting/toxinregengloves)
	configure(transformation(name = "purging gloves", makes = list(item_term(/obj/item/clothing/gloves/toxinregen, 1)),
		crafted = crafted(reqs = list(list(/obj/item/stack/material/cloth = 10), list(/obj/item/stack/material/crystalscale = 2), list(/obj/item/stack/material/resin = 8), list(/obj/item/stock_parts/capacitor = 1)),
			build_time = 6 SECONDS,
			category = CAT_CLOTHING)))


/transformation/crafting/iceboots
CAPABILITIES(/transformation/crafting/iceboots)
	configure(transformation(name = "frost boots", makes = list(item_term(/obj/item/clothing/shoes/boots/frost, 1)),
		crafted = crafted(reqs = list(list(/obj/item/stack/material/frostscale = 2), list(/obj/item/clothing/shoes/boots/winter = 1)),
			build_time = 6 SECONDS,
			category = CAT_CLOTHING)))


/transformation/crafting/strangepistol
CAPABILITIES(/transformation/crafting/strangepistol)
	configure(transformation(name = "Strange Weapon", makes = list(item_term(/obj/item/gun/energy/icelauncher, 1)),
		crafted = crafted(reqs = list(list(/obj/item/stack/material/steel = 8), list(/obj/item/stack/material/plastic = 3), list(/obj/item/cell/device = 1), list(/obj/item/stack/material/frostscale = 2)),
			build_time = 6 SECONDS,
			category = CAT_WEAPONRY,
			subcategory = CAT_WEAPON)))


/transformation/crafting/solarrapier
CAPABILITIES(/transformation/crafting/solarrapier)
	configure(transformation(name = "Solar Rapier", makes = list(item_term(/obj/item/material/sword/rapier/solar, 1)),
		crafted = crafted(reqs = list(list(/obj/item/stack/material/steel = 15), list(/obj/item/stack/material/leather = 3), list(/obj/item/stack/material/wisp = 2)),
			build_time = 6 SECONDS,
			category = CAT_WEAPONRY,
			subcategory = CAT_WEAPON)))


/transformation/crafting/gravityhammer
CAPABILITIES(/transformation/crafting/gravityhammer)
	configure(transformation(name = "Gravity Hammer", makes = list(item_term(/obj/item/material/twohanded/sledgehammer/gravity, 1)),
		crafted = crafted(reqs = list(list(/obj/item/stack/material/steel = 15), list(/obj/item/stack/material/leather = 3), list(/obj/item/stack/material/shellchitin = 2), list(/obj/item/cell/high = 1)),
			build_time = 6 SECONDS,
			category = CAT_WEAPONRY,
			subcategory = CAT_WEAPON)))


/transformation/crafting/harvester
CAPABILITIES(/transformation/crafting/harvester)
	configure(transformation(name = "Harvester", makes = list(item_term(/obj/item/material/twohanded/fireaxe/scythe/harvester, 1)),
		crafted = crafted(reqs = list(list(/obj/item/stack/material/steel = 15), list(/obj/item/stack/material/leather = 3), list(/obj/item/stack/material/dreamscale = 2)),
			build_time = 6 SECONDS,
			category = CAT_WEAPONRY,
			subcategory = CAT_WEAPON)))



//SS13 survivial part 1 aka me giving outsiders easier access to some things.
/transformation/crafting/sandstone
CAPABILITIES(/transformation/crafting/sandstone)
	configure(transformation(name = "sandstone brick", makes = list(item_term(/obj/item/stack/material/sandstone, 1)),
		crafted = crafted(reqs = list(list(/obj/item/ore/glass = 4)),
			build_time = 1 SECONDS,
			category = CAT_PRIMAL)))


/transformation/crafting/marble
CAPABILITIES(/transformation/crafting/marble)
	configure(transformation(name = "marble brick", makes = list(item_term(/obj/item/stack/material/marble, 1)),
		crafted = crafted(reqs = list(list(/obj/item/ore/marble = 4)),
			build_time = 1 SECONDS,
			category = CAT_PRIMAL)))

