// The timed sequences built on after() (code/datums/om/after_helpers.dm): each step lands on its own deadline, in order.

/datum/unit_test/dq_after_sequences
	abstract_type = /datum/unit_test/dq_after_sequences

/datum/unit_test/dq_after_sequences/dir_sequence

/datum/unit_test/dq_after_sequences/dir_sequence/Run()
	test_driver_begin()
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	var/obj/item/thing = allocate(/obj/item, test_floor())
	thing.dir = WEST
	thing.dir_sequence(list(NORTH, EAST, SOUTH), 2)
	TEST_ASSERT_EQUAL(thing.dir, WEST, "nothing turns before the first deadline")
	test_time(1)
	TEST_ASSERT_EQUAL(thing.dir, NORTH, "the first step turns at once")
	test_time(2)
	TEST_ASSERT_EQUAL(thing.dir, EAST, "the second step turns one interval later")
	test_time(2)
	TEST_ASSERT_EQUAL(thing.dir, SOUTH, "the third step turns one interval after that")

/datum/unit_test/dq_after_sequences/color_sequence

/datum/unit_test/dq_after_sequences/color_sequence/Run()
	test_driver_begin()
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	var/obj/item/thing = allocate(/obj/item, test_floor())
	thing.color_sequence(list("#ff0000", "#00ff00", "#0000ff"), 3)
	test_time(1)
	TEST_ASSERT_EQUAL(thing.color, "#ff0000", "the first colour shows at once")
	test_time(3)
	TEST_ASSERT_EQUAL(thing.color, "#00ff00", "the second colour one interval later")
	test_time(3)
	TEST_ASSERT_EQUAL(thing.color, "#0000ff", "the third colour one interval after that")

/datum/unit_test/dq_after_sequences/scatter_steps

/datum/unit_test/dq_after_sequences/scatter_steps/Run()
	test_driver_begin()
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	var/turf/start = test_floor()
	var/obj/item/thing = allocate(/obj/item, start)
	thing.scatter_steps(3)
	test_time(20)
	TEST_ASSERT(!QDELETED(thing), "scattering does not delete the thing")
	TEST_ASSERT(get_dist(thing, start) <= 3, "three steps carry it at most three tiles")
	// A step with its owner gone is dropped, not run.
	var/obj/item/doomed = allocate(/obj/item, start)
	doomed.scatter_steps(2)
	qdel(doomed)
	test_time(20)
