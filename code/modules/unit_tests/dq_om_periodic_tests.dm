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

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// Machines that used to poll forever (roadmap S5): idle, each one's step says it has nothing to
/// do, and its producer gives it work again.
/datum/unit_test/dq_om_idle_machines_sleep

/datum/unit_test/dq_om_idle_machines_sleep/Run()
	var/turf/T = test_floor()

	var/obj/machinery/igniter/igniter = allocate(/obj/machinery/igniter, T)
	igniter.on = FALSE
	TEST_ASSERT_EQUAL(igniter.machine_step(), PROCESS_KILL, "a switched-off igniter kept stepping")
	MACHINE_SLEEP(igniter)
	igniter.interaction_toggle(null, null, null)
	TEST_ASSERT(igniter.on && machine_stepping(igniter), "switching an igniter on did not wake it")
	igniter.on = FALSE

	var/obj/machinery/feeder/feeder = allocate(/obj/machinery/feeder, T)
	TEST_ASSERT_EQUAL(feeder.machine_step(), PROCESS_KILL, "an unattached feeder kept stepping")

	var/obj/machinery/pump/pump = allocate(/obj/machinery/pump, T)
	pump.on = FALSE
	TEST_ASSERT_EQUAL(pump.machine_step(), PROCESS_KILL, "a switched-off reagent pump kept stepping")

	var/obj/machinery/bunsen_burner/bunsen = allocate(/obj/machinery/bunsen_burner, T)
	TEST_ASSERT_EQUAL(bunsen.machine_step(), PROCESS_KILL, "a cold bunsen burner kept stepping")

	var/obj/machinery/vitals_monitor/vitals = allocate(/obj/machinery/vitals_monitor, T)
	TEST_ASSERT_EQUAL(vitals.machine_step(), PROCESS_KILL, "an unattached vitals monitor kept stepping")

	var/obj/machinery/door_timer/brig = allocate(/obj/machinery/door_timer, T)
	TEST_ASSERT_EQUAL(brig.machine_step(), PROCESS_KILL, "an idle brig timer kept stepping")

	var/obj/machinery/particle_accelerator/control_box/pa = allocate(/obj/machinery/particle_accelerator/control_box, T)
	TEST_ASSERT_EQUAL(pa.machine_step(), PROCESS_KILL, "an inactive particle accelerator kept stepping")

	var/obj/machinery/suspension_gen/suspension = allocate(/obj/machinery/suspension_gen, T)
	TEST_ASSERT_EQUAL(suspension.machine_step(), PROCESS_KILL, "an inactive suspension generator kept stepping")

	var/obj/machinery/radiocarbon_spectrometer/spectrometer = allocate(/obj/machinery/radiocarbon_spectrometer, T)
	TEST_ASSERT_EQUAL(spectrometer.machine_step(), PROCESS_KILL, "an idle spectrometer kept stepping")

	var/obj/machinery/dnaforensics/dna = allocate(/obj/machinery/dnaforensics, T)
	TEST_ASSERT_EQUAL(dna.machine_step(), PROCESS_KILL, "an idle DNA scanner kept stepping")

	var/obj/machinery/casino_prize_dispenser/casino = allocate(/obj/machinery/casino_prize_dispenser, T)
	TEST_ASSERT_EQUAL(casino.machine_step(), PROCESS_KILL, "a prize dispenser kept stepping")

	// A refinery pipe steps only while reagents move through it.
	var/obj/machinery/reagent_refinery/pipe/pipe = allocate(/obj/machinery/reagent_refinery/pipe, T)
	TEST_ASSERT_EQUAL(pipe.machine_step(), PROCESS_KILL, "an empty refinery pipe kept stepping")
	MACHINE_SLEEP(pipe)
	pipe.reagents.add_reagent(REAGENT_ID_WATER, 10)
	TEST_ASSERT(machine_stepping(pipe), "reagents arriving did not wake a refinery pipe")
	TEST_ASSERT_EQUAL(pipe.machine_step(), PROCESS_KILL, "a refinery pipe with nowhere to send its reagents kept stepping")

	// A door timer counts down only while timing, and wakes when started.
	MACHINE_SLEEP(brig)
	brig.stat &= ~(NOPOWER|BROKEN)
	brig.set_timer(1 MINUTE)
	brig.timer_start()
	TEST_ASSERT(machine_stepping(brig), "starting a brig timer did not wake it")
	TEST_ASSERT_NOTEQUAL(brig.machine_step(), PROCESS_KILL, "a timing brig timer stopped counting")
	brig.timer_end()
	TEST_ASSERT_EQUAL(brig.machine_step(), PROCESS_KILL, "a finished brig timer kept stepping")

/// A machine that ended its work for lack of power resumes when power returns, and the audit
/// sees it as idle only while it is unpowered.
/datum/unit_test/dq_om_machine_sleeps_until_powered

/datum/unit_test/dq_om_machine_sleeps_until_powered/Run()
	var/obj/machinery/igniter/igniter = allocate(/obj/machinery/igniter, test_floor())
	var/P = /datum/om/pipeline/machine
	var/datum/om/stage/machine/step/stage = om_registry().stage_by_type[/datum/om/stage/machine/step]
	igniter.on = TRUE
	igniter.stat |= NOPOWER
	MACHINE_WAKE(igniter)
	om_run_frame_now(igniter, P)
	TEST_ASSERT(!igniter.step_active && igniter.step_waiting_power, "an unpowered igniter did not wait for power")
	TEST_ASSERT(stage.idle(igniter), "an unpowered waiting machine is not idle")
	igniter.stat &= ~NOPOWER
	TEST_ASSERT(!stage.idle(igniter), "a powered waiting machine still looks idle to the audit")
	om_changed(igniter, CHANGE_MACHINE_POWER)
	igniter.om_rec.sched.run_pass(1e9)
	om_run_frame_now(igniter, P)
	TEST_ASSERT(igniter.step_active, "power returning did not restart its work")
	igniter.on = FALSE

#endif

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// Alarm handlers (was SSalarm): a raised alarm starts its handler on the slow lane; with no alarm
/// left it stops, and an idle handler never runs.
/datum/unit_test/dq_om_alarm_handler_park_wake

/datum/unit_test/dq_om_alarm_handler_park_wake/Run()
	var/datum/alarm_handler/AH = GLOB.power_alarm
	var/obj/item/origin = allocate(/obj/item, test_floor())
	if(!length(AH.alarms))
		PERIODIC_STOP(AH)
	AH.triggerAlarm(origin, origin, duration = 1)
	TEST_ASSERT(AH.periodic_pipe == PERIODIC_SLOW, "raising an alarm did not start its handler")
	AH.clearAlarm(origin, origin)
	if(!length(AH.alarms))
		TEST_ASSERT_EQUAL(AH.periodic_step(20), PROCESS_KILL, "a handler with no alarms kept stepping")

#endif

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// The missed-wake audits find nothing on the test map: every parked pipeline entity is idle by its
/// own rule, and every sleeper on timers and keys is asleep for a reason.
/datum/unit_test/dq_om_audit_finds_no_missed_wakes

/datum/unit_test/dq_om_audit_finds_no_missed_wakes/Run()
	react_test_ticks(10)
	var/list/missed = om_pipeline_audit(null, 100000, 100000, TRUE)
	var/list/names = list()
	for(var/datum/om/stage/T as anything in missed)
		names |= "[T.type]"
	TEST_ASSERT(!length(missed), "the pipeline audit found missed wakes: [jointext(names, ", ")]")
	var/list/woken = om_woken_audit(100000, FALSE)
	TEST_ASSERT(!length(woken), "the timer/key audit found sleepers with work: [jointext(woken, "; ")]")

/// Tanning racks and modular computers sleep when idle and wake on their producer.
/datum/unit_test/dq_om_idle_items_sleep

/datum/unit_test/dq_om_idle_items_sleep/Run()
	var/obj/structure/tanning_rack/rack = allocate(/obj/structure/tanning_rack, test_floor())
	TEST_ASSERT_EQUAL(rack.periodic_step(20), PROCESS_KILL, "an empty tanning rack kept stepping")
	var/obj/item/modular_computer/tablet/T = allocate(/obj/item/modular_computer/tablet, test_floor())
	T.enabled = FALSE
	TEST_ASSERT_EQUAL(T.periodic_step(20), PROCESS_KILL, "a switched-off computer kept stepping")
	PERIODIC_STOP(T)
	T.enable_computer()
	TEST_ASSERT(T.periodic_pipe == PERIODIC_SLOW, "switching a computer on did not start it")
	T.enabled = FALSE

#endif

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// A mob holder dropped on a turf lets its mob go right after the move, with no polling.
/datum/unit_test/dq_om_holder_cleans_up_on_drop

/datum/unit_test/dq_om_holder_cleans_up_on_drop/Run()
	var/turf/T = test_floor()
	var/mob/living/M = allocate(/mob/living, T)
	var/obj/item/holder/H = new(T, M)
	TEST_ASSERT(!H.periodic_pipe, "a holder polls on a lane")
	react_test_ticks(4)
	TEST_ASSERT(QDELETED(H), "a holder left on a turf was not cleaned up")
	TEST_ASSERT_EQUAL(M.loc, T, "the held mob was not released onto the turf")

#endif
