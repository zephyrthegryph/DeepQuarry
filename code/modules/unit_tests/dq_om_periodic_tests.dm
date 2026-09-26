// Park/wake tests for the pollers moved onto object-model pipelines (roadmap S3-S5,
// code/datums/om/periodic.dm, code/game/machinery/machine_pipeline.dm): periodic work runs only
// between its start and its end, parks in between, and the missed-wake audit finds nothing.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// A periodic user with `work` frames left to do.
/datum/dq_periodic_probe
	var/work = 0
	var/steps = 0
	var/last_delta

/datum/dq_periodic_probe/periodic_step(delta)
	steps++
	last_delta = delta
	if(--work <= 0)
		return PROCESS_KILL

/// PERIODIC_START runs periodic_step() every frame until it returns PROCESS_KILL; the entity then
/// idles and parks, PERIODIC_START wakes it again, PERIODIC_STOP ends the work early, and the
/// audit never sees a missed wake.
/datum/unit_test/dq_om_periodic_park_wake

/datum/unit_test/dq_om_periodic_park_wake/Run()
	var/datum/dq_periodic_probe/D = allocate(/datum/dq_periodic_probe)
	var/P = PERIODIC_SLOW
	D.work = 2
	PERIODIC_START(D, P)
	TEST_ASSERT(om_attached(D, P), "PERIODIC_START did not put it on the pipeline")
	TEST_ASSERT(PERIODIC_RUNNING(D) && (D.datum_flags & DF_ISPROCESSING), "a started entity is not marked running")
	for(var/i in 1 to 2)
		om_run_frame_now(D, P)
	TEST_ASSERT_EQUAL(D.steps, 2, "it did not step once per frame while it had work")
	TEST_ASSERT_EQUAL(D.last_delta, 20, "the slow lane passes the old SSobj delta")
	TEST_ASSERT(!PERIODIC_RUNNING(D), "PROCESS_KILL did not end the work")
	for(var/i in 1 to 3)
		om_run_frame_now(D, P)
	TEST_ASSERT_EQUAL(D.steps, 2, "it stepped with no work")
	TEST_ASSERT(om_pipe_parked(D, P), "an entity with no work did not park")
	TEST_ASSERT(!length(om_pipeline_audit(null, 400, 100, TRUE)), "the audit reported a missed wake")

	D.work = 5
	PERIODIC_START(D, P)
	D.om_rec.sched.run_pass(1e9)
	TEST_ASSERT(!om_pipe_parked(D, P), "PERIODIC_START did not unpark it")
	om_run_frame_now(D, P)
	TEST_ASSERT_EQUAL(D.steps, 3, "a woken entity did not step")
	PERIODIC_STOP(D)
	for(var/i in 1 to 3)
		om_run_frame_now(D, P)
	TEST_ASSERT_EQUAL(D.steps, 3, "PERIODIC_STOP did not end the work")
	TEST_ASSERT(om_pipe_parked(D, P), "a stopped entity did not park")

	// Moving to another lane leaves the first one idle, not missed.
	D.work = 5
	PERIODIC_START(D, PERIODIC_FAST)
	om_run_frame_now(D, P)
	TEST_ASSERT_EQUAL(D.steps, 3, "the old lane kept stepping after a move")
	om_run_frame_now(D, PERIODIC_FAST)
	TEST_ASSERT_EQUAL(D.steps, 4, "the new lane did not step")
	TEST_ASSERT_EQUAL(D.last_delta, 2, "the fast lane passes the old SSfastprocess delta")
	PERIODIC_STOP(D)

/// A machine with explicitly started work (the old START_MACHINE_PROCESSING contract).
/obj/machinery/dq_step_probe
	var/work = 0
	var/steps = 0

/obj/machinery/dq_step_probe/machine_step()
	steps++
	if(--work <= 0)
		return PROCESS_KILL

/// MACHINE_WAKE runs machine_step() every machine frame until it returns PROCESS_KILL; the machine
/// then parks, channels alone don't restart it, and MACHINE_WAKE/MACHINE_SLEEP start and end it.
/datum/unit_test/dq_om_machine_step_park_wake

/datum/unit_test/dq_om_machine_step_park_wake/Run()
	var/obj/machinery/dq_step_probe/M = allocate(/obj/machinery/dq_step_probe, test_floor())
	var/P = /datum/om/pipeline/machine
	TEST_ASSERT(!om_attached(M, P), "a machine with no work joined the pipeline at Initialize")
	M.work = 2
	MACHINE_WAKE(M)
	TEST_ASSERT(machine_stepping(M), "MACHINE_WAKE gave it no step work")
	for(var/i in 1 to 2)
		om_run_frame_now(M, P)
	TEST_ASSERT_EQUAL(M.steps, 2, "it did not step once per frame while it had work")
	TEST_ASSERT(!machine_stepping(M), "PROCESS_KILL did not end its step work")
	for(var/i in 1 to 3)
		om_run_frame_now(M, P)
	TEST_ASSERT_EQUAL(M.steps, 2, "it stepped with no work")
	TEST_ASSERT(om_pipe_parked(M, P), "a machine with no work did not park")
	M.work = 5
	om_changed(M, CHANGE_MACHINE_POWER)
	M.om_rec.sched.run_pass(1e9)
	for(var/i in 1 to 2)
		om_run_frame_now(M, P)
	TEST_ASSERT_EQUAL(M.steps, 2, "a power change restarted work nothing started")
	MACHINE_WAKE(M)
	M.om_rec.sched.run_pass(1e9)
	om_run_frame_now(M, P)
	TEST_ASSERT_EQUAL(M.steps, 3, "MACHINE_WAKE did not restart it")
	MACHINE_SLEEP(M)
	om_run_frame_now(M, P)
	TEST_ASSERT_EQUAL(M.steps, 3, "MACHINE_SLEEP did not end its work")
	TEST_ASSERT(!length(om_pipeline_audit(null, 400, 100, TRUE)), "the audit reported a missed wake")

/// A machine in fast mode steps on the fast lane, not the machine pipeline.
/datum/unit_test/dq_om_machine_fast_lane

/datum/unit_test/dq_om_machine_fast_lane/Run()
	var/obj/machinery/dq_step_probe/M = allocate(/obj/machinery/dq_step_probe, test_floor())
	M.work = 10
	MACHINE_WAKE(M)
	M.speed_process = TRUE
	PERIODIC_START(M, PERIODIC_FAST)
	om_run_frame_now(M, /datum/om/pipeline/machine)
	TEST_ASSERT_EQUAL(M.steps, 0, "a fast machine stepped on the machine pipeline")
	om_run_frame_now(M, PERIODIC_FAST)
	TEST_ASSERT_EQUAL(M.steps, 1, "a fast machine did not step on the fast lane")
	M.speed_process = FALSE
	PERIODIC_STOP(M)

/// om keys and timers: a subscriber wakes on a publish sharing a mask bit and not otherwise;
/// a timer fires once; unsubscribing drops the key.
/datum/unit_test/dq_om_keys_and_timers

/datum/unit_test/dq_om_keys_and_timers/Run()
	var/datum/om_wake_test_subscriber/S = allocate(/datum/om_wake_test_subscriber)
	var/token = OM_KEY_ON(S, KEY_METEORS, 77, 2)
	TEST_ASSERT(token, "subscribing returned no token")
	om_woken_trace(S)
	OM_KEY_PUBLISH(KEY_METEORS, 77, 1)
	react_test_ticks(4)
	TEST_ASSERT_EQUAL(om_woken_traced_count(S), 0, "a publish with no shared mask bit woke the subscriber")
	OM_KEY_PUBLISH(KEY_METEORS, 77, 2)
	react_test_ticks(4)
	TEST_ASSERT(om_woken_traced_count(S) >= 1, "a matching publish did not wake the subscriber")
	TEST_ASSERT((S.wakes[length(S.wakes)] & OM_WOKEN_KEY), "a key wake did not say it was a key")
	OM_KEY_OFF(S, token)
	TEST_ASSERT(!GLOB.om_keys["[KEY_METEORS]:77"], "the last unsubscribe left the key behind")
	var/before = om_woken_traced_count(S)
	OM_KEY_PUBLISH(KEY_METEORS, 77, 2)
	react_test_ticks(4)
	TEST_ASSERT_EQUAL(om_woken_traced_count(S), before, "an unsubscribed datum woke")

	OM_WAKE_AT(S, world.time + 1)
	TEST_ASSERT(om_wake_pending(S), "the timer is not pending")
	react_test_ticks(8)
	TEST_ASSERT(om_woken_traced_count(S) == before + 1, "the timer did not fire exactly once")
	TEST_ASSERT((S.wakes[length(S.wakes)] & OM_WOKEN_TIMER), "a timer wake did not say it was a timer")
	TEST_ASSERT(!om_wake_pending(S), "a fired timer is still pending")
	om_woken_untrace(S)

#endif
