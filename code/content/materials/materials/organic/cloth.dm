/datum/material/cloth
	name = MAT_CLOTH
	door_icon_base = "wood"
	ignition_point = T0C+232
	melting_point = T0C+300
	protectiveness = 1 // 4%
	flags = MATERIAL_PADDING
	conductive = 0
	integrity = 40
	pass_stack_colors = TRUE
	supply_conversion_value = 2
	hardness = 5
	stack_type = /obj/item/stack/material/cloth


/transformation/stack/cloth__woven_net
CAPABILITIES(/transformation/stack/cloth__woven_net)
	configure(transformation(takes = list(stack_term(STACK_SELF, 10)), makes = list(item_term(/obj/item/material/fishing_net, 1)),
		chosen = chosen(title = "woven net",
			subject = /datum/material/cloth,
			build_time = 30 SECONDS,
			material = STACK_MATERIAL_SELF,
			pass_color = TRUE,
			replaces = TRUE)))

/transformation/stack/cloth__bedsheet
CAPABILITIES(/transformation/stack/cloth__bedsheet)
	configure(transformation(takes = list(stack_term(STACK_SELF, 10)), makes = list(item_term(/obj/item/bedsheet, 1)),
		chosen = chosen(title = "bedsheet",
			subject = /datum/material/cloth,
			build_time = 30 SECONDS,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/cloth__uniform
CAPABILITIES(/transformation/stack/cloth__uniform)
	configure(transformation(takes = list(stack_term(STACK_SELF, 8)), makes = list(item_term(/obj/item/clothing/under/color/white, 1)),
		chosen = chosen(title = "uniform",
			subject = /datum/material/cloth,
			build_time = 15 SECONDS,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/cloth__foot_wraps
CAPABILITIES(/transformation/stack/cloth__foot_wraps)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/item/clothing/shoes/footwraps, 1)),
		chosen = chosen(title = "foot wraps",
			subject = /datum/material/cloth,
			build_time = 5 SECONDS,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/cloth__gloves
CAPABILITIES(/transformation/stack/cloth__gloves)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/item/clothing/gloves/white, 1)),
		chosen = chosen(title = "gloves",
			subject = /datum/material/cloth,
			build_time = 5 SECONDS,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/cloth__wig
CAPABILITIES(/transformation/stack/cloth__wig)
	configure(transformation(takes = list(stack_term(STACK_SELF, 4)), makes = list(item_term(/obj/item/clothing/head/powdered_wig, 1)),
		chosen = chosen(title = "wig",
			subject = /datum/material/cloth,
			build_time = 10 SECONDS,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/cloth__philosopher_s_wig
CAPABILITIES(/transformation/stack/cloth__philosopher_s_wig)
	configure(transformation(takes = list(stack_term(STACK_SELF, 50)), makes = list(item_term(/obj/item/clothing/head/philosopher_wig, 1)),
		chosen = chosen(title = "philosopher's wig",
			subject = /datum/material/cloth,
			build_time = 2 MINUTES,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/cloth__taqiyah
CAPABILITIES(/transformation/stack/cloth__taqiyah)
	configure(transformation(takes = list(stack_term(STACK_SELF, 3)), makes = list(item_term(/obj/item/clothing/head/taqiyah, 1)),
		chosen = chosen(title = "taqiyah",
			subject = /datum/material/cloth,
			build_time = 6 SECONDS,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/cloth__turban
CAPABILITIES(/transformation/stack/cloth__turban)
	configure(transformation(takes = list(stack_term(STACK_SELF, 3)), makes = list(item_term(/obj/item/clothing/head/turban, 1)),
		chosen = chosen(title = "turban",
			subject = /datum/material/cloth,
			build_time = 6 SECONDS,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/cloth__hijab
CAPABILITIES(/transformation/stack/cloth__hijab)
	configure(transformation(takes = list(stack_term(STACK_SELF, 3)), makes = list(item_term(/obj/item/clothing/head/hijab, 1)),
		chosen = chosen(title = "hijab",
			subject = /datum/material/cloth,
			build_time = 6 SECONDS,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/cloth__kippa
CAPABILITIES(/transformation/stack/cloth__kippa)
	configure(transformation(takes = list(stack_term(STACK_SELF, 3)), makes = list(item_term(/obj/item/clothing/head/kippa, 1)),
		chosen = chosen(title = "kippa",
			subject = /datum/material/cloth,
			build_time = 6 SECONDS,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/cloth__scarf
CAPABILITIES(/transformation/stack/cloth__scarf)
	configure(transformation(takes = list(stack_term(STACK_SELF, 4)), makes = list(item_term(/obj/item/clothing/accessory/scarf/white, 1)),
		chosen = chosen(title = "scarf",
			subject = /datum/material/cloth,
			build_time = 5 SECONDS,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/cloth__baggy_pants
CAPABILITIES(/transformation/stack/cloth__baggy_pants)
	configure(transformation(takes = list(stack_term(STACK_SELF, 8)), makes = list(item_term(/obj/item/clothing/under/pants/baggy/white, 1)),
		chosen = chosen(title = "baggy pants",
			subject = /datum/material/cloth,
			build_time = 10 SECONDS,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/cloth__belt_pouch
CAPABILITIES(/transformation/stack/cloth__belt_pouch)
	configure(transformation(takes = list(stack_term(STACK_SELF, 25)), makes = list(item_term(/obj/item/storage/belt/fannypack/white, 1)),
		chosen = chosen(title = "belt pouch",
			subject = /datum/material/cloth,
			build_time = 1 MINUTE,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/cloth__pouch_small
CAPABILITIES(/transformation/stack/cloth__pouch_small)
	configure(transformation(takes = list(stack_term(STACK_SELF, 10)), makes = list(item_term(/obj/item/storage/pouch/small, 1)),
		chosen = chosen(title = "pouch, small",
			subject = /datum/material/cloth,
			build_time = 20 SECONDS,
			pass_color = FALSE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/cloth__pouch_ammo
CAPABILITIES(/transformation/stack/cloth__pouch_ammo)
	configure(transformation(takes = list(stack_term(STACK_SELF, 10)), makes = list(item_term(/obj/item/storage/pouch/ammo, 1)),
		chosen = chosen(title = "pouch, ammo",
			subject = /datum/material/cloth,
			build_time = 20 SECONDS,
			pass_color = FALSE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/cloth__pouch_tools
CAPABILITIES(/transformation/stack/cloth__pouch_tools)
	configure(transformation(takes = list(stack_term(STACK_SELF, 10)), makes = list(item_term(/obj/item/storage/pouch/eng_tool, 1)),
		chosen = chosen(title = "pouch, tools",
			subject = /datum/material/cloth,
			build_time = 20 SECONDS,
			pass_color = FALSE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/cloth__pouch_parts
CAPABILITIES(/transformation/stack/cloth__pouch_parts)
	configure(transformation(takes = list(stack_term(STACK_SELF, 10)), makes = list(item_term(/obj/item/storage/pouch/eng_parts, 1)),
		chosen = chosen(title = "pouch, parts",
			subject = /datum/material/cloth,
			build_time = 20 SECONDS,
			pass_color = FALSE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/cloth__pouch_supplies
CAPABILITIES(/transformation/stack/cloth__pouch_supplies)
	configure(transformation(takes = list(stack_term(STACK_SELF, 10)), makes = list(item_term(/obj/item/storage/pouch/eng_supply, 1)),
		chosen = chosen(title = "pouch, supplies",
			subject = /datum/material/cloth,
			build_time = 20 SECONDS,
			pass_color = FALSE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/cloth__pouch_medical
CAPABILITIES(/transformation/stack/cloth__pouch_medical)
	configure(transformation(takes = list(stack_term(STACK_SELF, 10)), makes = list(item_term(/obj/item/storage/pouch/medical, 1)),
		chosen = chosen(title = "pouch, medical",
			subject = /datum/material/cloth,
			build_time = 20 SECONDS,
			pass_color = FALSE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/cloth__pouch_flare
CAPABILITIES(/transformation/stack/cloth__pouch_flare)
	configure(transformation(takes = list(stack_term(STACK_SELF, 10)), makes = list(item_term(/obj/item/storage/pouch/flares, 1)),
		chosen = chosen(title = "pouch, flare",
			subject = /datum/material/cloth,
			build_time = 20 SECONDS,
			pass_color = FALSE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/cloth__crude_bandage
CAPABILITIES(/transformation/stack/cloth__crude_bandage)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/medical/crude_pack, 1)),
		chosen = chosen(title = "crude bandage",
			subject = /datum/material/cloth,
			build_time = 2 SECONDS,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/cloth__empty_sandbag
CAPABILITIES(/transformation/stack/cloth__empty_sandbag)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/item/stack/emptysandbag, 1)),
		chosen = chosen(title = "empty sandbag",
			subject = /datum/material/cloth,
			build_time = 2 SECONDS,
			material = STACK_MATERIAL_SELF,
			pass_color = TRUE)))

/transformation/stack/cloth__painting_canvas_11x11
CAPABILITIES(/transformation/stack/cloth__painting_canvas_11x11)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/item/canvas, 1)),
		chosen = chosen(title = "painting canvas (11x11)",
			subject = /datum/material/cloth,
			build_time = 2 SECONDS,
			material = STACK_MATERIAL_SELF,
			pass_color = FALSE)))

/transformation/stack/cloth__painting_canvas_19x19
CAPABILITIES(/transformation/stack/cloth__painting_canvas_19x19)
	configure(transformation(takes = list(stack_term(STACK_SELF, 3)), makes = list(item_term(/obj/item/canvas/nineteen_nineteen, 1)),
		chosen = chosen(title = "painting canvas (19x19)",
			subject = /datum/material/cloth,
			build_time = 2 SECONDS,
			material = STACK_MATERIAL_SELF,
			pass_color = FALSE)))

/transformation/stack/cloth__painting_canvas_23x19
CAPABILITIES(/transformation/stack/cloth__painting_canvas_23x19)
	configure(transformation(takes = list(stack_term(STACK_SELF, 4)), makes = list(item_term(/obj/item/canvas/twentythree_nineteen, 1)),
		chosen = chosen(title = "painting canvas (23x19)",
			subject = /datum/material/cloth,
			build_time = 3 SECONDS,
			material = STACK_MATERIAL_SELF,
			pass_color = FALSE)))

/transformation/stack/cloth__painting_canvas_23x23_ai
CAPABILITIES(/transformation/stack/cloth__painting_canvas_23x23_ai)
	configure(transformation(takes = list(stack_term(STACK_SELF, 5)), makes = list(item_term(/obj/item/canvas/twentythree_twentythree, 1)),
		chosen = chosen(title = "painting canvas (23x23), AI",
			subject = /datum/material/cloth,
			build_time = 3 SECONDS,
			material = STACK_MATERIAL_SELF,
			pass_color = FALSE)))

/transformation/stack/cloth__painting_canvas_24x24
CAPABILITIES(/transformation/stack/cloth__painting_canvas_24x24)
	configure(transformation(takes = list(stack_term(STACK_SELF, 6)), makes = list(item_term(/obj/item/canvas/twentyfour_twentyfour, 1)),
		chosen = chosen(title = "painting canvas (24x24)",
			subject = /datum/material/cloth,
			build_time = 3 SECONDS,
			material = STACK_MATERIAL_SELF,
			pass_color = FALSE)))

/datum/material/cloth/syncloth
	name = MAT_SYNCLOTH
	ignition_point = T0C+532
	melting_point = T0C+600
	integrity = 200
	protectiveness = 15 // 4%
	pass_stack_colors = TRUE
	supply_conversion_value = 3
	hardness = 5

/datum/material/cloth/teal
	name = MAT_CLOTH_TEAL
	display_name = MAT_CLOTH_TEAL
	use_name = "teal cloth"
	icon_colour = "#00EAFA"
	wiki_flag = WIKI_SPOILER

/datum/material/cloth/black
	name = MAT_CLOTH_BLACK
	display_name = MAT_CLOTH_BLACK
	use_name = "black cloth"
	icon_colour = "#505050"
	wiki_flag = WIKI_SPOILER

/datum/material/cloth/green
	name = MAT_CLOTH_GREEN
	display_name = MAT_CLOTH_GREEN
	use_name = "green cloth"
	icon_colour = "#01C608"
	wiki_flag = WIKI_SPOILER

/datum/material/cloth/puple
	name = MAT_CLOTH_PURPLE
	display_name = MAT_CLOTH_PURPLE
	use_name = "purple cloth"
	icon_colour = "#9C56C4"
	wiki_flag = WIKI_SPOILER

/datum/material/cloth/blue
	name = MAT_CLOTH_BLUE
	display_name = MAT_CLOTH_BLUE
	use_name = "blue cloth"
	icon_colour = "#6B6FE3"
	wiki_flag = WIKI_SPOILER

/datum/material/cloth/beige
	name = MAT_CLOTH_BEIGE
	display_name = MAT_CLOTH_BEIGE
	use_name = "beige cloth"
	icon_colour = "#E8E7C8"
	wiki_flag = WIKI_SPOILER

/datum/material/cloth/brown
	name = MAT_CLOTH_BROWN
	display_name = MAT_CLOTH_BROWN
	use_name = "brown cloth"
	icon_colour = "#5C4831"
	wiki_flag = WIKI_SPOILER

/datum/material/cloth/lime
	name = MAT_CLOTH_LIME
	display_name = MAT_CLOTH_LIME
	use_name = "lime cloth"
	icon_colour = "#62E36C"
	wiki_flag = WIKI_SPOILER

/datum/material/cloth/yellow
	name = MAT_CLOTH_YELLOW
	display_name = MAT_CLOTH_YELLOW
	use_name = "yellow cloth"
	icon_colour = "#EEF573"
	wiki_flag = WIKI_SPOILER

/datum/material/cloth/orange
	name = MAT_CLOTH_ORANGE
	display_name = MAT_CLOTH_ORANGE
	use_name = "orange cloth"
	icon_colour = "#E3BF49"
	wiki_flag = WIKI_SPOILER



// added stacktype var inside cloth_ch.dm
/datum/material/carpet
	name = MAT_CARPET
	display_name = "comfy"
	use_name = "red upholstery"
	icon_colour = "#DA020A"
	flags = MATERIAL_PADDING|MATERIAL_BRITTLE
	ignition_point = T0C+232
	melting_point = T0C+300
	sheet_singular_name = "tile"
	sheet_plural_name = "tiles"
	protectiveness = 1 // 4%
	conductive = 0
	hardness = 5
	integrity = 40
	supply_conversion_value = 0.25
	wiki_flag = WIKI_SPOILER

/datum/material/cotton
	name = MAT_COTTON
	display_name =MAT_COTTON
	icon_colour = "#FFFFFF"
	flags = MATERIAL_PADDING|MATERIAL_BRITTLE
	ignition_point = T0C+232
	melting_point = T0C+300
	protectiveness = 1 // 4%
	conductive = 0
	hardness = 5
	integrity = 10
	supply_conversion_value = 1
	stack_type = /obj/item/stack/material/cotton

/datum/material/fibers
	name = MAT_FIBERS
	display_name = "plant"
	sheet_singular_name = "fiber"
	icon_colour = "#006b0e"
	flags = MATERIAL_PADDING|MATERIAL_BRITTLE
	ignition_point = T0C+232
	melting_point = T0C+300
	protectiveness = 1 // 4%
	conductive = 0
	pass_stack_colors = TRUE
	hardness = 5
	integrity = 5
	stack_type = /obj/item/stack/material/fiber
	supply_conversion_value = 1


//Red Color Fix
/datum/material/cloth_red
	name = "carpet" //This is the easiest fix but god do i hate it -shark
	display_name = "red"
	use_name = "red cloth"
	icon_colour = "#DA020A"
	flags = MATERIAL_PADDING
	ignition_point = T0C+232
	melting_point = T0C+300
	protectiveness = 1 // 4%
	conductive = 0
	supply_conversion_value = 0

//CARPET materials

/datum/material/carpet
	stack_type = /obj/item/stack/tile/carpet

/datum/material/carpet/teal
	name = MAT_CARPET_TEAL
	icon_colour = "#007575"
	stack_type = /obj/item/stack/tile/carpet/teal

/datum/material/carpet/bcarpet
	name = MAT_CARPET_BLACK
	icon_colour = "#1B171E"
	stack_type = /obj/item/stack/tile/carpet/bcarpet

/datum/material/carpet/blucarpet
	name = MAT_CARPET_BLUE
	icon_colour = "#122CDF"
	stack_type = /obj/item/stack/tile/carpet/blucarpet

/datum/material/carpet/turcarpet
	name = MAT_CARPET_TURQUOISE
	icon_colour = "#41A997"
	stack_type = /obj/item/stack/tile/carpet/turcarpet

/datum/material/carpet/sblucarpet
	name = MAT_CARPET_SILVERBLUE
	icon_colour = "#547EC6"
	stack_type = /obj/item/stack/tile/carpet/sblucarpet

/datum/material/carpet/gaycarpet
	name = MAT_CARPET_PINK
	icon_colour = "#E12C87"
	stack_type = /obj/item/stack/tile/carpet/gaycarpet

/datum/material/carpet/purcarpet
	name = MAT_CARPET_PURPLE
	icon_colour = "#B500A6"
	stack_type = /obj/item/stack/tile/carpet/purcarpet

/datum/material/carpet/oracarpet
	name = MAT_CARPET_ORANGE
	icon_colour = "#D1D000"
	stack_type = /obj/item/stack/tile/carpet/oracarpet
