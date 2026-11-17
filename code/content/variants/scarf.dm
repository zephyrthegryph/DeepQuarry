// Variants of /obj/item/clothing/accessory/scarf: one row per type that only set data (doc/rewrite/variant_census.md). The old path, parent + "/" + key, still resolves
// for maps and saves (variant_alias_of()). Started by tools/ci/variant_collapse.py.

GLOBAL_LIST_INIT(dq_variants_scarf, list(
	"black" = list("name" = "black scarf", "icon_state" = "blackscarf"),
	"christmas" = list("name" = "christmas scarf", "icon_state" = "christmasscarf"),
	"darkblue" = list("name" = "dark blue scarf", "icon_state" = "darkbluescarf"),
	"lightblue" = list("name" = "light blue scarf", "icon_state" = "lightbluescarf"),
	"orange" = list("name" = "orange scarf", "icon_state" = "orangescarf"),
	"purple" = list("name" = "purple scarf", "icon_state" = "purplescarf"),
	"red" = list("name" = "red scarf", "icon_state" = "redscarf"),
	"stripedblue" = list("name" = "striped blue scarf", "icon_state" = "stripedbluescarf"),
	"stripedgreen" = list("name" = "striped green scarf", "icon_state" = "stripedgreenscarf"),
	"stripedred" = list("name" = "striped red scarf", "icon_state" = "stripedredscarf"),
	"yellow" = list("name" = "yellow scarf", "icon_state" = "yellowscarf"),
	"zebra" = list("name" = "zebra scarf", "icon_state" = "zebrascarf"),
))

/// The variant rows (variants(), code/engine/lifeforms/variants.dm).
/obj/item/clothing/accessory/scarf/proc/variant_table()
	return GLOB.dq_variants_scarf

CAPABILITIES(/obj/item/clothing/accessory/scarf)
	variants(nameof(variant), PROC_REF(variant_table))
