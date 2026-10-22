/// A material ring or bracelet takes the material passed to its constructor; the type's forced material applies only when none is passed.
/datum/unit_test/accessory_material_precedence
	var/list/pairs = list(
		/obj/item/clothing/accessory/ring/material/gold,
		/obj/item/clothing/accessory/bracelet/material/gold)

/datum/unit_test/accessory_material_precedence/Run()
	for(var/type in pairs)
		var/obj/item/clothing/accessory/forced = allocate(type, test_floor())
		TEST_ASSERT_EQUAL(forced.get_material()?.name, MAT_GOLD, "[type] without a passed material is made of its forced material")
		var/obj/item/clothing/accessory/passed = allocate(type, test_floor(), MAT_SILVER)
		TEST_ASSERT_EQUAL(passed.get_material()?.name, MAT_SILVER, "[type] built with a material argument is made of that material, not the forced one")
