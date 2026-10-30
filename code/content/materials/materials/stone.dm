/datum/material/stone
	name = MAT_SANDSTONE
	stack_type = /obj/item/stack/material/sandstone
	icon_base = "stone"
	table_icon_base = "stone"
	icon_reinf = "reinf_stone"
	icon_colour = "#D9C179"
	shard_type = SHARD_STONE_PIECE
	density = 22
	hardness = 55
	protectiveness = 5 // 20%
	conductive = 0
	conductivity = 5
	door_icon_base = "stone"
	sheet_singular_name = "brick"
	sheet_plural_name = "bricks"
	supply_conversion_value = 0.5

/transformation/stack/stone__planting_bed
CAPABILITIES(/transformation/stack/stone__planting_bed)
	configure(transformation(takes = list(stack_term(STACK_SELF, 3)), makes = list(item_term(/obj/machinery/portable_atmospherics/hydroponics/soil, 1)),
		chosen = chosen(title = "planting bed",
			subject = /datum/material/stone,
			build_time = 10,
			one_per_turf = 1,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF)))

/datum/material/stone/marble
	name = MAT_MARBLE
	icon_colour = "#AAAAAA"
	density = 26
	hardness = 30 // Please.
	integrity = 201 //hack to stop kitchen benches being flippable, todo: refactor into weight system
	stack_type = /obj/item/stack/material/marble
	supply_conversion_value = 2

/transformation/stack/stone_marble__light_marble_floor_tile
CAPABILITIES(/transformation/stack/stone_marble__light_marble_floor_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/wmarble, 4)),
		chosen = chosen(title = "light marble floor tile",
			subject = /datum/material/stone/marble,
			max_made = 20,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/stone_marble__dark_marble_floor_tile
CAPABILITIES(/transformation/stack/stone_marble__dark_marble_floor_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/bmarble, 4)),
		chosen = chosen(title = "dark marble floor tile",
			subject = /datum/material/stone/marble,
			max_made = 20,
			recycle = STACK_MATERIAL_SELF)))

/datum/material/stone/flint
	name = MAT_FLINT
	icon_colour = "#9e9c99"
	density = 20
	hardness = 30
	integrity = 100
	stack_type = /obj/item/stack/material/flint
	supply_conversion_value = 2
	sheet_singular_name = "piece"
	sheet_plural_name = "pieces"
	supply_conversion_value = 0.1

/transformation/stack/stone_flint__clears
CAPABILITIES(/transformation/stack/stone_flint__clears)
	configure(transformation(chosen = chosen(subject = /datum/material/stone/flint, replaces = TRUE)))

/datum/material/stone/concrete
	name = MAT_CONCRETE
	stack_type = /obj/item/stack/material/concrete
	icon_base = "brick"
	icon_colour = COLOR_GRAY
	integrity = 150
	melting_point = 1550
	protectiveness = 10
	density = 27
	hardness = 60
	var/image/texture
	supply_conversion_value = 0.1

/transformation/stack/stone_concrete__concrete_flooring
CAPABILITIES(/transformation/stack/stone_concrete__concrete_flooring)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/floor/concrete, 4)),
		chosen = chosen(title = "Concrete Flooring",
			subject = /datum/material/stone/concrete,
			max_made = 20,
			recycle = STACK_MATERIAL_SELF,
			group = "Concrete Pathing")))

/transformation/stack/stone_concrete__concrete_sidewalk
CAPABILITIES(/transformation/stack/stone_concrete__concrete_sidewalk)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/floor/sidewalk, 4)),
		chosen = chosen(title = "Concrete Sidewalk",
			subject = /datum/material/stone/concrete,
			max_made = 20,
			recycle = STACK_MATERIAL_SELF,
			group = "Concrete Pathing")))

/transformation/stack/stone_concrete__concrete_sidewalk_side
CAPABILITIES(/transformation/stack/stone_concrete__concrete_sidewalk_side)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/floor/sidewalk/side, 4)),
		chosen = chosen(title = "Concrete Sidewalk (Side)",
			subject = /datum/material/stone/concrete,
			max_made = 20,
			recycle = STACK_MATERIAL_SELF,
			group = "Concrete Pathing")))

/transformation/stack/stone_concrete__concrete_sidewalk_slab
CAPABILITIES(/transformation/stack/stone_concrete__concrete_sidewalk_slab)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/floor/sidewalk/slab, 4)),
		chosen = chosen(title = "Concrete Sidewalk (Slab)",
			subject = /datum/material/stone/concrete,
			max_made = 20,
			recycle = STACK_MATERIAL_SELF,
			group = "Concrete Pathing")))

/datum/material/stone/concrete/New()
	. = ..()
	texture = image('icons/turf/wall_texture.dmi', "concrete")
	texture.blend_mode = BLEND_MULTIPLY

/datum/material/stone/concrete/get_wall_texture()
	return texture

