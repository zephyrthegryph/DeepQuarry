// Variants of /obj/item/clothing/under/skirt/colorable: one row per type that only set data (doc/rewrite/variant_census.md). The old path, parent + "/" + key, still resolves
// for maps and saves (variant_alias_of()). Started by tools/ci/variant_collapse.py.

GLOBAL_LIST_INIT(dq_variants_skirt_colorable, list(
	"high" = list("name" = "high skirt", "desc" = "A skirt that rests at the waist instead of the hips.", "icon_state" = "skirt_high", "item_state" = "skirt_high", "worn_state" = "skirt_high"),
	"jumper" = list("name" = "jumper skirt", "desc" = "A skirt that's held up by suspenders.", "icon_state" = "skirt_jumper", "item_state" = "skirt_jumper", "worn_state" = "skirt_jumper"),
	"jumperdress" = list("name" = "jumper dress", "desc" = "A dress held up by suspenders. Not quite a skirt anymore.", "icon_state" = "skirt_jumperdress", "item_state" = "skirt_jumperdress", "worn_state" = "skirt_jumperdress"),
	"long" = list("name" = "long skirt", "icon_state" = "skirt_long", "item_state" = "skirt_long", "worn_state" = "skirt_long"),
	"pencil" = list("name" = "pencil skirt", "desc" = "A short skirt that's almost as thin as a pencil. Almost.", "icon_state" = "skirt_pencil", "item_state" = "skirt_pencil", "worn_state" = "skirt_pencil"),
	"plaid" = list("name" = "plaid skirt", "desc" = "A skirt featuring a plaid pattern.", "icon_state" = "skirt_plaid", "item_state" = "skirt_plaid", "worn_state" = "skirt_plaid"),
	"puffy" = list("icon_state" = "skirt_puffy", "item_state" = "skirt_puffy", "worn_state" = "skirt_puffy"),
	"short" = list("name" = "short skirt", "desc" = "A far too short pleated skirt.", "icon_state" = "skirt_short", "item_state" = "skirt_short", "worn_state" = "skirt_short"),
	"short_split" = list("name" = "short skirt (split)", "desc" = "A far too short pleated skirt with an open split down one side.", "icon_state" = "skirt_short_split", "item_state" = "skirt_short_split", "worn_state" = "skirt_short_split"),
	"skater" = list("desc" = "A skirt with loose frills.", "icon_state" = "skirt_skater", "item_state" = "skirt_skater", "worn_state" = "skirt_skater"),
	"swept" = list("name" = "swept skirt", "desc" = "A skirt with an angled hem; shorter on one side, longer on the other, like a sweep.", "icon_state" = "skirt_swept", "item_state" = "skirt_swept", "worn_state" = "skirt_swept"),
	"tube" = list("desc" = "A long thin skirt that trails beyond the knees.", "icon_state" = "skirt_tube", "item_state" = "skirt_tube", "worn_state" = "skirt_tube"),
))

/// The variant rows (variants(), code/engine/lifeforms/variants.dm).
/obj/item/clothing/under/skirt/colorable/proc/own_variant_table()
	return GLOB.dq_variants_skirt_colorable

CAPABILITIES(/obj/item/clothing/under/skirt/colorable)
	variants(nameof(variant), PROC_REF(own_variant_table)) // its own rows replace the parent family's
