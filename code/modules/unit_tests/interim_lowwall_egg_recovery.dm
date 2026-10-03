/// Real low-wall variants preserve their material-specific three-sheet dismantling return.
/datum/unit_test/interim_lowwall_recovery
	var/wall_type = /obj/structure/low_wall/bay
	var/expected_material = MAT_STEEL

/datum/unit_test/interim_lowwall_recovery/reinforced
	wall_type = /obj/structure/low_wall/bay/reinforced
	expected_material = MAT_PLASTEEL

/datum/unit_test/interim_lowwall_recovery/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/structure/low_wall/wall = allocate(wall_type, T)
	TEST_ASSERT(!QDELETED(wall), "the actual low wall initializes on its valid floor")
	TEST_ASSERT_EQUAL(wall.material.name, expected_material, "the actual low-wall variant resolves its expected material")
	var/product_type = wall.material.stack_type
	TEST_ASSERT(product_type, "the actual material declares its returned sheet type")
	TEST_ASSERT_EQUAL(length(contents_of(T, product_type)), 0, "the floor starts without returned sheets")
	var/obj/item/book/bystander = allocate(/obj/item/book, T)
	wall.dismantle()
	own_turf_contents(T)
	TEST_ASSERT(QDELETED(wall), "actual dismantling consumes the original low wall")
	TEST_ASSERT_NULL(locate_within(T, /obj/structure/low_wall), "dismantling leaves no duplicate low wall")
	var/sheets = 0
	for(var/obj/item/stack/material/product as anything in contents_of(T, product_type))
		TEST_ASSERT_EQUAL(product.loc, T, "all returned sheets remain on the original floor")
		TEST_ASSERT_EQUAL(product.get_material_name(), expected_material, "all returned sheets match the actual variant material")
		sheets += product.get_amount()
	TEST_ASSERT_EQUAL(sheets, 3, "actual dismantling returns exactly three matching sheets")
	TEST_ASSERT(!QDELETED(bystander), "dismantling preserves an unrelated floor item")
	TEST_ASSERT_EQUAL(bystander.loc, T, "the unrelated item remains on its original floor")

/// Actual egg welding releases its stored cargo before consuming the egg shell.
/datum/unit_test/interim_egg_weld_recovery/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/structure/closet/secure_closet/egg/egg = allocate(/obj/structure/closet/secure_closet/egg, T)
	var/obj/item/book/book = allocate(/obj/item/book, T)
	TEST_ASSERT_EQUAL(egg.store_items(), 1, "actual inherited storage gathers the floor book")
	TEST_ASSERT_EQUAL(book.loc, egg, "the real stored book is inside the egg")
	TEST_ASSERT(book in egg.slot_contents(CONTAINER_SLOT_INTERIOR), "the original book occupies the actual interior slot")
	var/obj/item/weldingtool/tool = allocate(/obj/item/weldingtool, T)
	TEST_ASSERT(user.put_in_active_hand(tool), "the actor holds the actual welder")
	TEST_ASSERT(egg.welder_act(user, tool), "actual egg welding reports success")
	own_turf_contents(T)
	TEST_ASSERT(QDELETED(egg), "actual welding consumes the original egg shell")
	TEST_ASSERT(!QDELETED(book), "the actual stored book survives welding")
	TEST_ASSERT_EQUAL(book.loc, T, "welding releases the original book onto the floor")
	TEST_ASSERT_EQUAL(length(contents_of(T, /obj/item/book)), 1, "welding preserves exactly the original book")
	TEST_ASSERT_NULL(locate_within(T, /obj/structure/closet/secure_closet/egg), "welding leaves no duplicate egg")
	TEST_ASSERT_EQUAL(user.get_active_hand(), tool, "welding keeps the original tool held")
