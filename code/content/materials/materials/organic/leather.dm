/datum/material/leather
	name = MAT_LEATHER
	display_name = "plainleather"
	icon_colour = "#5C4831"
	stack_type = /obj/item/stack/material/leather
	flags = MATERIAL_PADDING
	ignition_point = T0C+300
	melting_point = T0C+300
	protectiveness = 3 // 13%
	conductive = 0
	integrity = 40
	supply_conversion_value = 2

/transformation/stack/leather__bedsheet
CAPABILITIES(/transformation/stack/leather__bedsheet)
	configure(transformation(takes = list(stack_term(STACK_SELF, 10)), makes = list(item_term(/obj/item/bedsheet, 1)),
		chosen = chosen(title = "bedsheet",
			subject = /datum/material/leather,
			build_time = 30 SECONDS,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF,
			replaces = TRUE)))

/transformation/stack/leather__uniform
CAPABILITIES(/transformation/stack/leather__uniform)
	configure(transformation(takes = list(stack_term(STACK_SELF, 8)), makes = list(item_term(/obj/item/clothing/under/color/white, 1)),
		chosen = chosen(title = "uniform",
			subject = /datum/material/leather,
			build_time = 15 SECONDS,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/leather__foot_wraps
CAPABILITIES(/transformation/stack/leather__foot_wraps)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/item/clothing/shoes/footwraps, 1)),
		chosen = chosen(title = "foot wraps",
			subject = /datum/material/leather,
			build_time = 5 SECONDS,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/leather__gloves
CAPABILITIES(/transformation/stack/leather__gloves)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/item/clothing/gloves/white, 1)),
		chosen = chosen(title = "gloves",
			subject = /datum/material/leather,
			build_time = 5 SECONDS,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/leather__wig
CAPABILITIES(/transformation/stack/leather__wig)
	configure(transformation(takes = list(stack_term(STACK_SELF, 4)), makes = list(item_term(/obj/item/clothing/head/powdered_wig, 1)),
		chosen = chosen(title = "wig",
			subject = /datum/material/leather,
			build_time = 10 SECONDS,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/leather__philosopher_s_wig
CAPABILITIES(/transformation/stack/leather__philosopher_s_wig)
	configure(transformation(takes = list(stack_term(STACK_SELF, 50)), makes = list(item_term(/obj/item/clothing/head/philosopher_wig, 1)),
		chosen = chosen(title = "philosopher's wig",
			subject = /datum/material/leather,
			build_time = 2 MINUTES,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/leather__taqiyah
CAPABILITIES(/transformation/stack/leather__taqiyah)
	configure(transformation(takes = list(stack_term(STACK_SELF, 3)), makes = list(item_term(/obj/item/clothing/head/taqiyah, 1)),
		chosen = chosen(title = "taqiyah",
			subject = /datum/material/leather,
			build_time = 6 SECONDS,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/leather__turban
CAPABILITIES(/transformation/stack/leather__turban)
	configure(transformation(takes = list(stack_term(STACK_SELF, 3)), makes = list(item_term(/obj/item/clothing/head/turban, 1)),
		chosen = chosen(title = "turban",
			subject = /datum/material/leather,
			build_time = 6 SECONDS,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/leather__hijab
CAPABILITIES(/transformation/stack/leather__hijab)
	configure(transformation(takes = list(stack_term(STACK_SELF, 3)), makes = list(item_term(/obj/item/clothing/head/hijab, 1)),
		chosen = chosen(title = "hijab",
			subject = /datum/material/leather,
			build_time = 6 SECONDS,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/leather__kippa
CAPABILITIES(/transformation/stack/leather__kippa)
	configure(transformation(takes = list(stack_term(STACK_SELF, 3)), makes = list(item_term(/obj/item/clothing/head/kippa, 1)),
		chosen = chosen(title = "kippa",
			subject = /datum/material/leather,
			build_time = 6 SECONDS,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/leather__scarf
CAPABILITIES(/transformation/stack/leather__scarf)
	configure(transformation(takes = list(stack_term(STACK_SELF, 4)), makes = list(item_term(/obj/item/clothing/accessory/scarf/white, 1)),
		chosen = chosen(title = "scarf",
			subject = /datum/material/leather,
			build_time = 5 SECONDS,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/leather__baggy_pants
CAPABILITIES(/transformation/stack/leather__baggy_pants)
	configure(transformation(takes = list(stack_term(STACK_SELF, 8)), makes = list(item_term(/obj/item/clothing/under/pants/baggy/white, 1)),
		chosen = chosen(title = "baggy pants",
			subject = /datum/material/leather,
			build_time = 10 SECONDS,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/leather__belt_pouch
CAPABILITIES(/transformation/stack/leather__belt_pouch)
	configure(transformation(takes = list(stack_term(STACK_SELF, 25)), makes = list(item_term(/obj/item/storage/belt/fannypack/white, 1)),
		chosen = chosen(title = "belt pouch",
			subject = /datum/material/leather,
			build_time = 1 MINUTE,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/leather__pouch_medium
CAPABILITIES(/transformation/stack/leather__pouch_medium)
	configure(transformation(takes = list(stack_term(STACK_SELF, 10)), makes = list(item_term(/obj/item/storage/pouch, 1)),
		chosen = chosen(title = "pouch, medium",
			subject = /datum/material/leather,
			build_time = 20 SECONDS,
			pass_color = FALSE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/leather__pouch_large
CAPABILITIES(/transformation/stack/leather__pouch_large)
	configure(transformation(takes = list(stack_term(STACK_SELF, 15)), makes = list(item_term(/obj/item/storage/pouch/large, 1)),
		chosen = chosen(title = "pouch, large",
			subject = /datum/material/leather,
			build_time = 30 SECONDS,
			pass_color = FALSE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/leather__pouch_holster
CAPABILITIES(/transformation/stack/leather__pouch_holster)
	configure(transformation(takes = list(stack_term(STACK_SELF, 10)), makes = list(item_term(/obj/item/storage/pouch/holster, 1)),
		chosen = chosen(title = "pouch, holster",
			subject = /datum/material/leather,
			build_time = 20 SECONDS,
			pass_color = FALSE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/leather__pouch_melee
CAPABILITIES(/transformation/stack/leather__pouch_melee)
	configure(transformation(takes = list(stack_term(STACK_SELF, 10)), makes = list(item_term(/obj/item/storage/pouch/baton, 1)),
		chosen = chosen(title = "pouch, melee",
			subject = /datum/material/leather,
			build_time = 20 SECONDS,
			pass_color = FALSE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/leather__crude_bandage
CAPABILITIES(/transformation/stack/leather__crude_bandage)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/medical/crude_pack, 1)),
		chosen = chosen(title = "crude {display_name} bandage",
			subject = /datum/material/leather,
			build_time = 2 SECONDS,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/leather__net
CAPABILITIES(/transformation/stack/leather__net)
	configure(transformation(takes = list(stack_term(STACK_SELF, 10)), makes = list(item_term(/obj/item/material/fishing_net, 1)),
		chosen = chosen(title = "{display_name} net",
			subject = /datum/material/leather,
			build_time = 5 SECONDS,
			material = STACK_MATERIAL_SELF,
			pass_color = TRUE)))

/transformation/stack/leather__ring
CAPABILITIES(/transformation/stack/leather__ring)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/clothing/accessory/ring/material, 1)),
		chosen = chosen(title = "{display_name} ring",
			subject = /datum/material/leather,
			on_floor = 1,
			material = STACK_MATERIAL_SELF,
			pass_color = TRUE)))

/transformation/stack/leather__bracelet
CAPABILITIES(/transformation/stack/leather__bracelet)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/clothing/accessory/bracelet/material, 1)),
		chosen = chosen(title = "{display_name} bracelet",
			subject = /datum/material/leather,
			on_floor = 1,
			material = STACK_MATERIAL_SELF,
			pass_color = TRUE)))

/transformation/stack/leather__armor_plate
CAPABILITIES(/transformation/stack/leather__armor_plate)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/material/armor_plating, 1)),
		chosen = chosen(title = "{display_name} armor plate",
			subject = /datum/material/leather,
			build_time = 20,
			on_floor = 1,
			material = STACK_MATERIAL_SELF,
			pass_color = TRUE)))

/transformation/stack/leather__empty_sandbag
CAPABILITIES(/transformation/stack/leather__empty_sandbag)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/item/stack/emptysandbag, 1)),
		chosen = chosen(title = "empty sandbag",
			subject = /datum/material/leather,
			build_time = 2 SECONDS,
			material = STACK_MATERIAL_SELF,
			pass_color = TRUE)))

/transformation/stack/leather__whip
CAPABILITIES(/transformation/stack/leather__whip)
	configure(transformation(takes = list(stack_term(STACK_SELF, 5)), makes = list(item_term(/obj/item/material/whip, 1)),
		chosen = chosen(title = "whip",
			subject = /datum/material/leather,
			build_time = 15 SECONDS,
			material = STACK_MATERIAL_SELF,
			pass_color = TRUE)))

