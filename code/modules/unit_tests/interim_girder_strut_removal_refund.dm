/// The loose-strut removal step refunds exactly one reinforcement sheet only after its tool task completes, preserving the original support frame.
/datum/unit_test/interim_girder_strut_removal_refund/Run()
	test_driver_begin()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	user.set_combat_mode(FALSE)
	var/obj/structure/girder/girder = allocate(/obj/structure/girder, T)
	var/obj/item/tool/wirecutters/cutters = allocate(/obj/item/tool/wirecutters, T)
	var/datum/material/frame_material = girder.girder_material
	var/datum/material/reinforcement = get_material_by_name(MAT_PLASTEEL)
	var/unreinforced_cover = girder.cover
	girder.reinf_material = reinforcement
	girder.reinforce_girder()
	// Begin at the real loose-strut state; this test covers removal, not the preceding screwdriver wait.
	girder.state = 1
	TEST_ASSERT_EQUAL(length(contents_of(T, /obj/item/stack/material)), 0, "the actual fixture starts without refunded material sheets")
	TEST_ASSERT(user.put_in_active_hand(cutters), "the actual actor holds the real strut-removal tool")
	TEST_ASSERT(!user.incapacitated(INCAPACITATION_STUNNED | INCAPACITATION_KNOCKOUT), "the actual strut-removal actor starts capable")
	var/datum/op_result/removal = test_click(user, girder, cutters)
	TEST_ASSERT_NULL(removal?.outcome, "strut removal waits for its tool delay")
	test_time(1 SECOND)
	TEST_ASSERT_EQUAL(girder.reinf_material, reinforcement, "pending removal retains the exact actual reinforcement")
	TEST_ASSERT_EQUAL(girder.state, 1, "pending removal retains the loose-strut stage")
	TEST_ASSERT_EQUAL(length(contents_of(T, /obj/item/stack/material)), 0, "pending removal creates no material refund early")
	test_time(10 SECONDS)
	own_turf_contents(T)
	TEST_ASSERT(!user.incapacitated(INCAPACITATION_STUNNED | INCAPACITATION_KNOCKOUT), "the actual actor remains capable through the single removal task")
	TEST_ASSERT(!QDELETED(girder), "actual strut removal preserves the original support girder")
	TEST_ASSERT_EQUAL(girder.loc, T, "actual strut removal preserves the original frame's floor")
	TEST_ASSERT_EQUAL(girder.girder_material, frame_material, "actual strut removal preserves the original frame material")
	TEST_ASSERT_NULL(girder.reinf_material, "actual strut removal clears the reinforcement view")
	TEST_ASSERT(girder.anchored, "actual strut removal keeps the original support frame anchored")
	TEST_ASSERT_EQUAL(girder.state, 0, "actual removal returns to the ordinary anchored construction stage")
	TEST_ASSERT_EQUAL(girder.cover, unreinforced_cover, "actual removal restores the original unreinforced projectile cover")
	var/refunded = 0
	var/other_sheets = 0
	for(var/obj/item/stack/material/sheets as anything in contents_of(T, /obj/item/stack/material))
		if(sheets.type == /obj/item/stack/material/plasteel)
			refunded += sheets.get_amount()
		else
			other_sheets += sheets.get_amount()
	TEST_ASSERT_EQUAL(refunded, 1, "actual strut removal refunds exactly one plasteel reinforcement sheet")
	TEST_ASSERT_EQUAL(other_sheets, 0, "actual strut removal refunds none of the retained frame material")
	TEST_ASSERT_EQUAL(user.get_active_hand(), cutters, "actual removal preserves the original held tool")
	test_driver_end()
