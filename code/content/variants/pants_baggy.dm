// Variants of /obj/item/clothing/under/pants/baggy: one row per type that only set data (doc/rewrite/variant_census.md). The old path, parent + "/" + key, still resolves
// for maps and saves (variant_alias_of()). Started by tools/ci/variant_collapse.py.

GLOBAL_LIST_INIT(dq_variants_pants_baggy, list(
	"black" = list("name" = "baggy black pants", "desc" = "These pants are dark, like your soul.", "icon_state" = "baggy_blackpants"),
	"blackjeans" = list("name" = "baggy black jeans", "desc" = "Only for those who can pull it off.", "icon_state" = "baggy_jeansblack"),
	"camo" = list("name" = "baggy camo pants", "desc" = "A pair of woodland camouflage pants. Probably not the best choice for a space station.", "icon_state" = "baggy_camopants"),
	"classicjeans" = list("name" = "baggy classic jeans", "desc" = "You feel cooler already.", "icon_state" = "baggy_jeansclassic"),
	"greyjeans" = list("name" = "baggy grey jeans", "desc" = "Only for those who can pull it off.", "icon_state" = "baggy_jeansgrey"),
	"khaki" = list("name" = "baggy khaki pants", "desc" = "A pair of dust beige khaki pants.", "icon_state" = "baggy_khaki"),
	"mustangjeans" = list("name" = "maggy must hang jeans", "desc" = "Made in the finest space jeans factory this side of Alpha Centauri.", "icon_state" = "baggy_jeansmustang"),
	"red" = list("name" = "baggy red pants", "desc" = "Bright red pants. Overflowing with personality.", "icon_state" = "baggy_redpants"),
	"tan" = list("name" = "baggy tan pants", "desc" = "Some tan pants. You look like a white collar worker with these on.", "icon_state" = "baggy_tanpants"),
	"track" = list("name" = "baggy track pants", "desc" = "A pair of track pants, for the athletic.", "icon_state" = "baggy_trackpants"),
	"youngfolksjeans" = list("name" = "baggy young folks jeans", "desc" = "For those tired of boring old jeans. Relive the passion of your youth!", "icon_state" = "baggy_jeansyoungfolks"),
))

/// The variant rows (variants(), code/engine/lifeforms/variants.dm).
/obj/item/clothing/under/pants/baggy/proc/own_variant_table()
	return GLOB.dq_variants_pants_baggy

CAPABILITIES(/obj/item/clothing/under/pants/baggy)
	variants(nameof(variant), PROC_REF(own_variant_table)) // its own rows replace the parent family's
