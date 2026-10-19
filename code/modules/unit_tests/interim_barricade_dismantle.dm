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

/// The movement fast path (admission.md D7): a barricade's passable() pass flags let a PASSTABLE mover through; anything else is blocked
/// while it stands, and a knocked-flat (non-dense) one blocks nothing.
/datum/unit_test/dq_passable_fast_path

/datum/unit_test/dq_passable_fast_path/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/structure/barricade/barrier = allocate(/obj/structure/barricade, T)
	var/obj/effect/beam/beam = allocate(/obj/effect/beam, T)
	var/obj/structure/barricade/crate = allocate(/obj/structure/barricade, T) // a structure: no PASSTABLE (items have it)
	TEST_ASSERT(passable_of(barrier)?.pass_flags & PASSTABLE, "the barricade declares PASSTABLE through passable()")
	TEST_ASSERT(barrier.CanPass(beam, T), "a PASSTABLE mover goes through a standing barricade")
	TEST_ASSERT(!barrier.CanPass(crate, T), "a mover without PASSTABLE is blocked by a standing barricade")
	barrier.set_density(FALSE)
	TEST_ASSERT(barrier.CanPass(crate, T), "a barricade that isn't dense blocks nothing")
