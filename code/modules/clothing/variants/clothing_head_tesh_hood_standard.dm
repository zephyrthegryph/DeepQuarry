// Auto-generated. 25 variants of /obj/item/clothing/head/tesh_hood/standard.

GLOBAL_LIST_INIT(dq_variants_head_tesh_hood_standard, list(
	"black_orange" = list("name" = "black and orange cloak hood", "icon_state" = "tesh_hood_bo"),
	"black_grey" = list("name" = "black and grey cloak hood", "icon_state" = "tesh_hood_bg"),
	"black_midgrey" = list("name" = "black and medium grey cloak hood", "icon_state" = "tesh_hood_bmg"),
	"black_lightgrey" = list("name" = "black and light grey cloak hood", "icon_state" = "tesh_hood_blg"),
	"black_white" = list("name" = "black and white cloak hood", "icon_state" = "tesh_hood_bw"),
	"black_red" = list("name" = "black and red cloak hood", "icon_state" = "tesh_hood_br"),
	"black" = list("name" = "black cloak hood", "icon_state" = "tesh_hood_bn"),
	"black_yellow" = list("name" = "black and yellow cloak hood", "icon_state" = "tesh_hood_by"),
	"black_green" = list("name" = "black and green cloak hood", "icon_state" = "tesh_hood_bgr"),
	"black_blue" = list("name" = "black and blue cloak hood", "icon_state" = "tesh_hood_bbl"),
	"black_purple" = list("name" = "black and purple cloak hood", "icon_state" = "tesh_hood_bp"),
	"black_pink" = list("name" = "black and pink cloak hood", "icon_state" = "tesh_hood_bpi"),
	"black_brown" = list("name" = "black and brown cloak hood", "icon_state" = "tesh_hood_bbr"),
	"orange_grey" = list("name" = "orange and grey cloak hood", "icon_state" = "tesh_hood_og"),
	"rainbow" = list("name" = "rainbow cloak hood", "icon_state" = "tesh_hood_rainbow"),
	"lightgrey_grey" = list("name" = "light grey and grey cloak hood", "icon_state" = "tesh_hood_lgg"),
	"white_grey" = list("name" = "white and grey cloak hood", "icon_state" = "tesh_hood_wg"),
	"red_grey" = list("name" = "red and grey cloak hood", "icon_state" = "tesh_hood_rg"),
	"orange" = list("name" = "orange cloak hood", "icon_state" = "tesh_hood_on"),
	"yellow_grey" = list("name" = "yellow and grey cloak hood", "icon_state" = "tesh_hood_yg"),
	"green_grey" = list("name" = "green and grey cloak hood", "icon_state" = "tesh_hood_gg"),
	"blue_grey" = list("name" = "blue and grey cloak hood", "icon_state" = "tesh_hood_blug"),
	"purple_grey" = list("name" = "purple and grey cloak hood", "icon_state" = "tesh_hood_pg"),
	"pink_grey" = list("name" = "pink and grey cloak hood", "icon_state" = "tesh_hood_pig"),
	"brown_grey" = list("name" = "brown and grey cloak hood", "icon_state" = "tesh_hood_brg"),
))

CAPABILITIES(/obj/item/clothing/head/tesh_hood/standard)
	variants(nameof(variant), PROC_REF(variant_table))

/// The variant rows (variants(), code/engine/lifeforms/variants.dm).
/obj/item/clothing/head/tesh_hood/standard/proc/variant_table()
	return GLOB.dq_variants_head_tesh_hood_standard
