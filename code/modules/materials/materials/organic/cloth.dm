/datum/material/cloth
	name = MAT_CLOTH
	material_class = MATCLASS_ORGANIC
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
	stack_type = /obj/item/stack/material/cloth //CHOMPEdit


/datum/material/cloth/generate_recipes() //Vorestation Add - adding some funny cool storage pouches to this so botany can do things other than food
	recipes = list(
		new /datum/stack_recipe("woven net", /obj/item/material/fishing_net, 10, time = 30 SECONDS, pass_stack_color = TRUE, supplied_material = "[name]"),
		new /datum/stack_recipe("bedsheet", /obj/item/bedsheet, 10, time = 30 SECONDS, pass_stack_color = TRUE, recycle_material = "[name]"),
		new /datum/stack_recipe("uniform", /obj/item/clothing/under/color/white, 8, time = 15 SECONDS, pass_stack_color = TRUE, recycle_material = "[name]"),
		new /datum/stack_recipe("foot wraps", /obj/item/clothing/shoes/footwraps, 2, time = 5 SECONDS, pass_stack_color = TRUE, recycle_material = "[name]"),
		new /datum/stack_recipe("gloves", /obj/item/clothing/gloves/white, 2, time = 5 SECONDS, pass_stack_color = TRUE, recycle_material = "[name]"),
		new /datum/stack_recipe("wig", /obj/item/clothing/head/powdered_wig, 4, time = 10 SECONDS, pass_stack_color = TRUE, recycle_material = "[name]"),
		new /datum/stack_recipe("philosopher's wig", /obj/item/clothing/head/philosopher_wig, 50, time = 2 MINUTES, pass_stack_color = TRUE, recycle_material = "[name]"),
		new /datum/stack_recipe("taqiyah", /obj/item/clothing/head/taqiyah, 3, time = 6 SECONDS, pass_stack_color = TRUE, recycle_material = "[name]"),
		new /datum/stack_recipe("turban", /obj/item/clothing/head/turban, 3, time = 6 SECONDS, pass_stack_color = TRUE, recycle_material = "[name]"),
		new /datum/stack_recipe("hijab", /obj/item/clothing/head/hijab, 3, time = 6 SECONDS, pass_stack_color = TRUE, recycle_material = "[name]"),
		new /datum/stack_recipe("kippa", /obj/item/clothing/head/kippa, 3, time = 6 SECONDS, pass_stack_color = TRUE, recycle_material = "[name]"),
		new /datum/stack_recipe("scarf", /obj/item/clothing/accessory/scarf/white, 4, time = 5 SECONDS, pass_stack_color = TRUE, recycle_material = "[name]"),
		new /datum/stack_recipe("baggy pants", /obj/item/clothing/under/pants/baggy/white, 8, time = 10 SECONDS, pass_stack_color = TRUE, recycle_material = "[name]"),
		new /datum/stack_recipe("belt pouch", /obj/item/storage/belt/fannypack/white, 25, time = 1 MINUTE, pass_stack_color = TRUE, recycle_material = "[name]"),
		new /datum/stack_recipe("pouch, small", /obj/item/storage/pouch/small, 10, time = 20 SECONDS, pass_stack_color = FALSE, recycle_material = "[name]"), //vorestation Add
		new /datum/stack_recipe("pouch, ammo", /obj/item/storage/pouch/ammo, 10, time = 20 SECONDS, pass_stack_color = FALSE, recycle_material = "[name]"), //vorestation Add
		new /datum/stack_recipe("pouch, tools", /obj/item/storage/pouch/eng_tool, 10, time = 20 SECONDS, pass_stack_color = FALSE, recycle_material = "[name]"), //vorestation Add
		new /datum/stack_recipe("pouch, parts", /obj/item/storage/pouch/eng_parts, 10, time = 20 SECONDS, pass_stack_color = FALSE, recycle_material = "[name]"), //vorestation Add
		new /datum/stack_recipe("pouch, supplies", /obj/item/storage/pouch/eng_supply, 10, time = 20 SECONDS, pass_stack_color = FALSE, recycle_material = "[name]"), //vorestation Add
		new /datum/stack_recipe("pouch, medical", /obj/item/storage/pouch/medical, 10, time = 20 SECONDS, pass_stack_color = FALSE, recycle_material = "[name]"), //vorestation Add
		new /datum/stack_recipe("pouch, flare", /obj/item/storage/pouch/flares, 10, time = 20 SECONDS, pass_stack_color = FALSE, recycle_material = "[name]"), //vorestation Add
		new /datum/stack_recipe("crude bandage", /obj/item/stack/medical/crude_pack, 1, time = 2 SECONDS, pass_stack_color = TRUE, recycle_material = "[name]"),
		new /datum/stack_recipe("empty sandbag", /obj/item/stack/emptysandbag, 2, time = 2 SECONDS, pass_stack_color = TRUE, supplied_material = "[name]"),
		new /datum/stack_recipe("painting canvas (11x11)", /obj/item/canvas, 2, time = 2 SECONDS, pass_stack_color = FALSE, supplied_material = "[name]"),
		new /datum/stack_recipe("painting canvas (19x19)", /obj/item/canvas/nineteen_nineteen, 3, time = 2 SECONDS, pass_stack_color = FALSE, supplied_material = "[name]"),
		new /datum/stack_recipe("painting canvas (23x19)", /obj/item/canvas/twentythree_nineteen, 4, time = 3 SECONDS, pass_stack_color = FALSE, supplied_material = "[name]"),
		new /datum/stack_recipe("painting canvas (23x23), AI", /obj/item/canvas/twentythree_twentythree, 5, time = 3 SECONDS, pass_stack_color = FALSE, supplied_material = "[name]"),
		new /datum/stack_recipe("painting canvas (24x24)", /obj/item/canvas/twentyfour_twentyfour, 6, time = 3 SECONDS, pass_stack_color = FALSE, supplied_material = "[name]")
	)

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



//CHOMPedit: added stacktype var inside cloth_ch.dm
/datum/material/carpet
	name = MAT_CARPET
	display_name = "comfy"
	use_name = "red upholstery"
	material_class = MATCLASS_ORGANIC
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
	material_class = MATCLASS_ORGANIC
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
	material_class = MATCLASS_ORGANIC
	sheet_singular_name = "fiber"
	sheet_singular_name = MAT_FIBERS
	icon_colour = "#006b0e"
	flags = MATERIAL_PADDING|MATERIAL_BRITTLE
	ignition_point = T0C+232
	melting_point = T0C+300
	protectiveness = 1 // 4%
	conductive = 0
	pass_stack_colors = TRUE
	hardness = 5
	integrity = 5
	stack_type = /obj/item/stack/material/fiber //CHOMPEdit
	supply_conversion_value = 1


// === merged from cloth_ch.dm during hard-fork de-suffix (verified no override-order change) ===
//Red Color Fix
/datum/material/cloth_red
	name = "carpet" //This is the easiest fix but god do i hate it -shark
	display_name = "red"
	use_name = "red cloth"
	material_class = MATCLASS_ORGANIC
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
