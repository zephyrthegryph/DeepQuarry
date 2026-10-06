// Auto-generated. 9 variants of /obj/item/clothing/under/teshari/undercoat/standard/worksuit.

GLOBAL_LIST_INIT(dq_variants_under_teshari_undercoat_standard_worksuit, list(
	"blackpurple" = list("name" = "small black and purple worksuit", "icon_state" = "teshari_black_purple_worksuit"),
	"blackorange" = list("name" = "small black and orange worksuit", "icon_state" = "teshari_black_orange_worksuit"),
	"blackblue" = list("name" = "small black and blue worksuit", "icon_state" = "teshari_black_blue_worksuit"),
	"blackgreen" = list("name" = "small black and greeen worksuit", "icon_state" = "teshari_black_green_worksuit"),
	"whitered" = list("name" = "small white and red worksuit", "icon_state" = "teshari_white_red_worksuit"),
	"whitepurple" = list("name" = "small white and purple worksuit", "icon_state" = "teshari_white_purple_worksuit"),
	"whiteorange" = list("name" = "small white and orange worksuit", "icon_state" = "teshari_white_orange_worksuit"),
	"whiteblue" = list("name" = "small white and blue worksuit", "icon_state" = "teshari_white_blue_worksuit"),
	"whitegreen" = list("name" = "small white and green worksuit", "icon_state" = "teshari_white_green_worksuit"),
))

CAPABILITIES(/obj/item/clothing/under/teshari/undercoat/standard/worksuit)
	variants(nameof(variant), PROC_REF(own_variant_table)) // its own rows replace the parent family's

/// The variant rows (variants(), code/engine/lifeforms/variants.dm).
/obj/item/clothing/under/teshari/undercoat/standard/worksuit/proc/own_variant_table()
	return GLOB.dq_variants_under_teshari_undercoat_standard_worksuit
