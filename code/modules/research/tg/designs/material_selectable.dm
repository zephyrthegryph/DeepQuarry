// Material-selectable lathe designs.
//
// Instead of registering one techweb entry per material, these designs are flagged
// `material_selectable`: the Fabricator UI shows a material picker, and the chosen
// loaded material (steel, an exotic alloy, a substance alloy, ...) is consumed and
// the product is made of it. So a substance-alloy knife forged here carries that
// substance's structural stats and its discharge effect.

/datum/design_techweb/material_knife
	name = "Material Knife"
	desc = "A combat knife forged from a chosen loaded material."
	id = "material_knife"
	build_type = AUTOLATHE | PROTOLATHE
	build_path = /obj/item/material/knife
	material_selectable = TRUE
	selectable_amount = SHEET_MATERIAL_AMOUNT
	construction_time = 2 SECONDS
	category = list(
		RND_CATEGORY_INITIAL,
		RND_CATEGORY_WEAPONS + RND_SUBCATEGORY_WEAPONS_MELEE
	)

/datum/design_techweb/material_sword
	name = "Material Sword"
	desc = "A longsword forged from a chosen loaded material."
	id = "material_sword"
	build_type = AUTOLATHE | PROTOLATHE
	build_path = /obj/item/material/sword
	material_selectable = TRUE
	selectable_amount = SHEET_MATERIAL_AMOUNT * 2
	construction_time = 4 SECONDS
	category = list(
		RND_CATEGORY_INITIAL,
		RND_CATEGORY_WEAPONS + RND_SUBCATEGORY_WEAPONS_MELEE
	)

// Forge a stock 9mm magazine from any loaded alloy. No bespoke ammo subtype: the base
// ammo_magazine takes the chosen material as its second Initialize arg and stamps its
// rounds, and a substance alloy's rounds discharge on impact via the shared infusion.
// Other calibers become material-selectable by adding a design like this — nothing else.
/datum/design_techweb/material_rounds_9mm
	name = "Material Rounds (9mm)"
	desc = "A stock 9mm magazine forged from a chosen loaded material. Fits any 9mm sidearm; a substance alloy makes each round discharge its effect on impact."
	id = "material_rounds_9mm"
	build_type = AUTOLATHE | PROTOLATHE
	build_path = /obj/item/ammo_magazine/m9mm
	material_selectable = TRUE
	selectable_amount = SHEET_MATERIAL_AMOUNT
	materials = list(MAT_STEEL = 600)
	construction_time = 3 SECONDS
	category = list(
		RND_CATEGORY_INITIAL,
		RND_CATEGORY_WEAPONS + RND_SUBCATEGORY_WEAPONS_AMMO
	)

/datum/techweb_node/material_fabrication
	id = "material_fabrication"
	display_name = "Material Fabrication"
	description = "Forge weapons and ammunition from any loaded material — exotic and substance alloys included, carrying their properties."
	starting_node = TRUE
	design_ids = list(
		"material_knife",
		"material_sword",
		"material_rounds_9mm",
	)
