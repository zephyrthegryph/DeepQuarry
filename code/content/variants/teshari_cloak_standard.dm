// Variants of /obj/item/clothing/suit/storage/teshari/cloak/standard: one row per type that only set data (doc/rewrite/variant_census.md). The old path, parent + "/" + key, still resolves
// for maps and saves (variant_alias_of()). Started by tools/ci/variant_collapse.py.

GLOBAL_LIST_INIT(dq_variants_teshari_cloak_standard, list(
	"black_blue" = list("name" = "black and blue cloak", "icon_state" = "tesh_cloak_bbl"),
	"black_brown" = list("name" = "black and brown cloak", "icon_state" = "tesh_cloak_bbr"),
	"black_glow" = list("name" = "black and glowing cloak", "icon_state" = "tesh_cloak_bglowing"),
	"black_green" = list("name" = "black and green cloak", "icon_state" = "tesh_cloak_bgr"),
	"black_grey" = list("name" = "black and grey cloak", "icon_state" = "tesh_cloak_bg"),
	"black_orange" = list("name" = "black and orange cloak", "icon_state" = "tesh_cloak_bo"),
	"black_pink" = list("name" = "black and pink cloak", "icon_state" = "tesh_cloak_bpi"),
	"black_purple" = list("name" = "black and purple cloak", "icon_state" = "tesh_cloak_bp"),
	"black_red" = list("name" = "black and red cloak", "icon_state" = "tesh_cloak_br"),
	"black_white" = list("name" = "black and white cloak", "icon_state" = "tesh_cloak_bw"),
	"black_yellow" = list("name" = "black and yellow cloak", "icon_state" = "tesh_cloak_by"),
	"blue_grey" = list("name" = "blue and grey cloak", "icon_state" = "tesh_cloak_blug"),
	"brown_grey" = list("name" = "brown and grey cloak", "icon_state" = "tesh_cloak_brg"),
	"dark_retrowave" = list("name" = "dark aesthetic cloak", "icon_state" = "tesh_cloak_dretrowave"),
	"green_grey" = list("name" = "green and grey cloak", "icon_state" = "tesh_cloak_gg"),
	"orange" = list("name" = "orange cloak", "icon_state" = "tesh_cloak_on"),
	"orange_grey" = list("name" = "orange and grey cloak", "icon_state" = "tesh_cloak_og"),
	"pink_grey" = list("name" = "pink and grey cloak", "icon_state" = "tesh_cloak_pig"),
	"purple_grey" = list("name" = "purple and grey cloak", "icon_state" = "tesh_cloak_pg"),
	"rainbow" = list("name" = "rainbow cloak", "icon_state" = "tesh_cloak_rainbow"),
	"red_grey" = list("name" = "red and grey cloak", "icon_state" = "tesh_cloak_rg"),
	"white_grey" = list("name" = "white and grey cloak", "icon_state" = "tesh_cloak_wg"),
	"yellow_grey" = list("name" = "yellow and grey cloak", "icon_state" = "tesh_cloak_yg"),
))

/// The variant rows (variants(), code/engine/lifeforms/variants.dm).
/obj/item/clothing/suit/storage/teshari/cloak/standard/proc/variant_table()
	return GLOB.dq_variants_teshari_cloak_standard

CAPABILITIES(/obj/item/clothing/suit/storage/teshari/cloak/standard)
	variants(nameof(variant), PROC_REF(variant_table))
