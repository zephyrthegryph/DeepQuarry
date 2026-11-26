// Variants of /obj/item/reagent_containers/spray: one row per bottle that only set data (the name, description, sprite, size, starting fill and whether it
// has a safety; doc/rewrite/proposals/chemistry_recipes.md section 11c). The old path, parent + "/" + key, still resolves for maps and saves (variant_alias_of()).
// A bottle is one refillable container: empty it, fill it with anything else, relabel it with a pen.

GLOBAL_LIST_INIT(dq_variants_spray, list(
	"cleaner" = list(
		"name" = "space cleaner",
		"desc" = "BLAM!-brand non-foaming space cleaner!",
		"starting_fill" = list(REAGENT_ID_CLEANER = 250)),
	"drone_cleaner" = list(
		"name" = "space cleaner",
		"desc" = "BLAM!-brand non-foaming space cleaner!",
		"volume" = 50,
		"starting_fill" = list(REAGENT_ID_CLEANER = 50)),
	"sterilizine" = list(
		"name" = REAGENT_ID_STERILIZINE,
		"desc" = "Great for hiding incriminating bloodstains and sterilizing scalpels.",
		"starting_fill" = list(REAGENT_ID_STERILIZINE = 250)),
	"pepper" = list(
		"name" = "pepperspray",
		"desc" = "Manufactured by UhangInc, used to blind and down an opponent quickly.",
		"icon" = 'icons/obj/weapons.dmi',
		"icon_state" = "pepperspray",
		"item_state" = "pepperspray",
		"max_transfer_amount" = null,
		"volume" = 40,
		"table_center_y" = 16,
		"safety_lock" = TRUE,
		"safety" = TRUE,
		"starting_fill" = list(REAGENT_ID_CONDENSEDCAPSAICIN = 40)),
	"luminol" = list(
		"name" = "luminol bottle",
		"desc" = "A bottle containing an odourless, colorless liquid.",
		"icon" = 'icons/obj/forensics.dmi',
		"icon_state" = "luminol",
		"item_state" = "cleaner",
		"starting_fill" = list(REAGENT_ID_LUMINOL = 250)),
	"plantbgone" = list(
		"name" = REAGENT_PLANTBGONE,
		"desc" = "Kills those pesky weeds!",
		"icon" = 'icons/obj/hydroponics_machines.dmi',
		"icon_state" = "plantbgone",
		"item_state" = "plantbgone",
		"volume" = 100,
		"starting_fill" = list(REAGENT_ID_PLANTBGONE = 100)),
	"windowsealant" = list(
		"name" = "Krak-b-gone",
		"desc" = "A spray bottle of silicate sealant for rapid window repair.",
		"icon" = 'icons/obj/items.dmi',
		"icon_state" = "windowsealant",
		"item_state" = "spraycan",
		"max_transfer_amount" = null,
		"volume" = 80,
		"starting_fill" = list(REAGENT_ID_SILICATE = 80)),
))
