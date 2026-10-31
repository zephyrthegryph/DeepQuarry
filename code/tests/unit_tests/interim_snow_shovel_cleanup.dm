/// Real shovel entry consumes snow only at its uninterrupted four-second deadline.
/datum/unit_test/interim_snow_shovel_cleanup
	var/snow_type = /obj/effect/overlay/snow
	var/interrupted = FALSE

/datum/unit_test/interim_snow_shovel_cleanup/floor
	snow_type = /obj/effect/overlay/snow/floor

/datum/unit_test/interim_snow_shovel_cleanup/wall
	snow_type = /obj/effect/overlay/snow/wall

/datum/unit_test/interim_snow_shovel_cleanup/interrupted
	interrupted = TRUE

/datum/unit_test/interim_snow_shovel_cleanup/Run()
	test_driver_begin()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/item/shovel/shovel = allocate(/obj/item/shovel, T)
	var/obj/effect/overlay/snow/snow = allocate(snow_type, T)
	TEST_ASSERT(!QDELETED(snow), "actual snow overlay initializes alive")
	TEST_ASSERT_EQUAL(snow.loc, T, "actual snow overlay starts on the fixture floor")
	TEST_ASSERT(user.put_in_active_hand(shovel), "actual actor holds the registered shovel item")
	perform_op(user, snow, "shovel_snow", shovel)
	TEST_ASSERT(length(op_pendings_of(user)) > 0, "actual shovel entry starts its timed snow clearing")
	TEST_ASSERT(!QDELETED(snow), "actual snow clearing preserves its source immediately")
	test_time(3 SECONDS)
	TEST_ASSERT(!QDELETED(snow), "actual snow remains before the four-second deadline")
	TEST_ASSERT_EQUAL(snow.loc, T, "actual pending shoveling preserves the original snow floor")
	if(interrupted)
		var/turf/away = get_step(get_step(T, EAST), EAST)
		TEST_ASSERT(away, "actual cancellation fixture has a floor outside snow reach")
		user.forceMove(away)
	test_time(1 SECOND)
	if(interrupted)
		TEST_ASSERT(!QDELETED(snow), "actual actor movement cancels snow clearing without consuming its source")
		TEST_ASSERT_EQUAL(snow.loc, T, "actual canceled shoveling preserves the original snow floor")
		var/list/survivors = contents_of(T, /obj/effect/overlay/snow)
		TEST_ASSERT_EQUAL(length(survivors), 1, "actual canceled shoveling preserves exactly the original overlay")
		TEST_ASSERT_EQUAL(survivors[1], snow, "actual canceled overlay retains its original identity")
	else
		TEST_ASSERT(QDELETED(snow), "actual uninterrupted four-second shoveling consumes the original overlay")
		TEST_ASSERT_EQUAL(length(contents_of(T, /obj/effect/overlay/snow)), 0, "actual completed shoveling leaves no snow overlay")
	TEST_ASSERT(!QDELETED(user) && !QDELETED(shovel), "actual snow cleanup preserves its actor and tool")
	TEST_ASSERT_EQUAL(user.get_active_hand(), shovel, "actual snow cleanup preserves its held shovel")
