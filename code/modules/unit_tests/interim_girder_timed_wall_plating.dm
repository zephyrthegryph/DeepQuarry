/// Real girder plating spends two sheets at completion and wall dismantling refunds the same material allowance.
/datum/unit_test/om/interim_girder_timed_wall_plating
	var/deplete_while_waiting = FALSE

/datum/unit_test/om/interim_girder_timed_wall_plating/depleted
	deplete_while_waiting = TRUE

/datum/unit_test/om/interim_girder_timed_wall_plating/run_om(list/made)
	var/turf/T = run_loc_floor_bottom_left
	var/original_floor_type = T.type
	var/tile_x = T.x
	var/tile_y = T.y
	var/tile_z = T.z
	defer_cleanup(null, GLOBAL_PROC_REF(interim_restore_wall_floor), tile_x, tile_y, tile_z, original_floor_type)
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	user.enable_godmode()
	var/obj/structure/girder/girder = allocate(/obj/structure/girder, T)
	var/start_amount = deplete_while_waiting ? 2 : 3
	var/obj/item/stack/material/steel/sheets = allocate(/obj/item/stack/material/steel, T, start_amount)
	var/datum/material/steel = get_material_by_name(MAT_STEEL)
	TEST_ASSERT(girder.anchored && !girder.reinf_material && !girder.reinforcing, "the actual girder starts in ordinary anchored plating mode")
	TEST_ASSERT_EQUAL(girder.girder_material, steel, "the actual support girder has its declared steel material")
	TEST_ASSERT(user.put_in_active_hand(sheets), "the actor holds the real wall-plating sheets")
	TEST_ASSERT(!user.incapacitated(), "the actual actor is capable of construction")
	test_op_handler(girder, "interaction_item", user, sheets)
	TEST_ASSERT(LAZYLEN(user.do_afters), "the real material interaction starts a timed wall-plating action")
	TEST_ASSERT_EQUAL(sheets.get_amount(), start_amount, "starting actual plating consumes no sheet early")
	scheduler_advance((2 SECONDS) / (1 SECOND))
	TEST_ASSERT(!QDELETED(girder), "the original girder remains before the real plating deadline")
	var/turf/pending_floor = locate(tile_x, tile_y, tile_z)
	TEST_ASSERT_NOTNULL(pending_floor, "the original floor coordinate still resolves before the real plating deadline")
	TEST_ASSERT_EQUAL(pending_floor.type, original_floor_type, "pending plating has not replaced the original floor early")
	TEST_ASSERT_EQUAL(sheets.get_amount(), start_amount, "pending actual plating consumes no sheet early")
	if(deplete_while_waiting)
		TEST_ASSERT(sheets.use(1), "another actual stack use consumes one of the held sheets while plating waits")
	scheduler_advance((3 SECONDS) / (1 SECOND))
	TEST_ASSERT(!LAZYLEN(user.do_afters), "actual plating releases its pending timed action")
	TEST_ASSERT(!user.incapacitated(), "the actual safe actor remains capable through construction")
	var/turf/current = locate(tile_x, tile_y, tile_z)
	if(deplete_while_waiting)
		TEST_ASSERT(!QDELETED(girder), "insufficient sheets at actual completion preserve the original girder")
		TEST_ASSERT_EQUAL(current.type, original_floor_type, "insufficient sheets create no wall or floor replacement")
		TEST_ASSERT_EQUAL(sheets.get_amount(), 1, "failed plating preserves the exact remaining sheet after the independent stack use")
		TEST_ASSERT_EQUAL(user.get_active_hand(), sheets, "failed plating preserves the actual remaining held sheet")
		return
	own_turf_contents(current)
	TEST_ASSERT(QDELETED(girder), "actual completed plating consumes the original support girder")
	TEST_ASSERT(istype(current, /turf/simulated/wall), "actual completed plating replaces the original floor with a wall")
	var/turf/simulated/wall/wall = current
	TEST_ASSERT_EQUAL(wall.material, steel, "the actual wall uses the original steel sheets as outer material")
	TEST_ASSERT_EQUAL(wall.girder_material, steel, "the actual wall preserves the original girder material")
	TEST_ASSERT_NULL(wall.reinf_material, "ordinary plating adds no invented reinforcement")
	TEST_ASSERT(!wall.can_open, "plating an anchored support creates an ordinary wall rather than a false wall")
	TEST_ASSERT_EQUAL(sheets.get_amount(), 1, "actual completed plating spends exactly two of the original three sheets")
	TEST_ASSERT_EQUAL(user.get_active_hand(), sheets, "actual completed plating preserves the exact remaining held stack")
	wall.dismantle_wall()
	current = locate(tile_x, tile_y, tile_z)
	own_turf_contents(current)
	TEST_ASSERT(istype(current, /turf/simulated/floor/plating), "actual wall dismantling restores plating")
	var/list/recovered_girders = contents_of(current, /obj/structure/girder)
	TEST_ASSERT_EQUAL(length(recovered_girders), 1, "the constructed wall returns exactly one real support girder")
	var/obj/structure/girder/recovered = recovered_girders[1]
	TEST_ASSERT_EQUAL(recovered.girder_material, steel, "the recovered real support preserves its original material")
	var/refund_amount = 0
	for(var/obj/item/stack/material/refund as anything in contents_of(current, /obj/item/stack/material))
		TEST_ASSERT(istype(refund, /obj/item/stack/material/steel), "the real refund contains only original outer steel material")
		refund_amount += refund.get_amount()
	TEST_ASSERT_EQUAL(refund_amount, 2, "actual dismantling refunds exactly the two sheets spent by real plating")
	TEST_ASSERT_EQUAL(sheets.get_amount() + refund_amount, start_amount, "the actual construction and dismantling round trip conserves the original sheet allowance")
