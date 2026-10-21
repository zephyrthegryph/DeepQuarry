//R-UST port
/datum/material/supermatter
	name = MAT_SUPERMATTER
	icon_colour = "#FFFF00"
	stack_type = /obj/item/stack/material/supermatter
	shard_type = SHARD_SHARD
	ignition_point = PLASMA_MINIMUM_BURN_TEMPERATURE
	icon_base = "stone"
	shard_type = SHARD_SHARD
	hardness = 30
	door_icon_base = "stone"
	sheet_singular_name = "crystal"
	sheet_plural_name = "crystals"
	is_fusion_fuel = 1
	flags = MATERIAL_UNMELTABLE
	supply_conversion_value = 30

/datum/material/supermatter/New()
	. = ..()
	radioactivity = 20
	luminescence = 3

/transformation/stack/supermatter__supermatter_shard
CAPABILITIES(/transformation/stack/supermatter__supermatter_shard)
	configure(transformation(takes = list(stack_term(STACK_SELF, 30)), makes = list(item_term(/obj/machinery/power/supermatter/shard, 1)),
		chosen = chosen(title = "supermatter shard",
			subject = /datum/material/supermatter,
			build_time = 600,
			one_per_turf = 1,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF,
			replaces = TRUE)))

