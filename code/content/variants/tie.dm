// Variants of /obj/item/clothing/accessory/tie: one row per type that only set data (doc/rewrite/variant_census.md). The old path, parent + "/" + key, still resolves
// for maps and saves (variant_alias_of()). Started by tools/ci/variant_collapse.py.

GLOBAL_LIST_INIT(dq_variants_tie, list(
	"black" = list("name" = "black tie", "icon_state" = "blacktie"),
	"blue_clip" = list("name" = "blue tie with a clip", "icon_state" = "bluecliptie"),
	"blue_long" = list("name" = "blue long tie", "icon_state" = "bluelongtie"),
	"darkgreen" = list("name" = "dark green tie", "icon_state" = "dgreentie"),
	"horrible" = list("name" = "horrible tie", "desc" = "A neosilk clip-on tie. This one is disgusting.", "icon_state" = "horribletie"),
	"navy" = list("name" = "navy tie", "icon_state" = "navytie"),
	"red" = list("name" = "red tie", "icon_state" = "redtie"),
	"red_clip" = list("name" = "red tie with a clip", "icon_state" = "redcliptie"),
	"red_long" = list("name" = "red long tie", "icon_state" = "redlongtie"),
	"white" = list("name" = "white tie", "icon_state" = "whitetie"),
	"yellow" = list("name" = "yellow tie", "icon_state" = "yellowtie"),
))

/// The variant rows (variants(), code/engine/lifeforms/variants.dm).
/obj/item/clothing/accessory/tie/proc/variant_table()
	return GLOB.dq_variants_tie

CAPABILITIES(/obj/item/clothing/accessory/tie)
	variants(nameof(variant), PROC_REF(variant_table))
