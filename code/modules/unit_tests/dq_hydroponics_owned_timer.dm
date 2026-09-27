/obj/machinery/portable_atmospherics/hydroponics/owned_timer_test
	mechanical = FALSE
	var/wake_hits = 0

/obj/machinery/portable_atmospherics/hydroponics/owned_timer_test/wake_for_growth()
	growth_timer = null
	wake_hits++

/datum/unit_test/dq_hydroponics_owned_growth_timer
	needs_test_block = FALSE

/datum/unit_test/dq_hydroponics_owned_growth_timer/Run()
	var/obj/machinery/portable_atmospherics/hydroponics/owned_timer_test/tray = new(locate(1, 1, 1))
	STOP_MACHINE_PROCESSING(tray)
	tray.lastcycle = world.time
	tray.cycledelay = 2 * world.tick_lag
	tray.schedule_growth_wake()
	var/datum/object_model/schedule_entry/first = tray.growth_timer
	TEST_ASSERT(first && om_owner(first) == tray, "growth wake is not owned by the tray")
	tray.schedule_growth_wake()
	TEST_ASSERT(tray.growth_timer == first, "repeated growth wake scheduled another timer")
	sleep(2 SECONDS)
	TEST_ASSERT_EQUAL(tray.wake_hits, 1, "growth wake did not fire exactly once")
	TEST_ASSERT(!tray.growth_timer, "growth wake did not clear its completed timer")
	tray.cycledelay = 10 * world.tick_lag
	tray.lastcycle = world.time
	tray.schedule_growth_wake()
	var/datum/object_model/schedule_entry/second = tray.growth_timer
	TEST_ASSERT(second && om_owner(second) == tray, "second growth wake is not owned by the tray")
	qdel(tray)
	TEST_ASSERT(QDELETED(second), "growth wake survived tray destruction")
