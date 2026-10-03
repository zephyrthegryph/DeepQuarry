/// Both real barricade types return their actual material once and remove the source.
/datum/unit_test/interim_barricade_dismantle
	var/barricade_type = /obj/structure/barricade
	var/expected_material = MAT_WOOD

/datum/unit_test/interim_barricade_dismantle/sandbag
	barricade_type = /obj/structure/barricade/sandbag
	expected_material = MAT_CLOTH

/datum/unit_test/interim_barricade_dismantle/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/structure/barricade/barrier = allocate(barricade_type, T)
	var/datum/material/material = barrier.material
	TEST_ASSERT(material, "actual barricade initialization resolves its material")
	TEST_ASSERT_EQUAL(material.name, expected_material, "the actual type initializes its expected wood or cloth material")
	var/product_type = material.stack_type
	TEST_ASSERT(product_type, "actual barricade material declares its returned stack type")
	TEST_ASSERT_EQUAL(length(contents_of(T, product_type)), 0, "the fixture starts with no returned material")
	barrier.dismantle()
	own_turf_contents(T)
	TEST_ASSERT(QDELETED(barrier), "actual dismantling removes the original barricade")
	TEST_ASSERT_NULL(locate_within(T, /obj/structure/barricade), "dismantling leaves no duplicate barricade")
	var/list/products = contents_of(T, product_type)
	TEST_ASSERT_EQUAL(length(products), 1, "actual dismantling produces exactly one matching material stack")
	var/obj/item/stack/product = products[1]
	TEST_ASSERT_EQUAL(product.get_amount(), 1, "actual dismantling returns exactly one sheet")
	TEST_ASSERT_EQUAL(product.loc, T, "the returned material stays on the original floor")
	TEST_ASSERT_EQUAL(product.get_material_name(), material.name, "the returned sheet matches the original material")
