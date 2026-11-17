// Variants of /obj/item/clothing/under/color/fjumpsuit: one row per type that only set data (doc/rewrite/variant_census.md). The old path, parent + "/" + key, still resolves
// for maps and saves (variant_alias_of()). Started by tools/ci/variant_collapse.py.

GLOBAL_LIST_INIT(dq_variants_under_color_fjumpsuit, list(
	"aquaf" = list("name" = "aqua feminine jumpsuit", "icon_state" = "aqua", "worn_state" = "aquaf"),
	"bluef" = list("name" = "blue feminine jumpsuit", "icon_state" = "blue", "worn_state" = "bluef"),
	"brownf" = list("name" = "brown feminine jumpsuit", "icon_state" = "brown", "worn_state" = "brownf"),
	"darkbluef" = list("name" = "dark blue feminine jumpsuit", "icon_state" = "darkblue", "worn_state" = "darkbluef"),
	"darkredf" = list("name" = "dark red feminine jumpsuit", "icon_state" = "darkred", "worn_state" = "darkredf"),
	"greenf" = list("name" = "green feminine jumpsuit", "icon_state" = "green", "worn_state" = "greenf"),
	"lightbluef" = list("name" = "light blue feminine jumpsuit", "icon_state" = "lightblue", "worn_state" = "lightbluef"),
	"lightbrownf" = list("name" = "light brown feminine jumpsuit", "icon_state" = "lightbrown", "worn_state" = "lightbrownf"),
	"lightgreenf" = list("name" = "light green feminine jumpsuit", "icon_state" = "lightgreen", "worn_state" = "lightgreenf"),
	"lightpurplef" = list("name" = "light purple feminine jumpsuit", "icon_state" = "lightpurple", "worn_state" = "lightpurplef"),
	"lightredf" = list("name" = "light red feminine jumpsuit", "icon_state" = "lightred", "worn_state" = "lightredf"),
	"maroonf" = list("name" = "maroon feminine jumpsuit", "icon_state" = "maroon", "worn_state" = "maroonf"),
	"pinkf" = list("name" = "pink feminine jumpsuit", "icon_state" = "pink", "worn_state" = "pinkf"),
	"purplef" = list("name" = "purple feminine jumpsuit", "icon_state" = "purple", "worn_state" = "purplef"),
	"redf" = list("name" = "red feminine jumpsuit", "icon_state" = "red", "worn_state" = "redf"),
	"yellowf" = list("name" = "yellow feminine jumpsuit", "icon_state" = "yellow", "worn_state" = "yellowf"),
	"yellowgreenf" = list("name" = "yellow-green feminine jumpsuit", "icon_state" = "yellowgreen", "worn_state" = "yellowgreenf"),
))

/// The variant rows (variants(), code/engine/lifeforms/variants.dm).
/obj/item/clothing/under/color/fjumpsuit/proc/own_variant_table()
	return GLOB.dq_variants_under_color_fjumpsuit

CAPABILITIES(/obj/item/clothing/under/color/fjumpsuit)
	variants(nameof(variant), PROC_REF(own_variant_table)) // its own rows replace the parent family's
