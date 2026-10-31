/// Cutting a body-sized present releases every occupant before removing its wrapper.
/datum/unit_test/interim_wrapped_present_release/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/item/tool/wirecutters/tool = allocate(/obj/item/tool/wirecutters, T)
	var/obj/effect/spresent/wrapper = allocate(/obj/effect/spresent, T)
	var/mob/living/carbon/human/first = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/second = allocate(/mob/living/carbon/human, T)
	first.forceMove(wrapper)
	second.forceMove(wrapper)
	TEST_ASSERT_EQUAL(first.loc, wrapper, "the first occupant starts inside the wrapper")
	TEST_ASSERT_EQUAL(second.loc, wrapper, "the second occupant starts inside the wrapper")
	TEST_ASSERT_EQUAL(test_op_handler(wrapper, "wirecutter_used", user, tool), OP_OK, "cutting the occupied present succeeds")
	TEST_ASSERT(QDELETED(wrapper), "cutting consumes the occupied wrapper")
	TEST_ASSERT(!QDELETED(first), "cutting preserves the first occupant")
	TEST_ASSERT(!QDELETED(second), "cutting preserves the second occupant")
	TEST_ASSERT_EQUAL(first.loc, T, "the first occupant is released to the original turf")
	TEST_ASSERT_EQUAL(second.loc, T, "the second occupant is released to the original turf")

/// An empty body-sized present is still removable with wirecutters.
/datum/unit_test/interim_wrapped_present_empty/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/item/tool/wirecutters/tool = allocate(/obj/item/tool/wirecutters, T)
	var/obj/effect/spresent/wrapper = allocate(/obj/effect/spresent, T)
	TEST_ASSERT_EQUAL(length(contents_of(wrapper)), 0, "the wrapper starts empty")
	TEST_ASSERT_EQUAL(test_op_handler(wrapper, "wirecutter_used", user, tool), OP_OK, "cutting the empty present succeeds")
	TEST_ASSERT(QDELETED(wrapper), "cutting consumes the empty wrapper")
