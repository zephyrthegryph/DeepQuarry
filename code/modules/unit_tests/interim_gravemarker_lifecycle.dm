/// Actual grave-marker tool completion returns its wood material on the original floor.
/datum/unit_test/interim_gravemarker_dismantle_lifecycle/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/structure/gravemarker/marker = allocate(/obj/structure/gravemarker, T)
	marker.grave_name = "Remembered"
	marker.epitaph = "A marker to dismantle"
	TEST_ASSERT_EQUAL(marker.material, get_material_by_name(MAT_WOOD), "the actual default marker has wood material")
	marker.wrench_act_tool_done(user)
	own_turf_contents(T)
	TEST_ASSERT(QDELETED(marker), "actual wrench completion immediately consumes the original marker")
	TEST_ASSERT_NULL(locate_within(T, /obj/structure/gravemarker), "actual dismantling leaves no duplicate marker")
	TEST_ASSERT_EQUAL(length(contents_of(T, /obj/item/stack/material/wood)), 1, "actual dismantling creates exactly one returned wood stack")
	var/obj/item/stack/material/wood/wood = locate_within(T, /obj/item/stack/material/wood)
	TEST_ASSERT_EQUAL(wood.get_amount(), 1, "actual dismantling returns exactly one wood sheet")
	TEST_ASSERT_EQUAL(wood.loc, T, "the actual wood return stays on the original marker turf")
	TEST_ASSERT(!QDELETED(wood), "the real wood return survives marker consumption")
	TEST_ASSERT_NULL(user.get_active_hand(), "dismantling the floor marker does not equip its output")
