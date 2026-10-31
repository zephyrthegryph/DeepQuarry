/datum/material/phoron
	name = MAT_PHORON
	stack_type = /obj/item/stack/material/phoron
	ignition_point = PLASMA_MINIMUM_BURN_TEMPERATURE
	icon_base = "stone"
	table_icon_base = "stone"
	icon_colour = "#FC2BC5"
	shard_type = SHARD_SHARD
	hardness = 30
	door_icon_base = "stone"
	sheet_singular_name = "crystal"
	sheet_plural_name = "crystals"
	supply_conversion_value = 5


/datum/material/diamond
	name = MAT_DIAMOND
	stack_type = /obj/item/stack/material/diamond
	flags = MATERIAL_UNMELTABLE
	cut_delay = 60
	icon_colour = "#00FFE1"
	opacity = 0.4
	reflectivity = 0.6
	conductive = 0
	conductivity = 1
	shard_type = SHARD_SHARD
	tableslam_noise = 'sound/effects/Glasshit.ogg'
	hardness = 100
	supply_conversion_value = 8
	icon_base = "stone"
	table_icon_base = "stone"

/datum/material/quartz
	name = MAT_QUARTZ
	display_name = MAT_QUARTZ
	use_name = MAT_QUARTZ
	icon_colour = "#e6d7df"
	stack_type = /obj/item/stack/material/quartz
	tableslam_noise = 'sound/effects/Glasshit.ogg'
	sheet_singular_name = "crystal"
	sheet_plural_name = "crystals"
	supply_conversion_value = 4
	icon_base = "stone"
	table_icon_base = "stone"

/datum/material/painite
	name = MAT_PAINITE
	display_name = MAT_PAINITE
	use_name = MAT_PAINITE
	icon_colour = "#6b4947"
	stack_type = /obj/item/stack/material/painite
	flags = MATERIAL_UNMELTABLE
	reflectivity = 0.3
	tableslam_noise = 'sound/effects/Glasshit.ogg'
	sheet_singular_name = "gem"
	sheet_plural_name = "gems"
	supply_conversion_value = 4
	icon_base = "stone"
	table_icon_base = "stone"

/datum/material/void_opal
	name = MAT_VOPAL
	display_name = MAT_VOPAL
	use_name = MAT_VOPAL
	icon_colour = "#0f0f0f"
	stack_type = /obj/item/stack/material/void_opal
	flags = MATERIAL_UNMELTABLE
	cut_delay = 60
	reflectivity = 0
	conductivity = 1
	shard_type = SHARD_SHARD
	tableslam_noise = 'sound/effects/Glasshit.ogg'
	hardness = 100
	sheet_singular_name = "gem"
	sheet_plural_name = "gems"
	supply_conversion_value = 30	// These are hilariously rare.
	icon_base = "stone"
	table_icon_base = "stone"

// Particle Smasher and other exotic materials.
/datum/material/valhollide
	name = MAT_VALHOLLIDE
	stack_type = /obj/item/stack/material/valhollide
	icon_base = "stone"
	door_icon_base = "stone"
	icon_reinf = "reinf_mesh"
	icon_colour = "#FFF3B2"
	protectiveness = 30
	integrity = 240
	density = 30
	hardness = 45
	negation = 2
	conductive = 0
	conductivity = 5
	reflectivity = 0.5
	radiation_resistance = 20
	spatial_instability = 30
	sheet_singular_name = "gem"
	sheet_plural_name = "gems"
	icon_base = "stone"
	table_icon_base = "stone"
	supply_conversion_value = 10

/datum/material/verdantium
	name = MAT_VERDANTIUM
	stack_type = /obj/item/stack/material/verdantium
	icon_base = "metal"
	door_icon_base = "metal"
	icon_reinf = "reinf_metal"
	icon_colour = "#4FE95A"
	integrity = 80
	protectiveness = 15
	density = 15
	hardness = 30
	shard_type = SHARD_SHARD
	negation = 15
	conductivity = 60
	reflectivity = 0.3
	radiation_resistance = 5
	sheet_singular_name = "sheet"
	sheet_plural_name = "sheets"
	supply_conversion_value = 8
	icon_base = "stone"
	table_icon_base = "stone"

/datum/material/morphium
	name = MAT_MORPHIUM
	stack_type = /obj/item/stack/material/morphium
	icon_base = "metal"
	door_icon_base = "metal"
	icon_colour = "#37115A"
	icon_reinf = "reinf_metal"
	protectiveness = 60
	integrity = 300
	conductive = 0
	conductivity = 1.5
	hardness = 90
	shard_type = SHARD_SHARD
	density = 30
	negation = 25
	explosion_resistance = 85
	reflectivity = 0.2
	radiation_resistance = 10
	supply_conversion_value = 13
	icon_base = "stone"
	table_icon_base = "stone"

/datum/material/glamour
	name = MAT_GLAMOUR
	stack_type = /obj/item/stack/material/glamour
	icon_base = "stone"
	door_icon_base = "stone"
	icon_colour = "#fffee7"
	icon_reinf = "reinf_mesh"
	protectiveness = 70
	integrity = 300
	conductive = 1
	conductivity = 20
	hardness = 120
	shard_type = SHARD_SHARD
	density = 20
	negation = 35
	explosion_resistance = 20
	reflectivity = 1
	radiation_resistance = 100
	supply_conversion_value = 15
	icon_base = "stone"
	table_icon_base = "stone"

/transformation/stack/glamour__oar
CAPABILITIES(/transformation/stack/glamour__oar)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/item/oar, 1)),
		chosen = chosen(title = "oar",
			subject = /datum/material/glamour,
			build_time = 30,
			material = STACK_MATERIAL_SELF,
			pass_color = TRUE)))

/transformation/stack/glamour__boat
CAPABILITIES(/transformation/stack/glamour__boat)
	configure(transformation(takes = list(stack_term(STACK_SELF, 20)), makes = list(item_term(/obj/vehicle/boat, 1)),
		chosen = chosen(title = "boat",
			subject = /datum/material/glamour,
			build_time = 10 SECONDS,
			material = STACK_MATERIAL_SELF,
			pass_color = TRUE)))

/transformation/stack/glamour__dragon_boat
CAPABILITIES(/transformation/stack/glamour__dragon_boat)
	configure(transformation(takes = list(stack_term(STACK_SELF, 50)), makes = list(item_term(/obj/vehicle/boat/dragon, 1)),
		chosen = chosen(title = "dragon boat",
			subject = /datum/material/glamour,
			build_time = 30 SECONDS,
			material = STACK_MATERIAL_SELF,
			pass_color = TRUE)))

/transformation/stack/glamour__glamour_sandals
CAPABILITIES(/transformation/stack/glamour__glamour_sandals)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/clothing/shoes/sandal, 1)),
		chosen = chosen(title = "glamour sandals",
			subject = /datum/material/glamour,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/glamour__glamour_circlet
CAPABILITIES(/transformation/stack/glamour__glamour_circlet)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/clothing/head/woodcirclet, 1)),
		chosen = chosen(title = "glamour circlet",
			subject = /datum/material/glamour,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/glamour__book_shelf
CAPABILITIES(/transformation/stack/glamour__book_shelf)
	configure(transformation(takes = list(stack_term(STACK_SELF, 5)), makes = list(item_term(/obj/structure/bookcase, 1)),
		chosen = chosen(title = "book shelf",
			subject = /datum/material/glamour,
			build_time = 15,
			one_per_turf = 1,
			on_floor = 1,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/glamour__glamour_shelves
CAPABILITIES(/transformation/stack/glamour__glamour_shelves)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/structure/table/rack/shelf/wood, 1)),
		chosen = chosen(title = "glamour shelves",
			subject = /datum/material/glamour,
			build_time = 5,
			one_per_turf = TRUE,
			on_floor = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/glamour__glamour_standup_figure
CAPABILITIES(/transformation/stack/glamour__glamour_standup_figure)
	configure(transformation(takes = list(stack_term(STACK_SELF, 5)), makes = list(item_term(/obj/structure/barricade/cutout, 1)),
		chosen = chosen(title = "glamour standup figure",
			subject = /datum/material/glamour,
			build_time = 10 SECONDS,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/glamour__glamour_bandage
CAPABILITIES(/transformation/stack/glamour__glamour_bandage)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/medical/crude_pack, 1)),
		chosen = chosen(title = "glamour bandage",
			subject = /datum/material/glamour,
			build_time = 2 SECONDS,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/glamour__bedsheet
CAPABILITIES(/transformation/stack/glamour__bedsheet)
	configure(transformation(takes = list(stack_term(STACK_SELF, 10)), makes = list(item_term(/obj/item/bedsheet, 1)),
		chosen = chosen(title = "bedsheet",
			subject = /datum/material/glamour,
			build_time = 30 SECONDS,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/glamour__uniform
CAPABILITIES(/transformation/stack/glamour__uniform)
	configure(transformation(takes = list(stack_term(STACK_SELF, 8)), makes = list(item_term(/obj/item/clothing/under/color/white, 1)),
		chosen = chosen(title = "uniform",
			subject = /datum/material/glamour,
			build_time = 15 SECONDS,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/glamour__foot_wraps
CAPABILITIES(/transformation/stack/glamour__foot_wraps)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/item/clothing/shoes/footwraps, 1)),
		chosen = chosen(title = "foot wraps",
			subject = /datum/material/glamour,
			build_time = 5 SECONDS,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/glamour__gloves
CAPABILITIES(/transformation/stack/glamour__gloves)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/item/clothing/gloves/white, 1)),
		chosen = chosen(title = "gloves",
			subject = /datum/material/glamour,
			build_time = 5 SECONDS,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/glamour__wig
CAPABILITIES(/transformation/stack/glamour__wig)
	configure(transformation(takes = list(stack_term(STACK_SELF, 4)), makes = list(item_term(/obj/item/clothing/head/powdered_wig, 1)),
		chosen = chosen(title = "wig",
			subject = /datum/material/glamour,
			build_time = 10 SECONDS,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/glamour__philosopher_s_wig
CAPABILITIES(/transformation/stack/glamour__philosopher_s_wig)
	configure(transformation(takes = list(stack_term(STACK_SELF, 50)), makes = list(item_term(/obj/item/clothing/head/philosopher_wig, 1)),
		chosen = chosen(title = "philosopher's wig",
			subject = /datum/material/glamour,
			build_time = 2 MINUTES,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/glamour__taqiyah
CAPABILITIES(/transformation/stack/glamour__taqiyah)
	configure(transformation(takes = list(stack_term(STACK_SELF, 3)), makes = list(item_term(/obj/item/clothing/head/taqiyah, 1)),
		chosen = chosen(title = "taqiyah",
			subject = /datum/material/glamour,
			build_time = 6 SECONDS,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/glamour__turban
CAPABILITIES(/transformation/stack/glamour__turban)
	configure(transformation(takes = list(stack_term(STACK_SELF, 3)), makes = list(item_term(/obj/item/clothing/head/turban, 1)),
		chosen = chosen(title = "turban",
			subject = /datum/material/glamour,
			build_time = 6 SECONDS,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/glamour__hijab
CAPABILITIES(/transformation/stack/glamour__hijab)
	configure(transformation(takes = list(stack_term(STACK_SELF, 3)), makes = list(item_term(/obj/item/clothing/head/hijab, 1)),
		chosen = chosen(title = "hijab",
			subject = /datum/material/glamour,
			build_time = 6 SECONDS,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/glamour__kippa
CAPABILITIES(/transformation/stack/glamour__kippa)
	configure(transformation(takes = list(stack_term(STACK_SELF, 3)), makes = list(item_term(/obj/item/clothing/head/kippa, 1)),
		chosen = chosen(title = "kippa",
			subject = /datum/material/glamour,
			build_time = 6 SECONDS,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/glamour__scarf
CAPABILITIES(/transformation/stack/glamour__scarf)
	configure(transformation(takes = list(stack_term(STACK_SELF, 4)), makes = list(item_term(/obj/item/clothing/accessory/scarf/white, 1)),
		chosen = chosen(title = "scarf",
			subject = /datum/material/glamour,
			build_time = 5 SECONDS,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/glamour__baggy_pants
CAPABILITIES(/transformation/stack/glamour__baggy_pants)
	configure(transformation(takes = list(stack_term(STACK_SELF, 8)), makes = list(item_term(/obj/item/clothing/under/pants/baggy/white, 1)),
		chosen = chosen(title = "baggy pants",
			subject = /datum/material/glamour,
			build_time = 10 SECONDS,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/glamour__belt_pouch
CAPABILITIES(/transformation/stack/glamour__belt_pouch)
	configure(transformation(takes = list(stack_term(STACK_SELF, 25)), makes = list(item_term(/obj/item/storage/belt/fannypack/white, 1)),
		chosen = chosen(title = "belt pouch",
			subject = /datum/material/glamour,
			build_time = 1 MINUTE,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/glamour__glamour_net
CAPABILITIES(/transformation/stack/glamour__glamour_net)
	configure(transformation(takes = list(stack_term(STACK_SELF, 10)), makes = list(item_term(/obj/item/material/fishing_net, 1)),
		chosen = chosen(title = "glamour net",
			subject = /datum/material/glamour,
			build_time = 5 SECONDS,
			material = STACK_MATERIAL_SELF,
			pass_color = TRUE)))

/transformation/stack/glamour__glamour_ring
CAPABILITIES(/transformation/stack/glamour__glamour_ring)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/clothing/accessory/ring/material, 1)),
		chosen = chosen(title = "glamour ring",
			subject = /datum/material/glamour,
			on_floor = 1,
			material = STACK_MATERIAL_SELF,
			pass_color = TRUE)))

/transformation/stack/glamour__glamour_bracelet
CAPABILITIES(/transformation/stack/glamour__glamour_bracelet)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/clothing/accessory/bracelet/material, 1)),
		chosen = chosen(title = "glamour bracelet",
			subject = /datum/material/glamour,
			on_floor = 1,
			material = STACK_MATERIAL_SELF,
			pass_color = TRUE)))

/transformation/stack/glamour__glamour_armor_plate
CAPABILITIES(/transformation/stack/glamour__glamour_armor_plate)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/material/armor_plating, 1)),
		chosen = chosen(title = "glamour armor plate",
			subject = /datum/material/glamour,
			build_time = 20,
			on_floor = 1,
			material = STACK_MATERIAL_SELF,
			pass_color = TRUE)))

/transformation/stack/glamour__whip
CAPABILITIES(/transformation/stack/glamour__whip)
	configure(transformation(takes = list(stack_term(STACK_SELF, 5)), makes = list(item_term(/obj/item/material/whip, 1)),
		chosen = chosen(title = "whip",
			subject = /datum/material/glamour,
			build_time = 15 SECONDS,
			material = STACK_MATERIAL_SELF,
			pass_color = TRUE)))

/transformation/stack/glamour__transparent_glamour
CAPABILITIES(/transformation/stack/glamour__transparent_glamour)
	configure(transformation(takes = list(stack_term(STACK_SELF, 25)), makes = list(item_term(/obj/item/potion_material/glamour_transparent, 1)),
		chosen = chosen(title = "Transparent Glamour",
			subject = /datum/material/glamour,
			build_time = 15 SECONDS,
			material = STACK_MATERIAL_SELF,
			pass_color = FALSE)))

/transformation/stack/glamour__shrinking_glamour
CAPABILITIES(/transformation/stack/glamour__shrinking_glamour)
	configure(transformation(takes = list(stack_term(STACK_SELF, 10)), makes = list(item_term(/obj/item/potion_material/glamour_shrinking, 1)),
		chosen = chosen(title = "Shrinking Glamour",
			subject = /datum/material/glamour,
			build_time = 15 SECONDS,
			material = STACK_MATERIAL_SELF,
			pass_color = FALSE)))

/transformation/stack/glamour__twinkling_glamour
CAPABILITIES(/transformation/stack/glamour__twinkling_glamour)
	configure(transformation(takes = list(stack_term(STACK_SELF, 15)), makes = list(item_term(/obj/item/potion_material/glamour_twinkling, 1)),
		chosen = chosen(title = "Twinkling Glamour",
			subject = /datum/material/glamour,
			build_time = 15 SECONDS,
			material = STACK_MATERIAL_SELF,
			pass_color = FALSE)))

/transformation/stack/glamour__glamour_shard
CAPABILITIES(/transformation/stack/glamour__glamour_shard)
	configure(transformation(takes = list(stack_term(STACK_SELF, 15)), makes = list(item_term(/obj/item/potion_material/glamour_shard, 1)),
		chosen = chosen(title = "Glamour Shard",
			subject = /datum/material/glamour,
			build_time = 20 SECONDS,
			material = STACK_MATERIAL_SELF,
			pass_color = FALSE)))

/transformation/stack/glamour__glamour_cell
CAPABILITIES(/transformation/stack/glamour__glamour_cell)
	configure(transformation(takes = list(stack_term(STACK_SELF, 50)), makes = list(item_term(/obj/item/capture_crystal/glamour, 1)),
		chosen = chosen(title = "Glamour Cell",
			subject = /datum/material/glamour,
			build_time = 15 SECONDS,
			material = STACK_MATERIAL_SELF,
			pass_color = FALSE)))

/transformation/stack/glamour__speaking_glamour
CAPABILITIES(/transformation/stack/glamour__speaking_glamour)
	configure(transformation(takes = list(stack_term(STACK_SELF, 50)), makes = list(item_term(/obj/item/universal_translator/glamour, 1)),
		chosen = chosen(title = "Speaking Glamour",
			subject = /datum/material/glamour,
			build_time = 15 SECONDS,
			material = STACK_MATERIAL_SELF,
			pass_color = FALSE)))

/transformation/stack/glamour__glamour_bubble
CAPABILITIES(/transformation/stack/glamour__glamour_bubble)
	configure(transformation(takes = list(stack_term(STACK_SELF, 20)), makes = list(item_term(/obj/item/clothing/mask/gas/glamour, 1)),
		chosen = chosen(title = "Glamour Bubble",
			subject = /datum/material/glamour,
			build_time = 15 SECONDS,
			material = STACK_MATERIAL_SELF,
			pass_color = FALSE)))

/transformation/stack/glamour__pocket_of_glamour
CAPABILITIES(/transformation/stack/glamour__pocket_of_glamour)
	configure(transformation(takes = list(stack_term(STACK_SELF, 5)), makes = list(item_term(/obj/item/clothing/under/permit/glamour, 1)),
		chosen = chosen(title = "Pocket of Glamour",
			subject = /datum/material/glamour,
			build_time = 15 SECONDS,
			material = STACK_MATERIAL_SELF,
			pass_color = FALSE)))

/transformation/stack/glamour__glamour_bow
CAPABILITIES(/transformation/stack/glamour__glamour_bow)
	configure(transformation(takes = list(stack_term(STACK_SELF, 15)), makes = list(item_term(/obj/item/gun/launcher/crossbow/bow/glamour, 1)),
		chosen = chosen(title = "glamour bow",
			subject = /datum/material/glamour,
			build_time = 15 SECONDS,
			material = STACK_MATERIAL_SELF,
			pass_color = FALSE)))

/transformation/stack/glamour__glamour_arrow
CAPABILITIES(/transformation/stack/glamour__glamour_arrow)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/arrow/standard/glamour, 1)),
		chosen = chosen(title = "glamour arrow",
			subject = /datum/material/glamour,
			build_time = 15 SECONDS,
			material = STACK_MATERIAL_SELF,
			pass_color = FALSE)))

/datum/material/weathered_agate
	name = MAT_EAGATE
	display_name = "energized agate"
	use_name = "energized agate"
	icon_colour = "#FF3300"
	stack_type = /obj/item/stack/material/weathered_agate
	ignition_point = 2400
	melting_point = 2200
	protectiveness = 70
	opacity = 0.3
	reflectivity = 0.5
	explosion_resistance = 13
	negation = 12
	spatial_instability = 18
	radiation_resistance = 18
	supply_conversion_value = 12
	can_sharpen = TRUE

	hardness = 70
	density = 5

	shard_type = SHARD_SHARD
	tableslam_noise = 'sound/effects/Glasshit.ogg'
	sheet_singular_name = "gem"
	sheet_plural_name = "gems"
	icon_base = "resin"
	table_icon_base = "resin"


/datum/material/valhollide //buffed protection and reflectivity
	protectiveness = 70
	reflectivity = 0.75


/datum/material/morphium //buffed protection
	protectiveness = 65
