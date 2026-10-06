// Auto-generated. 11 variants of /obj/item/clothing/under/turtlebaggy.

GLOBAL_LIST_INIT(dq_variants_under_turtlebaggy, list(
	"cream_fem" = list("name" = "feminine cream baggy turtleneck", "icon_state" = "bb_turtle_fem"),
	"purple" = list("name" = "purple baggy turtleneck", "icon_state" = "bb_turtlepur"),
	"purple_fem" = list("name" = "feminine purple baggy turtleneck", "icon_state" = "bb_turtlepur_fem"),
	"red" = list("name" = "red baggy turtleneck", "icon_state" = "bb_turtlered"),
	"red_fem" = list("name" = "feminine red baggy turtleneck", "icon_state" = "bb_turtlered_fem"),
	"blue" = list("name" = "blue baggy turtleneck", "icon_state" = "bb_turtleblu"),
	"blue_fem" = list("name" = "feminine blue baggy turtleneck", "icon_state" = "bb_turtleblu_fem"),
	"green" = list("name" = "green baggy turtleneck", "icon_state" = "bb_turtlegrn"),
	"green_fem" = list("name" = "feminine green baggy turtleneck", "icon_state" = "bb_turtlegrn_fem"),
	"black" = list("name" = "black baggy turtleneck", "icon_state" = "bb_turtleblk"),
	"black_fem" = list("name" = "feminine black baggy turtleneck", "icon_state" = "bb_turtleblk_fem"),
))

CAPABILITIES(/obj/item/clothing/under/turtlebaggy)
	variants(nameof(variant), PROC_REF(variant_table))

/// The variant rows (variants(), code/engine/lifeforms/variants.dm).
/obj/item/clothing/under/turtlebaggy/proc/variant_table()
	return GLOB.dq_variants_under_turtlebaggy
