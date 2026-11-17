// Variants of /obj/item/clothing/shoes: one row per type that only set data (doc/rewrite/variant_census.md). The old path, parent + "/" + key, still resolves
// for maps and saves (variant_alias_of()). Started by tools/ci/variant_collapse.py.

GLOBAL_LIST_INIT(dq_variants_shoes, list(
	"antediluvian" = list("name" = "antediluvian legwraps", "desc" = "A pair of wraps with gold inlay that cut off around the ankle.", "icon_state" = "antediluvian", "item_state" = "antediluvian"),
	"athletic" = list("name" = "athletic shoes", "desc" = "A pair of sleek athletic shoes. Made by and for the sporty types.", "icon_state" = "sportshoe", "addblends" = "sportshoe_a", "item_state_slots" = list(slot_r_hand_str = "sportheld", slot_l_hand_str = "sportheld")),
	"ballet" = list("name" = "pointe shoes", "desc" = "These shoes feature long lace straps and flattened off toes. Great for the most elegant of dances!", "icon_state" = "ballet", "item_state" = "ballet"),
	"blue" = list("name" = "blue shoes", "icon_state" = "blue"),
	"brown" = list("name" = "brown shoes", "desc" = "A pair of brown shoes.", "icon_state" = "brown"),
	"cyborg" = list("name" = "cyborg boots", "desc" = "Shoes for a cyborg costume", "icon_state" = "boots"),
	"flipflop" = list("name" = "flip flops", "desc" = "A pair of foam flip flops. For those not afraid to show a little ankle.", "icon_state" = "thongsandal", "addblends" = "thongsandal_a"),
	"green" = list("name" = "green shoes", "icon_state" = "green"),
	"griffin" = list("name" = "griffon boots", "desc" = "A pair of costume boots fashioned after bird talons.", "icon_state" = "griffinboots", "item_state" = "griffinboots"),
	"heels" = list("name" = "high heels", "desc" = "A pair of high-heeled shoes. Fancy!", "icon_state" = "heels", "addblends" = "heels_a"),
	"mime" = list("name" = "mime shoes", "icon_state" = "white", "step_volume_mod" = 0),
	"purple" = list("name" = "purple shoes", "icon_state" = "purple"),
	"rainbow" = list("name" = "rainbow shoes", "desc" = "Very colourful shoes.", "icon_state" = "rain_bow"),
	"red" = list("name" = "red shoes", "desc" = "Stylish red shoes.", "icon_state" = "red"),
	"sandals" = list("desc" = "A pair of simple sandals.", "name" = "sandals", "icon_state" = "sandals_recolor"),
	"sandals_elegant" = list("name" = "elegant sandals", "desc" = "A pair of sandals with thin straps. It emphasizes the ankles!", "icon_state" = "sandals_elegant", "item_state" = "sandals_elegant", "addblends" = "sandals_elegant_a"),
	"skater" = list("name" = "skater shoes", "desc" = "A pair of wide shoes with thick soles.  Designed for skating.", "icon_state" = "skatershoe", "addblends" = "skatershoe_a", "item_state_slots" = list(slot_r_hand_str = "skaterheld", slot_l_hand_str = "skaterheld")),
	"sneakersblue" = list("name" = "blue sneakers", "desc" = "A stylish, expensive pair of blue sneakers.", "icon_state" = "sneakersblue", "item_state" = "sneakersblue"),
	"sneakerspurple" = list("name" = "purple sneakers", "desc" = "A stylish, expensive pair of purple sneakers.", "icon_state" = "sneakerspurple", "item_state" = "sneakerspurple"),
	"sneakersred" = list("name" = "red sneakers", "desc" = "A stylish, expensive pair of red sneakers.", "icon_state" = "sneakersred", "item_state" = "sneakersred"),
	"yellow" = list("name" = "yellow shoes", "icon_state" = "yellow"),
))

/// The variant rows (variants(), code/engine/lifeforms/variants.dm).
/obj/item/clothing/shoes/proc/variant_table()
	return GLOB.dq_variants_shoes
