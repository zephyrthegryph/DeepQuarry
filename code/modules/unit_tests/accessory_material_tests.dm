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

/// A material weapon takes the material passed to its constructor; the type's forced material applies only when none is passed.
/datum/unit_test/material_weapon_material_precedence

/datum/unit_test/material_weapon_material_precedence/Run()
	var/obj/item/material/ashtray/plastic/forced = allocate(/obj/item/material/ashtray/plastic, test_floor())
	var/datum/material/forced_mat = forced.get_material()
	TEST_ASSERT_EQUAL(forced_mat?.name, MAT_PLASTIC, "a forced-material weapon without a passed material is made of its forced material")
	var/obj/item/material/ashtray/plastic/passed = allocate(/obj/item/material/ashtray/plastic, test_floor(), MAT_SILVER)
	var/datum/material/passed_mat = passed.get_material()
	TEST_ASSERT_EQUAL(passed_mat?.name, MAT_PLASTIC, "a forced-material weapon built with a material argument is still made of its forced material")
	var/obj/item/material/knife/knife = allocate(/obj/item/material/knife, test_floor(), MAT_GOLD)
	var/datum/material/knife_mat = knife.get_material()
	TEST_ASSERT_EQUAL(knife_mat?.name, MAT_GOLD, "a plain material weapon is made of the passed material")
