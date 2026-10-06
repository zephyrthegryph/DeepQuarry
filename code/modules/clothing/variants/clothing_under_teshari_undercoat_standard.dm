// Variant registry (see code/datums/variants/README.md).
// Collapses 23 subtypes of /obj/item/clothing/under/teshari/undercoat/standard
// into the parent with a `variant` arg (the var lives on /obj/item; see
// gear_tweak_variant.dm). Each variant overrides only name/icon_state.

GLOBAL_LIST_INIT(dq_teshari_undercoat_variants, list(
	"black_orange" = list("name" = "black and orange undercoat", "icon_state" = "tesh_uniform_bo"),
	"black_grey" = list("name" = "black and grey undercoat", "icon_state" = "tesh_uniform_bg"),
	"black_white" = list("name" = "black and white undercoat", "icon_state" = "tesh_uniform_bw"),
	"black_red" = list("name" = "black and red undercoat", "icon_state" = "tesh_uniform_br"),
	"black" = list("name" = "black undercoat", "icon_state" = "tesh_uniform_bn"),
	"black_yellow" = list("name" = "black and yellow undercoat", "icon_state" = "tesh_uniform_by"),
	"black_green" = list("name" = "black and green undercoat", "icon_state" = "tesh_uniform_bgr"),
	"black_blue" = list("name" = "black and blue undercoat", "icon_state" = "tesh_uniform_bbl"),
	"black_purple" = list("name" = "black and purple undercoat", "icon_state" = "tesh_uniform_bp"),
	"black_pink" = list("name" = "black and pink undercoat", "icon_state" = "tesh_uniform_bpi"),
	"black_brown" = list("name" = "black and brown undercoat", "icon_state" = "tesh_uniform_bbr"),
	"orange_grey" = list("name" = "orange and grey undercoat", "icon_state" = "tesh_uniform_og"),
	"rainbow" = list("name" = "rainbow undercoat", "icon_state" = "tesh_uniform_rainbow"),
	"lightgrey_grey" = list("name" = "light grey and grey undercoat", "icon_state" = "tesh_uniform_lgg"),
	"white_grey" = list("name" = "white and grey undercoat", "icon_state" = "tesh_uniform_wg"),
	"red_grey" = list("name" = "red and grey undercoat", "icon_state" = "tesh_uniform_rg"),
	"orange" = list("name" = "orange undercoat", "icon_state" = "tesh_uniform_on"),
	"yellow_grey" = list("name" = "yellow and grey undercoat", "icon_state" = "tesh_uniform_yg"),
	"green_grey" = list("name" = "green and grey undercoat", "icon_state" = "tesh_uniform_gg"),
	"blue_grey" = list("name" = "blue and grey undercoat", "icon_state" = "tesh_uniform_blug"),
	"purple_grey" = list("name" = "purple and grey undercoat", "icon_state" = "tesh_uniform_pg"),
	"pink_grey" = list("name" = "pink and grey undercoat", "icon_state" = "tesh_uniform_pig"),
	"brown_grey" = list("name" = "brown and grey undercoat", "icon_state" = "tesh_uniform_brg"),
))

CAPABILITIES(/obj/item/clothing/under/teshari/undercoat/standard)
	variants(nameof(variant), PROC_REF(variant_table))

/// The variant rows (variants(), code/engine/lifeforms/variants.dm).
/obj/item/clothing/under/teshari/undercoat/standard/proc/variant_table()
	return GLOB.dq_teshari_undercoat_variants
