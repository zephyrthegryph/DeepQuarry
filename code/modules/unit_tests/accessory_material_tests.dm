/// A material ring or bracelet takes the material passed to its constructor; the type's forced material applies only when none is passed.
/datum/unit_test/accessory_material_precedence
	var/list/pairs = list(
		/obj/item/clothing/accessory/ring/material/gold,
		/obj/item/clothing/accessory/bracelet/material/gold)

/datum/unit_test/accessory_material_precedence/Run()
	for(var/type in pairs)
		var/obj/item/clothing/accessory/forced = allocate(type, test_floor())
		var/datum/material/forced_mat = forced.get_material()
		TEST_ASSERT_EQUAL(forced_mat?.name, MAT_GOLD, "[type] without a passed material is made of its forced material")
		var/obj/item/clothing/accessory/passed = allocate(type, test_floor(), MAT_SILVER)
		var/datum/material/passed_mat = passed.get_material()
		TEST_ASSERT_EQUAL(passed_mat?.name, MAT_SILVER, "[type] built with a material argument is made of that material, not the forced one")
