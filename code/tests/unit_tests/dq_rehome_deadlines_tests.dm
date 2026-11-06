// scheduler_rehome() (code/engine/time/records.dm) moves a record's non-timer deadlines to the scheduler that is current now: a min_interval
// throttle release and a keyed (pipeline stage style, DEADLINE_SUB_STAGE + n) rewake. An entity first touched on the live clock and then used under a test
// driver's injected clock must see both fire once, at the remaining time, and not before.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/datum/engine_test_entity/rehome_probe
	var/list/wake_times
	var/list/keyed_times

/datum/scheduled_behaviour/dq_rehome_probe
	name = "dq_rehome_probe"
	wake_on = CHANGE_EXPLICIT
	min_interval = 3 SECONDS

/datum/scheduled_behaviour/dq_rehome_probe/on_wake(datum/E, changes)
	var/datum/engine_test_entity/rehome_probe/P = E
	if(istype(P))
		LAZYADD(P.wake_times, time_scheduler().now())

/datum/scheduled_behaviour/dq_rehome_probe/on_keyed_deadline(datum/E, sub)
	var/datum/engine_test_entity/rehome_probe/P = E
	if(istype(P) && sub == DEADLINE_SUB_STAGE)
		LAZYADD(P.keyed_times, time_scheduler().now())

/datum/unit_test/dq_rehome_moves_throttle_and_keyed_deadlines/Run()
	var/datum/engine_test_entity/rehome_probe/E = allocate(/datum/engine_test_entity/rehome_probe)
	var/datum/scheduled_behaviour/dq_rehome_probe/B = definition_registry().behaviour(/datum/scheduled_behaviour/dq_rehome_probe)
	TEST_ASSERT(B, "The probe behaviour is registered")
	var/datum/scheduler_record/rec = scheduler_record_of(E)
	TEST_ASSERT(rec && rec.sched == time_scheduler(), "The entity first joins the scheduler that is current before the test clock")
	TEST_ASSERT(!kernel_test_active(), "No test clock is running when the entity joins")
	var/datum/time_scheduler/live = rec.sched
	entity_attach(E, B)
	var/i = rec.att.Find(B)
	TEST_ASSERT(i, "The probe is attached")
	// A wake, then a second inside the interval: the second is held behind a throttle deadline.
	TEST_ASSERT(!scheduler_throttled(rec, B, i, CHANGE_EXPLICIT), "The first wake is not throttled")
	TEST_ASSERT(scheduler_throttled(rec, B, i, CHANGE_EXPLICIT), "A wake inside the interval is deferred")
	TEST_ASSERT(deadline_deadline_pending(E, B, DEADLINE_SUB_THROTTLE), "The throttle release is a pending deadline")
	TEST_ASSERT(deadline_deadline(E, 5 SECONDS, B, DEADLINE_SUB_STAGE), "A keyed rewake is armed")
	TEST_ASSERT(deadline_deadline_pending(E, B, DEADLINE_SUB_STAGE), "The keyed rewake is pending")

	kernel_test_begin()
	var/datum/time_scheduler/test_sched = time_scheduler()
	TEST_ASSERT(test_sched != live, "The test clock brought its own scheduler")
	// Touching the entity rehomes its record onto the test scheduler.
	TEST_ASSERT_EQUAL(scheduler_record_of(E), rec, "The record is the same one")
	TEST_ASSERT_EQUAL(rec.sched, test_sched, "The touch rehomed the record onto the test scheduler")
	TEST_ASSERT(deadline_deadline_pending(E, B, DEADLINE_SUB_THROTTLE), "The throttle release survived the rehome")
	TEST_ASSERT(deadline_deadline_pending(E, B, DEADLINE_SUB_STAGE), "The keyed rewake survived the rehome")

	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(length(E.wake_times), 0, "The throttled wake has not fired before its remaining time")
	TEST_ASSERT_EQUAL(length(E.keyed_times), 0, "The keyed rewake has not fired before its remaining time")
	test_time(1.5 SECONDS)
	TEST_ASSERT_EQUAL(length(E.wake_times), 1, "The throttled wake fired once after its remaining 3 seconds")
	TEST_ASSERT(E.wake_times[1] >= 3 SECONDS && E.wake_times[1] <= 3.5 SECONDS, "The throttled wake fired at about 3 seconds (was [E.wake_times[1]])")
	TEST_ASSERT_EQUAL(length(E.keyed_times), 0, "The keyed rewake still waits at 3.5 seconds")
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(length(E.keyed_times), 1, "The keyed rewake fired once after its remaining 5 seconds")
	TEST_ASSERT(E.keyed_times[1] >= 5 SECONDS && E.keyed_times[1] <= 5.5 SECONDS, "The keyed rewake fired at about 5 seconds (was [E.keyed_times[1]])")
	test_time(5 SECONDS)
	TEST_ASSERT_EQUAL(length(E.wake_times), 1, "The throttled wake did not fire again")
	TEST_ASSERT_EQUAL(length(E.keyed_times), 1, "The keyed rewake did not fire again")
	kernel_test_end()

#endif
