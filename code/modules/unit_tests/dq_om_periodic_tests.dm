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

/// om_task_periodic() runs periodic_step() every frame until it returns PROCESS_KILL; the entity then
/// idles and parks, om_task_periodic() wakes it again, om_task_periodic_stop() ends the work early, and the
/// audit never sees a missed wake.
/datum/unit_test/dq_om_periodic_park_wake

/datum/unit_test/dq_om_periodic_park_wake/Run()
	var/datum/dq_periodic_probe/D = allocate(/datum/dq_periodic_probe)
	var/P = PERIODIC_SLOW
	D.work = 2
	om_task_periodic(D, P)
	TEST_ASSERT(om_attached(D, P), "om_task_periodic() did not put it on the pipeline")
	TEST_ASSERT(om_task_periodic_running(D) && (D.datum_flags & DF_ISPROCESSING), "a started entity is not marked running")
	for(var/i in 1 to 2)
		om_run_frame_now(D, P)
	TEST_ASSERT_EQUAL(D.steps, 2, "it did not step once per frame while it had work")
	TEST_ASSERT_EQUAL(D.last_delta, 20, "the slow lane passes the old SSobj delta")
	TEST_ASSERT(!om_task_periodic_running(D), "PROCESS_KILL did not end the work")
	for(var/i in 1 to 3)
		om_run_frame_now(D, P)
	TEST_ASSERT_EQUAL(D.steps, 2, "it stepped with no work")
	TEST_ASSERT(om_pipe_parked(D, P), "an entity with no work did not park")
	TEST_ASSERT(!length(om_pipeline_audit(null, 400, 100, TRUE)), "the audit reported a missed wake")

	D.work = 5
	om_task_periodic(D, P)
	D.om_rec.sched.run_pass(1e9)
	TEST_ASSERT(!om_pipe_parked(D, P), "om_task_periodic() did not unpark it")
	// The pass may already have run the woken entity's slot, depending on where the suite's
	// clock put the ring: measure the explicit frame from what the pass left.
	var/after_pass = D.steps
	TEST_ASSERT(after_pass <= 3, "the pass stepped a woken entity more than once")
	om_run_frame_now(D, P)
	TEST_ASSERT_EQUAL(D.steps, after_pass + 1, "a woken entity did not step")
	om_task_periodic_stop(D)
	var/stopped_at = D.steps
	for(var/i in 1 to 3)
		om_run_frame_now(D, P)
	TEST_ASSERT_EQUAL(D.steps, stopped_at, "om_task_periodic_stop() did not end the work")
	TEST_ASSERT(om_pipe_parked(D, P), "a stopped entity did not park")

	// Moving to another lane leaves the first one idle, not missed.
	D.work = 5
	om_task_periodic(D, PERIODIC_FAST)
	om_run_frame_now(D, P)
	TEST_ASSERT_EQUAL(D.steps, stopped_at, "the old lane kept stepping after a move")
	om_run_frame_now(D, PERIODIC_FAST)
	TEST_ASSERT_EQUAL(D.steps, stopped_at + 1, "the new lane did not step")
	TEST_ASSERT_EQUAL(D.last_delta, 2, "the fast lane passes the old SSfastprocess delta")
	om_task_periodic_stop(D)

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
	M.set_speed_process(TRUE)
	om_task_periodic(M, PERIODIC_FAST)
	om_run_frame_now(M, /datum/om/pipeline/machine)
	TEST_ASSERT_EQUAL(M.steps, 0, "a fast machine stepped on the machine pipeline")
	om_run_frame_now(M, PERIODIC_FAST)
	TEST_ASSERT_EQUAL(M.steps, 1, "a fast machine did not step on the fast lane")
	M.set_speed_process(FALSE)
	om_task_periodic_stop(M)

/// Change channels and timers for sleepers: a watcher wakes on a watched channel and not on
/// another; unwatching stops it; an om_after() timer fires once.
/datum/unit_test/dq_om_keys_and_timers

/datum/proc/dq_om_test_timer_hit()
	return

/datum/unit_test/dq_om_keys_and_timers/Run()
	var/datum/om_wake_test_subscriber/S = allocate(/datum/om_wake_test_subscriber)
	var/datum/source = allocate(/datum)
	om_test_watch(S, source, CHANGE_DATUM_B)
	om_trace(S)
	om_changed(source, CHANGE_DATUM_A)
	om_test_ticks(4)
	TEST_ASSERT_EQUAL(om_traced_count(S), 0, "a change on an unwatched channel woke the watcher")
	om_changed(source, CHANGE_DATUM_B)
	TEST_ASSERT(om_wait_for_wake(S), "a watched channel did not wake the watcher")
	TEST_ASSERT((S.wakes[length(S.wakes)] & CHANGE_RELATED), "a watch wake did not arrive as CHANGE_RELATED")
	om_unwatch(S, source, /datum/om/behaviour/sleeper/test_subscriber)
	var/before = om_traced_count(S)
	om_changed(source, CHANGE_DATUM_B)
	om_test_ticks(4)
	TEST_ASSERT_EQUAL(om_traced_count(S), before, "an unwatched datum woke")

	var/id = om_after(S, 1, /datum/proc/dq_om_test_timer_hit)
	TEST_ASSERT(om_timer_pending(S, id), "the timer is not pending")
	TEST_ASSERT(om_wait_for_wake(S, before), "the timer did not fire")
	om_test_ticks(8)
	TEST_ASSERT(om_traced_count(S) == before + 1, "the timer did not fire exactly once")
	TEST_ASSERT(!om_timer_pending(S, id), "a fired timer is still pending")
	om_untrace(S)

#endif

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// Machines that used to poll forever (roadmap S5): idle, each one's step says it has nothing to
/// do, and its producer gives it work again.
/datum/unit_test/dq_om_idle_machines_sleep

/datum/unit_test/dq_om_idle_machines_sleep/Run()
	var/turf/T = test_floor()

	var/obj/machinery/igniter/igniter = allocate(/obj/machinery/igniter, T)
	igniter.set_on(FALSE)
	TEST_ASSERT(!sys_periodic_allows(igniter, MACHINE_PIPELINE), "a switched-off igniter may still step")
	MACHINE_SLEEP(igniter)
	igniter.interaction_toggle(null, null, null)
	TEST_ASSERT(igniter.on && machine_stepping(igniter), "switching an igniter on did not wake it")
	igniter.set_on(FALSE)

	var/obj/machinery/feeder/feeder = allocate(/obj/machinery/feeder, T)
	TEST_ASSERT(!sys_periodic_allows(feeder, MACHINE_PIPELINE), "an unattached feeder may still step")

	var/obj/machinery/pump/pump = allocate(/obj/machinery/pump, T)
	pump.set_on(FALSE)
	TEST_ASSERT(!sys_periodic_allows(pump, MACHINE_PIPELINE), "a switched-off reagent pump may still step")

	var/obj/machinery/bunsen_burner/bunsen = allocate(/obj/machinery/bunsen_burner, T)
	TEST_ASSERT(!sys_periodic_allows(bunsen, MACHINE_PIPELINE), "a cold bunsen burner may still step")

	var/obj/machinery/vitals_monitor/vitals = allocate(/obj/machinery/vitals_monitor, T)
	TEST_ASSERT(test_machine_idle(vitals), "an unattached vitals monitor kept stepping")

	var/obj/machinery/door_timer/brig = allocate(/obj/machinery/door_timer, T)
	TEST_ASSERT(test_machine_idle(brig), "an idle brig timer kept stepping")

	var/obj/machinery/particle_accelerator/control_box/pa = allocate(/obj/machinery/particle_accelerator/control_box, T)
	TEST_ASSERT(test_machine_idle(pa), "an inactive particle accelerator kept stepping")

	var/obj/machinery/suspension_gen/suspension = allocate(/obj/machinery/suspension_gen, T)
	TEST_ASSERT(!sys_periodic_allows(suspension, MACHINE_PIPELINE), "an inactive suspension generator may still step")

	var/obj/machinery/radiocarbon_spectrometer/spectrometer = allocate(/obj/machinery/radiocarbon_spectrometer, T)
	TEST_ASSERT(!sys_periodic_allows(spectrometer, MACHINE_PIPELINE), "an idle spectrometer may still step")

	var/obj/machinery/dnaforensics/dna = allocate(/obj/machinery/dnaforensics, T)
	TEST_ASSERT(test_machine_idle(dna), "an idle DNA scanner kept stepping")

	var/obj/machinery/casino_prize_dispenser/casino = allocate(/obj/machinery/casino_prize_dispenser, T)
	TEST_ASSERT(test_machine_idle(casino), "a prize dispenser kept stepping")

	// A refinery pipe steps only while reagents move through it.
	var/obj/machinery/reagent_refinery/pipe/pipe = allocate(/obj/machinery/reagent_refinery/pipe, T)
	TEST_ASSERT(test_machine_idle(pipe), "an empty refinery pipe kept stepping")
	MACHINE_SLEEP(pipe)
	pipe.reagents.add_reagent(REAGENT_ID_WATER, 10)
	TEST_ASSERT(machine_stepping(pipe), "reagents arriving did not wake a refinery pipe")
	TEST_ASSERT(test_machine_idle(pipe), "a refinery pipe with nowhere to send its reagents kept stepping")

	// A door timer counts down only while timing, and wakes when started.
	MACHINE_SLEEP(brig)
	brig.stat_remove(NOPOWER|BROKEN)
	brig.set_timer(1 MINUTE)
	brig.timer_start()
	TEST_ASSERT(sys_periodic_allows(brig, MACHINE_PIPELINE), "starting a brig timer did not declare it stepping")
	TEST_ASSERT_NOTEQUAL(brig.machine_step(), PROCESS_KILL, "a timing brig timer stopped counting")
	brig.timer_end()
	TEST_ASSERT(!sys_periodic_allows(brig, MACHINE_PIPELINE), "a finished brig timer kept stepping")

/// A machine that ended its work for lack of power resumes when power returns, and the audit
/// sees it as idle only while it is unpowered.
/datum/unit_test/dq_om_machine_sleeps_until_powered

/datum/unit_test/dq_om_machine_sleeps_until_powered/Run()
	var/obj/machinery/igniter/igniter = allocate(/obj/machinery/igniter, test_floor())
	var/P = /datum/om/pipeline/machine
	var/datum/om/stage/machine/step/stage = om_registry().stage_by_type[/datum/om/stage/machine/step]
	igniter.set_on(TRUE)
	igniter.stat_add(NOPOWER)
	MACHINE_WAKE(igniter)
	igniter.om_rec.sched.run_pass(1e9)
	om_run_frame_now(igniter, P)
	TEST_ASSERT(!igniter.step_active && igniter.step_waiting_power, "an unpowered igniter did not wait for power")
	TEST_ASSERT(stage.idle(igniter), "an unpowered waiting machine is not idle")
	igniter.stat_remove(NOPOWER)
	TEST_ASSERT(!stage.idle(igniter), "a powered waiting machine still looks idle to the audit")
	om_changed(igniter, CHANGE_MACHINE_POWER)
	igniter.om_rec.sched.run_pass(1e9)
	om_run_frame_now(igniter, P)
	TEST_ASSERT(igniter.step_active, "power returning did not restart its work")
	igniter.set_on(FALSE)

#endif

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// Alarm handlers (was SSalarm): a raised alarm starts its handler on the slow lane; with no alarm
/// left it stops, and an idle handler never runs.
/datum/unit_test/dq_om_alarm_handler_park_wake

/datum/unit_test/dq_om_alarm_handler_park_wake/Run()
	var/datum/alarm_handler/AH = GLOB.power_alarm
	var/obj/item/origin = allocate(/obj/item, test_floor())
	if(!length(AH.alarms))
		om_task_periodic_stop(AH)
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
	om_test_ticks(10)
	var/list/missed = om_pipeline_audit(null, 100000, 100000, TRUE)
	var/list/names = list()
	for(var/datum/om/stage/T as anything in missed)
		names |= "[T.type]"
	TEST_ASSERT(!length(missed), "the pipeline audit found missed wakes: [jointext(names, ", ")]")
	var/list/woken = om_sleeper_audit(100000, FALSE)
	TEST_ASSERT(!length(woken), "the timer/key audit found sleepers with work: [jointext(woken, "; ")]")

/// Tanning racks and modular computers sleep when idle and wake on their producer.
/datum/unit_test/dq_om_idle_items_sleep

/datum/unit_test/dq_om_idle_items_sleep/Run()
	var/obj/structure/tanning_rack/rack = allocate(/obj/structure/tanning_rack, test_floor())
	TEST_ASSERT_NULL(rack.periodic_pipe, "an empty tanning rack kept stepping")
	var/obj/item/modular_computer/tablet/T = allocate(/obj/item/modular_computer/tablet, test_floor())
	T.set_enabled(FALSE)
	TEST_ASSERT_NULL(T.periodic_pipe, "a switched-off computer kept stepping")
	TEST_ASSERT(!om_task_periodic(T, PERIODIC_SLOW), "a switched-off computer could be started by hand")
	T.enable_computer()
	TEST_ASSERT(T.periodic_pipe == PERIODIC_SLOW, "switching a computer on did not start it")
	T.set_enabled(FALSE)

#endif

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// A mob holder dropped on a turf lets its mob go right after the move, with no polling.
/datum/unit_test/dq_om_holder_cleans_up_on_drop

/datum/unit_test/dq_om_holder_cleans_up_on_drop/Run()
	var/turf/T = test_floor()
	var/mob/living/M = allocate(/mob/living, T)
	var/obj/item/holder/H = new(T, M)
	TEST_ASSERT(!H.periodic_pipe, "a holder polls on a lane")
	for(var/i in 1 to 40)
		om_test_ticks(1)
		if(QDELETED(H))
			break
	TEST_ASSERT(QDELETED(H), "a holder left on a turf was not cleaned up")
	TEST_ASSERT_EQUAL(M.loc, T, "the held mob was not released onto the turf")

#endif

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// Random events (was SSevents' fire loop, now the event service): an active event steps on the slow lane until it is
/// killed; the event containers keep the random-event clock there.
/datum/unit_test/dq_om_events_on_lanes

/datum/unit_test/dq_om_events_on_lanes/Run()
	var/datum/event_meta/EM = new(EVENT_LEVEL_MUNDANE, "Lane test", /datum/event/nothing, 0, add_to_queue = FALSE)
	var/datum/event/E = new /datum/event/nothing(EM)
	TEST_ASSERT(E.periodic_pipe == PERIODIC_SLOW, "a new event is not on the slow lane")
	E.kill()
	TEST_ASSERT(!om_task_periodic_running(E), "a killed event kept its lane")
	own_remove(GLOB.event_service, nameof(/datum/world_service/events::finished_events), E) // the service owns finished events
	for(var/i = EVENT_LEVEL_MUNDANE to EVENT_LEVEL_MAJOR)
		var/datum/event_container/EC = GLOB.event_service.event_containers[i]
		TEST_ASSERT(EC.periodic_pipe == PERIODIC_SLOW, "event container [i] is not keeping its clock")

/// Shuttles (was SSshuttles' fire loop): a shuttle with work is on the slow lane, an idle one is not.
/datum/unit_test/dq_om_shuttles_on_lanes

/datum/unit_test/dq_om_shuttles_on_lanes/Run()
	for(var/name in SSshuttles.shuttles)
		var/datum/shuttle/S = SSshuttles.shuttles[name]
		if(!(S.shuttle_flags & SHUTTLE_FLAGS_PROCESS))
			continue
		var/working = S.always_process || S.process_state != IDLE_STATE
		TEST_ASSERT_EQUAL(!!S.periodic_pipe, working, "shuttle [name]: lane [S.periodic_pipe] but working [working]")

#endif

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// Planets (was SSplanets' per-planet loop): each planet keeps its clock and weather on the slow lane.
/datum/unit_test/dq_om_planets_on_lanes

/datum/unit_test/dq_om_planets_on_lanes/Run()
	for(var/datum/planet/P as anything in GLOB.planet_service.planets)
		TEST_ASSERT(P.periodic_pipe == PERIODIC_SLOW, "planet [P.name] is not on the slow lane")

#endif

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// Spreading plants (was SSplants' loop) grow on their own lane from add_plant() to remove_plant().
/datum/unit_test/dq_om_plants_on_lane

/datum/unit_test/dq_om_plants_on_lane/Run()
	var/datum/probe = allocate(/datum/dq_periodic_probe)
	om_task_periodic(probe, PERIODIC_PLANTS)
	TEST_ASSERT(probe.periodic_pipe == PERIODIC_PLANTS, "the plant lane did not take a datum")
	var/datum/om/pipeline/periodic/P = om_registry().behaviour(PERIODIC_PLANTS)
	TEST_ASSERT_EQUAL(P.every, 7.5 SECONDS, "the plant lane lost the old SSplants cadence")
	om_task_periodic_stop(probe)

#endif

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// A machine type on the machine pipeline from Initialize, like the mapped ones.
/obj/machinery/dq_step_probe/mapped

/obj/machinery/dq_step_probe/mapped/started
	var/start_now = TRUE

/obj/machinery/dq_step_probe/mapped/started/step_start_condition()
	return start_now

/datum/om/decl/dq_test_step_probe
	of = /obj/machinery/dq_step_probe/mapped
	behaviours = list(/datum/om/pipeline/machine)

/// Machines never start by default: a freshly materialized machine with no work is never stepped
/// and parks; one whose declared start condition holds is woken once the world is up.
/datum/unit_test/dq_om_fresh_machine_never_steps

/datum/unit_test/dq_om_fresh_machine_never_steps/Run()
	var/obj/machinery/dq_step_probe/mapped/idle = allocate(/obj/machinery/dq_step_probe/mapped, test_floor())
	idle.work = 5
	var/obj/machinery/dq_step_probe/mapped/started/busy = allocate(/obj/machinery/dq_step_probe/mapped/started, test_floor())
	busy.work = 5
	TEST_ASSERT(om_attached(idle, /datum/om/pipeline/machine), "a decl-listed machine did not join the pipeline")
	for(var/i in 1 to 40)
		om_test_ticks(1)
		if(busy.steps)
			break
	// Two intervals after the busy machine first steps: the idle one would have
	// been stepped by then (was three, ~2 s of extra real-time wait).
	om_test_ticks(MACHINE_PIPELINE_INTERVAL * 2 / world.tick_lag)
	TEST_ASSERT_EQUAL(idle.steps, 0, "a fresh machine with no work was stepped")
	TEST_ASSERT(om_pipe_parked(idle, /datum/om/pipeline/machine), "a fresh machine with no work did not park")
	TEST_ASSERT(busy.steps > 0, "a machine whose start condition holds was not woken")

#endif

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// Started items and effects run only when they can act: idle ones say so, radiation sources
/// sleep with nobody near and wake when a mob comes, timed ones sleep on one timer.
/datum/unit_test/dq_om_items_run_only_when_they_can_act

/datum/unit_test/dq_om_items_run_only_when_they_can_act/Run()
	var/turf/T = locate(world.maxx - 2, world.maxy - 2, test_floor().z)
	// Proximity gate: a uranium coin with nobody near sleeps on the chunks around it.
	for(var/mob/living/L in range(world.view, T))
		TEST_FAIL("the test corner is not empty") // the gate needs an empty neighbourhood
		return
	var/obj/item/coin/uranium/coin = allocate(/obj/item/coin/uranium, T)
	TEST_ASSERT_EQUAL(coin.periodic_step(20), PROCESS_KILL, "a radiation source with nobody near kept stepping")
	TEST_ASSERT(length(coin.proximity_chunks), "a sleeping radiation source watches no chunks")
	om_task_periodic_stop(coin)
	var/mob/living/visitor = allocate(/mob/living, locate(1, 1, T.z))
	visitor.forceMove(get_step(T, WEST))
	for(var/i in 1 to 40)
		om_test_ticks(1)
		if(coin.periodic_pipe)
			break
	TEST_ASSERT(coin.periodic_pipe == PERIODIC_SLOW, "a mob coming near did not wake the radiation source")
	TEST_ASSERT(!coin.proximity_chunks, "a woken radiation source kept its chunk watches")
	qdel(visitor)

	// Start and stop conditions.
	var/obj/item/chainsaw/saw = allocate(/obj/item/chainsaw, test_floor())
	TEST_ASSERT(!saw.periodic_pipe, "a chainsaw that is off runs")
	TEST_ASSERT(!om_task_periodic(saw, PERIODIC_SLOW), "a chainsaw that is off could be started")
	var/obj/item/gun/launcher/spikethrower/spikes = allocate(/obj/item/gun/launcher/spikethrower, test_floor())
	TEST_ASSERT(!spikes.periodic_pipe, "a full spikethrower runs")
	var/obj/item/ghost_trap/trap = allocate(/obj/item/ghost_trap, test_floor())
	TEST_ASSERT(!trap.periodic_pipe, "an empty ghost trap runs")
	var/obj/effect/map_effect/interval/effect = allocate(/obj/effect/map_effect/interval, T)
	effect.always_run = FALSE
	TEST_ASSERT_EQUAL(effect.periodic_step(20), PROCESS_KILL, "an interval effect with nobody near kept stepping")

	// One timer instead of a countdown.
	var/obj/structure/timer_door/door = allocate(/obj/structure/timer_door, test_floor())
	TEST_ASSERT(!door.periodic_pipe, "a timer door polls")
	var/obj/effect/spider/eggcluster/eggs = allocate(/obj/effect/spider/eggcluster, test_floor())
	TEST_ASSERT(!eggs.periodic_pipe, "an egg cluster polls its growth")
	TEST_ASSERT(length(eggs.om_rec?.timers), "an egg cluster has no hatch timer")

#endif
