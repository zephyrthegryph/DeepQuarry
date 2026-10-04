/// Fixed bracelets choose their own material before the clothing parent applies armor and integrity.
/datum/unit_test/interim_bracelet_material_contract/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/list/material_types = list(
		/obj/item/clothing/accessory/bracelet/material/wood = MAT_WOOD,
		/obj/item/clothing/accessory/bracelet/material/plastic = MAT_PLASTIC,
		/obj/item/clothing/accessory/bracelet/material/iron = MAT_IRON,
		/obj/item/clothing/accessory/bracelet/material/steel = MAT_STEEL,
		/obj/item/clothing/accessory/bracelet/material/silver = MAT_SILVER,
		/obj/item/clothing/accessory/bracelet/material/gold = MAT_GOLD,
		/obj/item/clothing/accessory/bracelet/material/platinum = MAT_PLATINUM,
		/obj/item/clothing/accessory/bracelet/material/phoron = MAT_PHORON,
		/obj/item/clothing/accessory/bracelet/material/glass = MAT_GLASS,
	)
	for(var/bracelet_type in material_types)
		var/material_key = material_types[bracelet_type]
		var/datum/material/expected = get_material_by_name(material_key)
		TEST_ASSERT(expected, "The actual fixed bracelet material exists: [material_key]")
		var/obj/item/clothing/accessory/bracelet/material/fixed = allocate(bracelet_type, T, "invalid caller material")
		var/obj/item/clothing/accessory/bracelet/material/custom = allocate(/obj/item/clothing/accessory/bracelet/material, T, material_key)
		TEST_ASSERT(fixed && !QDELETED(fixed), "Fixed bracelet construction ignores the caller's invalid material: [bracelet_type]")
		TEST_ASSERT(custom && !QDELETED(custom), "The generic bracelet accepts the actual material: [material_key]")
		TEST_ASSERT_EQUAL(fixed.get_material(), expected, "The fixed bracelet retains the exact registered material")
		TEST_ASSERT_EQUAL(custom.get_material(), expected, "The generic bracelet honors its caller's material")
		TEST_ASSERT_EQUAL(fixed.max_integrity, max(1, round(expected.integrity / 10)) * MATERIAL_WEAR_UNIT, "The parent applies the chosen material's integrity")
		TEST_ASSERT_EQUAL(fixed.max_integrity, custom.max_integrity, "Fixed and custom forms receive the same parent material behavior")
		TEST_ASSERT_EQUAL(lowertext(fixed.color), lowertext(expected.icon_colour), "The real bracelet appearance uses the chosen material")
		TEST_ASSERT_EQUAL(fixed.name, "[expected.display_name] bracelet", "The fixed bracelet displays its chosen material")
