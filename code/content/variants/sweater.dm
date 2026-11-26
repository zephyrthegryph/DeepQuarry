// Variants of /obj/item/clothing/accessory/sweater: one row per type that only set data (doc/rewrite/variant_census.md). The old path, parent + "/" + key, still resolves
// for maps and saves (variant_alias_of()). Started by tools/ci/variant_collapse.py.

GLOBAL_LIST_INIT(dq_variants_sweater, list(
	"blackneck" = list("name" = "black turtleneck", "desc" = "A tight turtleneck, entirely black in coloration.", "icon_state" = "turtleneck_black"),
	"blue" = list("name" = "blue sweater", "desc" = "A warm knit sweater. This one's colored in a lighter blue.", "icon_state" = "sweater_blue"),
	"flowersweater" = list("name" = "flowery sweater", "desc" = "An oversized and flowery pink sweater.", "icon_state" = "flowersweater"),
	"heart" = list("name" = "heart sweater", "desc" = "A warm knit sweater. This one's colored in a lighter blue, and has a big pink heart right in the center!", "icon_state" = "sweater_blueheart"),
	"keyhole" = list("name" = "keyhole sweater", "desc" = "A lavender sweater with an open chest.", "icon_state" = "keyholesweater"),
	"mint" = list("name" = "mint sweater", "desc" = "A warm knit sweater. This one has a minty tint to it.", "icon_state" = "sweater_mint"),
	"nt" = list("name" = "dark blue sweater", "desc" = "A warm knit sweater. This one's a darker blue.", "icon_state" = "sweater_nt"),
	"pink" = list("name" = "pink sweater", "desc" = "A warm knit sweater. This one's pink in color.", "icon_state" = "sweater_pink"),
	"redneck" = list("name" = "red turtleneck", "desc" = "A comfortable turtleneck in a dark red.", "icon_state" = "turtleneck_red"),
	"uglyxmas" = list("name" = "ugly Christmas sweater", "desc" = "A gift that probably should've stayed in the back of the closet.", "icon_state" = "uglyxmas"),
	"winterneck" = list("name" = "Christmas turtleneck", "desc" = "A really cheesy holiday sweater, it actually kinda itches.", "icon_state" = "turtleneck_winterred"),
))

/// The variant rows (variants(), code/engine/lifeforms/variants.dm).
/obj/item/clothing/accessory/sweater/proc/variant_table()
	return GLOB.dq_variants_sweater
