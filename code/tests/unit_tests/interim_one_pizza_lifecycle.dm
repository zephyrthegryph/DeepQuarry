/// Actual cutting completion turns the floor pizza into its five configured slice varieties.
/datum/unit_test/interim_one_pizza_slice_lifecycle/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/structure/theonepizza/pizza = allocate(/obj/structure/theonepizza, T)
	var/list/configured = pizza.slicelist
	var/list/expected = configured.Copy()
	TEST_ASSERT_EQUAL(length(expected), 5, "the actual giant pizza configures five slice varieties")
	for(var/slice_path in expected)
		TEST_ASSERT_EQUAL(length(contents_of(T, slice_path)), 0, "the original turf contains no slice of the configured variety")
	test_op_handler(pizza, "slice_done", user)
	own_turf_contents(T)
	TEST_ASSERT(QDELETED(pizza), "actual cutting completion immediately consumes the original floor pizza")
	TEST_ASSERT_NULL(locate_within(T, /obj/structure/theonepizza), "the cut pizza leaves no duplicate source structure")
	var/slice_count = 0
	for(var/slice_path in expected)
		var/list/slices = contents_of(T, slice_path)
		TEST_ASSERT_EQUAL(length(slices), 1, "actual cutting creates exactly one slice of each configured variety")
		var/obj/item/reagent_containers/food/snacks/sliceable/pizza/slice = slices[1]
		TEST_ASSERT_EQUAL(slice.loc, T, "each actual cut slice remains on the original pizza turf")
		TEST_ASSERT(!QDELETED(slice), "each actual cut slice survives source consumption")
		slice_count += length(slices)
	TEST_ASSERT_EQUAL(slice_count, 5, "actual cutting creates exactly five configured slices")
	TEST_ASSERT_NULL(user.get_active_hand(), "cutting the floor structure does not equip an output slice")
