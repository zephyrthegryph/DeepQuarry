/// Real shovel filling consumes a growplot only after its uninterrupted three-second task.
/datum/unit_test/interim_soil_fill_cleanup
	var/interrupted = FALSE

/datum/unit_test/interim_soil_fill_cleanup/interrupted
	interrupted = TRUE

/datum/unit_test/interim_soil_fill_cleanup/Run()
	test_driver_begin()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/item/shovel/shovel = allocate(/obj/item/shovel, T)
	var/obj/machinery/portable_atmospherics/hydroponics/soil/soil = allocate(/obj/machinery/portable_atmospherics/hydroponics/soil, T)
	TEST_ASSERT(!QDELETED(soil), "actual soil growplot initializes alive")
	TEST_ASSERT(user.put_in_active_hand(shovel), "real actor holds the actual filling shovel")
	user.set_use_stance(I_HURT)
	user.next_click = 0
	test_click(user, soil, shovel)
	TEST_ASSERT(!QDELETED(soil), "starting the real fill task preserves the growplot immediately")
	if(interrupted)
		var/turf/away = get_step(get_step(T, EAST), EAST)
		TEST_ASSERT(away, "actual cancellation fixture has a destination outside reach")
		user.forceMove(away)
	test_time(2 SECONDS)
	TEST_ASSERT(!QDELETED(soil), "actual growplot remains before its three-second fill deadline")
	test_time(1 SECOND)
	if(interrupted)
		TEST_ASSERT(!QDELETED(soil), "actual actor movement outside reach cancels filling without consuming the growplot")
		TEST_ASSERT_EQUAL(soil.loc, T, "canceled actual filling preserves the original growplot floor")
		TEST_ASSERT_EQUAL(length(contents_of(T, /obj/machinery/portable_atmospherics/hydroponics/soil)), 1, "canceled filling preserves exactly the original soil growplot")
	else
		TEST_ASSERT(QDELETED(soil), "actual uninterrupted three-second filling consumes the original growplot")
		TEST_ASSERT_EQUAL(length(contents_of(T, /obj/machinery/portable_atmospherics/hydroponics/soil)), 0, "successful actual filling leaves no soil growplot")
	TEST_ASSERT(!QDELETED(user) && !QDELETED(shovel), "actual fill cleanup preserves its actor and tool")
	TEST_ASSERT_EQUAL(user.get_active_hand(), shovel, "actual fill cleanup preserves the original held shovel")
