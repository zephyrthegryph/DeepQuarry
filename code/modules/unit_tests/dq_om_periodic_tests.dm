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

/// cadence_start() puts the entity on a cadence and the kernel steps it until periodic_step() returns
/// PROCESS_KILL; the entity then leaves the cadence (it costs nothing), cadence_start() starts it again,
/// cadence_stop() ends the work early, and moving to another cadence leaves the first.
/datum/unit_test/dq_om_periodic_park_wake

/datum/unit_test/dq_om_periodic_park_wake/Run()
	var/datum/dq_periodic_probe/D = allocate(/datum/dq_periodic_probe)
	var/P = PERIODIC_SLOW
	D.work = 2
	cadence_start(D, P)
	TEST_ASSERT(member_is(P, D), "cadence_start() did not put it on the cadence")
	TEST_ASSERT((!isnull(D.periodic_pipe)) && (D.datum_flags & DF_ISPROCESSING), "a started entity is not marked running")
	for(var/i in 1 to 2)
		TEST_ASSERT(periodic_run_now(D, P), "a started entity could not be stepped")
	TEST_ASSERT_EQUAL(D.steps, 2, "it did not step once per frame while it had work")
	TEST_ASSERT_EQUAL(D.last_delta, 20, "the slow lane passes the old SSobj delta")
	TEST_ASSERT(!(!isnull(D.periodic_pipe)), "PROCESS_KILL did not end the work")
	TEST_ASSERT(!member_is(P, D), "an entity with no work stayed on the cadence")
	for(var/i in 1 to 3)
		TEST_ASSERT(!periodic_run_now(D, P), "an entity with no work could be stepped")
	TEST_ASSERT_EQUAL(D.steps, 2, "it stepped with no work")

	D.work = 5
	cadence_start(D, P)
	TEST_ASSERT(member_is(P, D), "cadence_start() did not put it back on the cadence")
	TEST_ASSERT(periodic_run_now(D, P), "a restarted entity did not step")
	TEST_ASSERT_EQUAL(D.steps, 3, "a restarted entity did not step")
	cadence_stop(D)
	var/stopped_at = D.steps
	for(var/i in 1 to 3)
		periodic_run_now(D, P)
	TEST_ASSERT_EQUAL(D.steps, stopped_at, "cadence_stop() did not end the work")
	TEST_ASSERT(!member_is(P, D), "a stopped entity stayed on the cadence")

	// Moving to another lane leaves the first one, not double-stepped.
	D.work = 5
	cadence_start(D, P)
	cadence_start(D, PERIODIC_FAST)
	TEST_ASSERT(!member_is(P, D), "moving to another lane left the entity on the first")
	TEST_ASSERT(member_is(PERIODIC_FAST, D), "moving to another lane did not join the new one")
	TEST_ASSERT(!periodic_run_now(D, P), "the old lane kept stepping after a move")
	TEST_ASSERT(periodic_run_now(D, PERIODIC_FAST), "the new lane did not step")
	TEST_ASSERT_EQUAL(D.last_delta, 2, "the fast lane passes the old SSfastprocess delta")
	cadence_stop(D)

	// The kernel sweeps the cadence: a started member steps on its own, every 0.2 s on the fast lane, until it stops.
	D.work = 1000
	var/steps_before = D.steps
	cadence_start(D, PERIODIC_FAST)
	sleep(1 SECONDS)
	TEST_ASSERT(D.steps >= steps_before + 3, "the kernel did not step a fast-lane member: [D.steps - steps_before] steps in a second")
	TEST_ASSERT(D.steps <= steps_before + 8, "the kernel stepped a fast-lane member too often: [D.steps - steps_before] steps in a second")
	cadence_stop(D)
	var/after_stop = D.steps
	sleep(1 SECONDS)
	TEST_ASSERT_EQUAL(D.steps, after_stop, "a stopped member kept being stepped by the kernel")
	TEST_ASSERT(!length(pipeline_pipeline_audit(null, 400, 100, TRUE)), "the audit reported a missed wake")

/// A member that stops itself during its sweep does not make the member swapped into its slot miss the sweep.
/datum/unit_test/dq_om_periodic_sweep_survives_leaving_members

/datum/unit_test/dq_om_periodic_sweep_survives_leaving_members/Run()
	var/list/probes = list()
	for(var/i in 1 to 5)
		var/datum/dq_periodic_probe/D = allocate(/datum/dq_periodic_probe)
		D.work = (i == 2 || i == 3) ? 1 : 100 // the second and third stop at their first step
		probes += D
		cadence_start(D, PERIODIC_SLOW)
	var/datum/controller/kernel/K = kernel()
	var/datum/work_item/W = K.cadence_items[PERIODIC_SLOW]
	W.next_run = 0
	W.cursor = 0 // a fresh sweep
	var/saved = K.expect_errors
	// The sweep is spread across the interval (run_item_spread()): drive passes until it closes.
	var/now = world.time + 1000
	var/runs_before = W.runs
	for(var/pass in 1 to 1000)
		K.run_item(W, TICK_USAGE + 100, now) // a whole tick of budget from here: the test's tick may already be spent
		if(W.runs > runs_before)
			break
		now += W.interval
	K.expect_errors = saved
	TEST_ASSERT(W.runs > runs_before && !W.cursor, "the sweep closed")
	for(var/datum/dq_periodic_probe/D as anything in probes)
		TEST_ASSERT_EQUAL(D.steps, 1, "every member is stepped once in a sweep, even when others leave it")
	for(var/datum/dq_periodic_probe/D as anything in probes)
		cadence_stop(D)

/// A machine with explicitly started work (started_work(), code/library/machine/started_work.dm).
/obj/machinery/dq_step_probe
	var/work = 0
	var/steps = 0

CAPABILITIES(/obj/machinery/dq_step_probe)
	started_work(step = PROC_REF(work_step), starts = PROC_REF(step_start_condition))

/obj/machinery/dq_step_probe/proc/work_step(datum/act/timer/A)
	steps++
	if(--work <= 0)
		return PROCESS_KILL

/// work_start() runs the step every interval until it returns PROCESS_KILL; the machine then parks, a power change alone doesn't restart it,
/// and work_start()/work_stop() start and end it.
/datum/unit_test/dq_om_machine_step_park_wake

/datum/unit_test/dq_om_machine_step_park_wake/Run()
	test_driver_begin()
	var/obj/machinery/dq_step_probe/M = allocate(/obj/machinery/dq_step_probe, test_floor())
	M.set_powered(TRUE)
	TEST_ASSERT(!work_started(M), "a machine with no work started none at Initialize")
	M.work = 2
	work_start(M)
	TEST_ASSERT(work_started(M), "work_start() started its work")
	test_time(MACHINE_SERVICE_INTERVAL * 2 + 1)
	TEST_ASSERT_EQUAL(M.steps, 2, "it did not step once per interval while it had work")
	TEST_ASSERT(!work_started(M), "PROCESS_KILL ended its work")
	test_time(MACHINE_SERVICE_INTERVAL * 3)
	TEST_ASSERT_EQUAL(M.steps, 2, "it stepped with no work")
	M.work = 5
	M.set_powered(FALSE)
	M.set_powered(TRUE)
	test_time(MACHINE_SERVICE_INTERVAL * 2)
	TEST_ASSERT_EQUAL(M.steps, 2, "a power change restarted work nothing started")
	work_start(M)
	test_time(MACHINE_SERVICE_INTERVAL + 1)
	TEST_ASSERT_EQUAL(M.steps, 3, "work_start() restarted it")
	work_stop(M)
	test_time(MACHINE_SERVICE_INTERVAL * 2)
	TEST_ASSERT_EQUAL(M.steps, 3, "work_stop() ended its work")
	test_driver_end()

/datum/proc/dq_om_test_timer_hit()
	return

#endif

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// Machines that used to poll forever (roadmap S5): idle, each one's step says it has nothing to
/// do, and its producer gives it work again.
/datum/unit_test/dq_om_idle_machines_sleep

/datum/unit_test/dq_om_idle_machines_sleep/Run()
	var/turf/T = test_floor()

	var/obj/machinery/igniter/igniter = allocate(/obj/machinery/igniter, T)
	igniter.set_on(FALSE)
	TEST_ASSERT(!test_work_allowed(igniter), "a switched-off igniter may still step")
	work_stop(igniter)
	test_op_handler(igniter, "interaction_toggle", null)
	kernel_drain_now() // the switch's change reaches its work at the drain
	TEST_ASSERT(igniter.on && test_work_allowed(igniter), "switching an igniter on did not wake it")
	igniter.set_on(FALSE)

	var/obj/machinery/feeder/feeder = allocate(/obj/machinery/feeder, T)
	TEST_ASSERT(!test_work_allowed(feeder), "an unattached feeder may still step")

	var/obj/machinery/pump/pump = allocate(/obj/machinery/pump, T)
	pump.set_on(FALSE)
	TEST_ASSERT(!test_work_allowed(pump), "a switched-off reagent pump may still step")

	var/obj/machinery/bunsen_burner/bunsen = allocate(/obj/machinery/bunsen_burner, T)
	TEST_ASSERT(!test_work_allowed(bunsen), "a cold bunsen burner may still step")

	var/obj/machinery/vitals_monitor/vitals = allocate(/obj/machinery/vitals_monitor, T)
	TEST_ASSERT(test_machine_idle(vitals), "an unattached vitals monitor kept stepping")

	var/obj/machinery/door_timer/brig = allocate(/obj/machinery/door_timer, T)
	TEST_ASSERT(test_machine_idle(brig), "an idle brig timer kept stepping")

	var/obj/machinery/particle_accelerator/control_box/pa = allocate(/obj/machinery/particle_accelerator/control_box, T)
	TEST_ASSERT(test_machine_idle(pa), "an inactive particle accelerator kept stepping")

	var/obj/machinery/suspension_gen/suspension = allocate(/obj/machinery/suspension_gen, T)
	TEST_ASSERT(!test_work_allowed(suspension), "an inactive suspension generator may still step")

	var/obj/machinery/radiocarbon_spectrometer/spectrometer = allocate(/obj/machinery/radiocarbon_spectrometer, T)
	TEST_ASSERT(!test_work_allowed(spectrometer), "an idle spectrometer may still step")

	var/obj/machinery/dnaforensics/dna = allocate(/obj/machinery/dnaforensics, T)
	TEST_ASSERT(test_machine_idle(dna), "an idle DNA scanner kept stepping")

	var/obj/machinery/casino_prize_dispenser/casino = allocate(/obj/machinery/casino_prize_dispenser, T)
	TEST_ASSERT(test_machine_idle(casino), "a prize dispenser kept stepping")

	// A refinery pipe steps only while reagents move through it.
	var/obj/machinery/reagent_refinery/pipe/pipe = allocate(/obj/machinery/reagent_refinery/pipe, T)
	TEST_ASSERT(test_machine_idle(pipe), "an empty refinery pipe kept stepping")
	work_stop(pipe)
	pipe.reagents.add_reagent(REAGENT_ID_WATER, 10)
	TEST_ASSERT(test_work_allowed(pipe), "reagents arriving did not wake a refinery pipe")
	TEST_ASSERT(test_machine_idle(pipe), "a refinery pipe with nowhere to send its reagents kept stepping")

	// A door timer counts down only while timing, and wakes when started.
	work_stop(brig)
	brig.set_grid_power(TRUE)
	brig.set_broken_condition(FALSE)
	brig.set_timer(1 MINUTE)
	brig.timer_start()
	TEST_ASSERT(brig.timing && after_pending(brig, "end"), "starting a brig timer did not arm its end")
	brig.timer_end()
	TEST_ASSERT(!brig.timing && !after_pending(brig, "end"), "a finished brig timer kept a timer pending")

/// Started work (code/library/machine/started_work.dm): the work of a machine that is not operable parks (no step runs) and runs again by
/// itself when power returns.
/datum/unit_test/dq_started_work_waits_for_power

/datum/unit_test/dq_started_work_waits_for_power/Run()
	test_driver_begin()
	var/obj/machinery/dq_step_probe/M = allocate(/obj/machinery/dq_step_probe, test_floor())
	M.work = 100
	M.set_powered(FALSE)
	work_start(M)
	test_time(MACHINE_SERVICE_INTERVAL * 3)
	TEST_ASSERT_EQUAL(M.steps, 0, "an unpowered machine's work parked")
	M.set_powered(TRUE)
	test_time(MACHINE_SERVICE_INTERVAL * 2)
	TEST_ASSERT(M.steps > 0, "power returning un-parked it")
	var/ran = M.steps
	M.set_broken_condition(TRUE)
	test_time(MACHINE_SERVICE_INTERVAL * 3)
	TEST_ASSERT_EQUAL(M.steps, ran, "a broken machine's work parked")
	work_stop(M)
	test_driver_end()

#endif

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// Alarm handlers (was SSalarm): a raised alarm starts its handler on the slow lane; with no alarm
/// left it stops, and an idle handler never runs.
/datum/unit_test/dq_om_alarm_handler_park_wake

/datum/unit_test/dq_om_alarm_handler_park_wake/Run()
	var/datum/alarm_handler/AH = GLOB.power_alarm
	var/obj/item/origin = allocate(/obj/item, test_floor())
	if(!length(AH.alarms))
		AH.set_expiring(FALSE)
	AH.triggerAlarm(origin, origin, duration = 1)
	TEST_ASSERT(AH.expiring, "raising an alarm did not start its handler")
	AH.clearAlarm(origin, origin)
	if(!length(AH.alarms))
		AH.expire_step(null)
		TEST_ASSERT(!AH.expiring, "a handler with no alarms kept stepping")

#endif

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// The missed-wake audits find nothing on the test map: every parked pipeline entity is idle by its
/// own rule, and every sleeper on timers and keys is asleep for a reason.
/datum/unit_test/dq_om_audit_finds_no_missed_wakes

/datum/unit_test/dq_om_audit_finds_no_missed_wakes/Run()
	om_test_ticks(10)
	var/list/missed = pipeline_pipeline_audit(null, 100000, 100000, TRUE)
	var/list/names = list()
	for(var/datum/om/stage/T as anything in missed)
		names |= "[T.type]"
	TEST_ASSERT(!length(missed), "the pipeline audit found missed wakes: [jointext(names, ", ")]")
	var/list/woken = sleep_audit(100000, FALSE)
	TEST_ASSERT(!length(woken), "the timer/key audit found sleepers with work: [jointext(woken, "; ")]")

/// Tanning racks and modular computers sleep when idle and wake on their producer.
/datum/unit_test/dq_om_idle_items_sleep

/datum/unit_test/dq_om_idle_items_sleep/Run()
	var/obj/structure/tanning_rack/rack = allocate(/obj/structure/tanning_rack, test_floor())
	TEST_ASSERT_NULL(rack.periodic_pipe, "an empty tanning rack kept stepping")
	var/obj/item/modular_computer/tablet/T = allocate(/obj/item/modular_computer/tablet, test_floor())
	T.set_enabled(FALSE)
	TEST_ASSERT_NULL(T.periodic_pipe, "a switched-off computer kept stepping")
	TEST_ASSERT(length(T.rx?.every_parked), "a switched-off computer's every() work is not parked")
	T.enable_computer()
	TEST_ASSERT(!length(T.rx?.every_parked) || every_running(T), "switching a computer on did not open its every() gate")
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
	TEST_ASSERT(isnull(E.periodic_pipe), "a new event steps from its every(), not from a legacy lane")
	E.kill()
	TEST_ASSERT(!every_running(E), "a killed event kept its every()")
	own_remove(SSevents, nameof(/datum/system/events::finished_events), E) // the service owns finished events
	for(var/i = EVENT_LEVEL_MUNDANE to EVENT_LEVEL_MAJOR)
		var/datum/event_container/EC = SSevents.event_containers[i]
		TEST_ASSERT(EC.clock_running, "event container [i] is not keeping its clock")

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

/// Planets (was SSplanets' per-planet loop): each planet keeps its clock and weather on its own every().
/datum/unit_test/dq_om_planets_on_lanes

/datum/unit_test/dq_om_planets_on_lanes/Run()
	for(var/datum/planet/P as anything in SSplanets.planets)
		TEST_ASSERT(P.clock_running, "planet [P.name] is not keeping its clock")

#endif

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// Spreading plants (was SSplants' loop) grow on their own every() from add_plant() to remove_plant(): the interval is 7.5 s.
/datum/unit_test/dq_om_plants_on_lane

/datum/unit_test/dq_om_plants_on_lane/Run()
	var/list/entries = compiled_entries(table_of_type(/obj/effect/plant), ENTRY_EVERY)
	TEST_ASSERT_EQUAL(length(entries), 1, "the plant type lost its growth every()")
	var/datum/centry/C = entries[1]
	var/datum/entry/E = C.item
	TEST_ASSERT_EQUAL(E.args["interval"], 7.5 SECONDS, "the plant every() lost the old SSplants cadence")

#endif

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// A machine type whose work may start at Initialize, like the mapped ones.
/obj/machinery/dq_step_probe/mapped

/obj/machinery/dq_step_probe/mapped/started
	var/start_now = TRUE

/obj/machinery/dq_step_probe/mapped/started/step_start_condition()
	return start_now

/// Machines never start work by default: a freshly materialized machine with no work is never stepped; one whose declared start condition
/// holds starts once the world is up.
/datum/unit_test/dq_om_fresh_machine_never_steps

/datum/unit_test/dq_om_fresh_machine_never_steps/Run()
	test_driver_begin()
	var/obj/machinery/dq_step_probe/mapped/idle = allocate(/obj/machinery/dq_step_probe/mapped, test_floor())
	idle.work = 5
	var/obj/machinery/dq_step_probe/mapped/started/busy = allocate(/obj/machinery/dq_step_probe/mapped/started, test_floor())
	busy.work = 5
	idle.set_powered(TRUE)
	busy.set_powered(TRUE)
	test_time(MACHINE_SERVICE_INTERVAL * 3)
	TEST_ASSERT_EQUAL(idle.steps, 0, "a fresh machine with no work was stepped")
	TEST_ASSERT(!work_started(idle), "a fresh machine with no work started none")
	TEST_ASSERT(busy.steps > 0, "a machine whose start condition holds started")
	test_driver_end()

#endif

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// Started items and effects run only when they can act: idle ones say so, radiation sources
/// sleep with nobody near and wake when a mob comes, timed ones sleep on one timer.
/datum/unit_test/dq_om_items_run_only_when_they_can_act

/datum/unit_test/dq_om_items_run_only_when_they_can_act/Run()
	var/turf/T = locate(world.maxx - 2, world.maxy - 2, test_floor().z)
	// Start and stop conditions.
	var/obj/item/chainsaw/saw = allocate(/obj/item/chainsaw, test_floor())
	TEST_ASSERT(!saw.periodic_pipe, "a chainsaw that is off runs")
	var/obj/item/gun/launcher/spikethrower/spikes = allocate(/obj/item/gun/launcher/spikethrower, test_floor())
	TEST_ASSERT(!spikes.periodic_pipe, "a full spikethrower runs")
	var/obj/item/ghost_trap/trap = allocate(/obj/item/ghost_trap, test_floor())
	TEST_ASSERT(!trap.periodic_pipe, "an empty ghost trap runs")
	var/obj/effect/map_effect/interval/effect = allocate(/obj/effect/map_effect/interval, T)
	TEST_ASSERT_EQUAL(stat_value(effect, STAT_RELEVANCE), RELEVANCE_NONE, "an interval effect with nobody near is relevant")

	// One timer instead of a countdown.
	var/obj/structure/timer_door/door = allocate(/obj/structure/timer_door, test_floor())
	TEST_ASSERT(!door.periodic_pipe, "a timer door polls")
	var/obj/effect/spider/eggcluster/eggs = allocate(/obj/effect/spider/eggcluster, test_floor())
	TEST_ASSERT(!eggs.periodic_pipe, "an egg cluster polls its growth")
	TEST_ASSERT(length(eggs.om_rec?.timers), "an egg cluster has no hatch timer")

#endif

/// A spread cadence sweep keeps each member's phase: one pass runs only the share of members due by then, a later pass
/// the rest, and a pass that fell behind catches up by a bounded share.
/datum/unit_test/dq_om_periodic_sweep_is_spread

/datum/unit_test/dq_om_periodic_sweep_is_spread/Run()
	var/datum/controller/kernel/K = kernel()
	var/datum/work_item/W = K.cadence_items[PERIODIC_SLOW]
	TEST_ASSERT(W.spread, "a cadence slower than the tick spreads its sweep")
	var/list/probes = list()
	for(var/i in 1 to 40)
		var/datum/dq_periodic_probe/D = allocate(/datum/dq_periodic_probe)
		D.work = 100
		probes += D
		cadence_start(D, PERIODIC_SLOW)
	var/total = members_total(PERIODIC_SLOW)
	W.next_run = 0
	W.cursor = 0
	var/now = world.time + 1000
	K.run_item(W, TICK_USAGE + 100, now)
	var/stepped = 0
	for(var/datum/dq_periodic_probe/D as anything in probes)
		stepped += D.steps
	TEST_ASSERT(W.cursor, "one pass leaves the sweep open")
	TEST_ASSERT(W.cursor - 1 <= CEILING(total * world.tick_lag / W.interval, 1), "the first pass ran only its share ([W.cursor - 1] of [total])")
	// A long stall: the next pass is far behind, but catches up by a bounded share.
	var/before = W.cursor
	K.run_item(W, TICK_USAGE + 100, now + W.interval * 10)
	TEST_ASSERT(W.cursor == 0 || W.cursor - before <= CEILING(total * world.tick_lag / W.interval, 1) * KERNEL_SPREAD_CATCHUP, "catch-up is bounded ([W.cursor - before])")
	for(var/pass in 1 to 1000)
		if(!W.cursor)
			break
		now += W.interval
		K.run_item(W, TICK_USAGE + 100, now)
	TEST_ASSERT(!W.cursor, "the sweep closes")
	for(var/datum/dq_periodic_probe/D as anything in probes)
		TEST_ASSERT_EQUAL(D.steps, 1, "every member stepped once in the sweep")
		cadence_stop(D)
