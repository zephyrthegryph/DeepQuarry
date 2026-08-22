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
	materials = list()
	construction_time = 3 SECONDS
	category = list(
		RND_CATEGORY_INITIAL,
		RND_CATEGORY_WEAPONS + RND_SUBCATEGORY_WEAPONS_AMMO
	)

/datum/design_techweb/material_armor_plate
	name = "Material Armor Plate"
	desc = "A rigid armor plate whose protection, weight, electrical response, and durability derive from a selected material."
	id = "material_armor_plate"
	build_type = AUTOLATHE | PROTOLATHE
	build_path = /obj/item/material/armor_plating
	material_selectable = TRUE
	selectable_amount = SHEET_MATERIAL_AMOUNT
	construction_time = 3 SECONDS
	category = list(RND_CATEGORY_INITIAL, RND_CATEGORY_EQUIPMENT + RND_SUBCATEGORY_EQUIPMENT_SECURITY)
	departmental_flags = DEPARTMENT_BITFLAG_SECURITY | DEPARTMENT_BITFLAG_SCIENCE

/datum/design_techweb/material_armor_insert
	name = "Material Armor Insert"
	desc = "A fitted armor insert made from selected plate stock."
	id = "material_armor_insert"
	build_type = AUTOLATHE | PROTOLATHE
	build_path = /obj/item/material/armor_plating/insert
	material_selectable = TRUE
	selectable_amount = SHEET_MATERIAL_AMOUNT * 2
	construction_time = 4 SECONDS
	category = list(RND_CATEGORY_INITIAL, RND_CATEGORY_EQUIPMENT + RND_SUBCATEGORY_EQUIPMENT_SECURITY)
	departmental_flags = DEPARTMENT_BITFLAG_SECURITY | DEPARTMENT_BITFLAG_SCIENCE

/datum/design_techweb/material_power_cell
	name = "Material-Core Power Cell"
	desc = "A standard power cell whose capacity, EMP tolerance, and durability derive from the selected finished solid material."
	id = "material_power_cell"
	build_type = AUTOLATHE | PROTOLATHE
	build_path = /obj/item/cell
	material_selectable = TRUE
	selectable_amount = SHEET_MATERIAL_AMOUNT * 2
	material_application = MATERIAL_APPLICATION_CELL
	materials = list(MAT_GLASS = 500)
	construction_time = 5 SECONDS
	category = list(RND_CATEGORY_INITIAL, RND_CATEGORY_EQUIPMENT + RND_SUBCATEGORY_EQUIPMENT_ENGINEERING)
	departmental_flags = DEPARTMENT_BITFLAG_ENGINEERING | DEPARTMENT_BITFLAG_SCIENCE

/obj/item/stack/cable_coil/engineered
	name = "engineered cable coil"
	desc = "A fabricated layered conductor whose installed segments retain their material construction."

/datum/design_techweb/material_composite_cable
	name = "Material Power Cable"
	desc = "Ten lengths of power cable made from a selected material or layered composite. Composite cores, buffers, and jackets remain physically meaningful after installation."
	id = "material_composite_cable"
	build_type = AUTOLATHE | PROTOLATHE
	build_path = /obj/item/stack/cable_coil/engineered
	material_selectable = TRUE
	selectable_amount = SHEET_MATERIAL_AMOUNT
	materials = list()
	construction_time = 3 SECONDS
	category = list(RND_CATEGORY_INITIAL, RND_CATEGORY_EQUIPMENT + RND_SUBCATEGORY_EQUIPMENT_ENGINEERING)
	departmental_flags = DEPARTMENT_BITFLAG_ENGINEERING | DEPARTMENT_BITFLAG_SCIENCE

/datum/design_techweb/material_composite_cable/create_item(target, chosen_material)
	if(!chosen_material)
		return null
	return new /obj/item/stack/cable_coil/engineered(target, 10, null, chosen_material)

/datum/design_techweb/material_reaction_vessel
	name = "Material Reaction Vessel"
	desc = "A reusable reaction vessel whose exposed liner controls corrosion and catalytic reaction rate."
	id = "material_reaction_vessel"
	build_type = AUTOLATHE | PROTOLATHE
	build_path = /obj/item/reagent_containers/glass/beaker/composite
	material_selectable = TRUE
	selectable_amount = SHEET_MATERIAL_AMOUNT
	materials = list(MAT_GLASS = 250)
	construction_time = 3 SECONDS
	category = list(RND_CATEGORY_INITIAL, RND_CATEGORY_EQUIPMENT + RND_SUBCATEGORY_EQUIPMENT_SCIENCE)
	departmental_flags = DEPARTMENT_BITFLAG_SCIENCE | DEPARTMENT_BITFLAG_MEDICAL

/datum/design_techweb/material_reaction_vessel/create_item(target, chosen_material)
	if(!chosen_material)
		return null
	return new /obj/item/reagent_containers/glass/beaker/composite(target, chosen_material)

/datum/techweb_node/material_fabrication
	id = "material_fabrication"
	display_name = "Material Fabrication"
	description = "Forge weapons and ammunition from any loaded material — exotic and substance alloys included, carrying their properties."
	starting_node = TRUE
	design_ids = list(
		"board_material_furnace",
		"material_crucible",
		"material_knife",
		"material_sword",
		"material_rounds_9mm",
		"material_armor_plate",
		"material_armor_insert",
		"material_power_cell",
		"material_composite_cable",
		"material_reaction_vessel",
	)
