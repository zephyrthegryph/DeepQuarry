/// Actual bonfire completion returns all five configured wood sheets and removes the fire.
/datum/unit_test/interim_bonfire_dismantle/Run()
	test_driver_begin()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/structure/bonfire/fire = allocate(/obj/structure/bonfire, T)
	TEST_ASSERT_EQUAL(fire.material.name, MAT_WOOD, "the actual bonfire initializes its wood material")
	TEST_ASSERT(!fire.burning, "the fixture is an extinguished bonfire")
	TEST_ASSERT_EQUAL(fire.get_fuel_amount(), 0, "the real bonfire starts without fuel")
	TEST_ASSERT_EQUAL(length(contents_of(T, /obj/item/stack/material/wood)), 0, "the floor starts without recovered wood")
	test_op_handler(fire, "dismantle_done", user)
	own_turf_contents(T)
	TEST_ASSERT(QDELETED(fire), "actual dismantling completion consumes the bonfire")
	TEST_ASSERT_NULL(locate_within(T, /obj/structure/bonfire), "completion leaves no duplicate bonfire")
	var/sheets = 0
	for(var/obj/item/stack/material/wood/wood as anything in contents_of(T, /obj/item/stack/material/wood))
		TEST_ASSERT_EQUAL(wood.loc, T, "every recovered wood stack stays on the original floor")
		sheets += wood.get_amount()
	TEST_ASSERT_EQUAL(sheets, 5, "actual completion returns exactly five wood sheets")
	TEST_ASSERT_NULL(user.get_active_hand(), "dismantling does not equip recovered material")
	test_driver_end()

/// Actual catwalk deconstruction returns two rods on solid floor and its installed tile.
/datum/unit_test/interim_catwalk_dismantle
	var/plate = FALSE

/datum/unit_test/interim_catwalk_dismantle/plated
	plate = TRUE

/datum/unit_test/interim_catwalk_dismantle/Run()
	test_driver_begin()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/structure/catwalk/catwalk = allocate(/obj/structure/catwalk, T)
	var/obj/item/stack/tile/floor/tiles
	if(plate)
		tiles = allocate(/obj/item/stack/tile/floor, T, 2)
		catwalk.plate_done(user, tiles)
		TEST_ASSERT_EQUAL(tiles.get_amount(), 1, "actual plating consumes exactly one original tile")
		TEST_ASSERT_EQUAL(catwalk.plated_tile, /obj/item/stack/tile/floor, "actual plating records the installed tile type")
	else
		TEST_ASSERT_NULL(catwalk.plated_tile, "an unplated actual catwalk has no recorded tile")
	TEST_ASSERT_EQUAL(length(contents_of(T, /obj/item/stack/rods)), 0, "the floor starts without recovered rods")
	var/obj/item/weldingtool/welder = allocate(/obj/item/weldingtool, T)
	TEST_ASSERT(user.put_in_active_hand(welder), "the actor holds the real welder before slicing")
	user.set_combat_mode(FALSE) // the help stance keeps the lattice
	test_click(user, catwalk, welder)
	test_time(1 SECOND)
	TEST_ASSERT(!QDELETED(catwalk), "an unlit real welder does not dismantle the catwalk")
	TEST_ASSERT_EQUAL(length(contents_of(T, /obj/item/stack/rods)), 0, "the unlit slicing attempt returns no rods")
	TEST_ASSERT(test_op_handler(welder, "interaction_self", user, welder), "actual welder activation reports success")
	TEST_ASSERT(welder.isOn(), "actual activation lights the held welder")
	var/fuel_before = welder.get_fuel()
	TEST_ASSERT(test_op_committed(test_click(user, catwalk, welder)), "the public slicing op commits")
	test_time(1 SECOND)
	TEST_ASSERT_EQUAL(welder.get_fuel(), fuel_before, "catwalk slicing preserves the declared zero fuel cost")
	test_op_handler(welder, "interaction_self", user, welder)
	TEST_ASSERT(!welder.isOn(), "actual activation switches the welder off after slicing")
	own_turf_contents(T)
	TEST_ASSERT(QDELETED(catwalk), "actual deconstruction consumes the original catwalk")
	TEST_ASSERT_NULL(locate_within(T, /obj/structure/catwalk), "deconstruction leaves no duplicate catwalk")
	TEST_ASSERT_NULL(locate_within(T, /obj/structure/lattice), "solid-floor deconstruction creates no lattice even when requested")
	var/rods = 0
	for(var/obj/item/stack/rods/rod_stack as anything in contents_of(T, /obj/item/stack/rods))
		TEST_ASSERT_EQUAL(rod_stack.loc, T, "the recovered rods stay on the original floor")
		rods += rod_stack.get_amount()
	TEST_ASSERT_EQUAL(rods, 2, "solid-floor deconstruction returns exactly two rods")
	var/recovered_tiles = 0
	for(var/obj/item/stack/tile/floor/tile_stack as anything in contents_of(T, /obj/item/stack/tile/floor))
		if(tile_stack != tiles)
			recovered_tiles += tile_stack.get_amount()
	TEST_ASSERT_EQUAL(recovered_tiles, plate ? 1 : 0, "only a plated catwalk returns its installed tile")
	TEST_ASSERT_EQUAL(user.get_active_hand(), welder, "slicing keeps the original welder held instead of equipping recovered material")
	test_driver_end()
