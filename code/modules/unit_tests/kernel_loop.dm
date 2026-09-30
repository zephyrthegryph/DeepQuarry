// The kernel as the host loop (code/controllers/kernel/loop.dm): there is no MC queue, the failsafe watches the kernel,
// the loop can be restarted, and the gameplay systems that used to be subsystems run as kernel work.

/// The kernel owns the loop: every subsystem that fires is a kernel host service, Master's values keep their meaning,
/// and the host lists hold the phases K and G services.
/datum/unit_test/kernel_loop_is_host

/datum/unit_test/kernel_loop_is_host/Run()
	var/datum/controller/kernel/K = kernel()
	TEST_ASSERT(K.loop_gen > 0, "a kernel loop generation is running")
	TEST_ASSERT_EQUAL(Master.init_stage_completed, INITSTAGE_MAX, "the loop runs at the last init stage")
	TEST_ASSERT(Master.current_runlevel >= 1, "Master keeps the run level the kernel reads")
	for(var/datum/controller/subsystem/S as anything in Master.subsystems)
		if(S.flags & SS_NO_FIRE)
			continue
		TEST_ASSERT(S.flags & SS_KERNEL_HOSTED, "[S.type] fires, so the kernel must host it (there is no MC queue)")
		TEST_ASSERT(S.state != SS_QUEUED, "[S.type] is not in a queue")
	TEST_ASSERT(SSinput in K.hosted_k, "input is a phase K host")
	TEST_ASSERT(SSverb_manager in K.hosted_k, "verb_manager is a phase K host")
	TEST_ASSERT(SStgui in K.hosted_k, "the tgui transport is a phase K host")
	TEST_ASSERT(SSdbcore in K.hosted_k, "dbcore is a phase K host")
	TEST_ASSERT(SSprofiler in K.hosted_k, "the profiler is a phase K host")
	TEST_ASSERT(SSgarbage in K.hosted_g, "garbage is the phase G host")
	TEST_ASSERT(!(SSgarbage in K.hosted_k), "garbage is not also a phase K host")
	// Master.x is the loop's value, written by the kernel.
	var/iteration_before = Master.iteration
	var/ticks_before = K.ticks
	var/tgui_before = SStgui.times_fired
	sleep(2 SECONDS)
	TEST_ASSERT(K.ticks > ticks_before, "the kernel loop ticks")
	TEST_ASSERT_EQUAL(Master.iteration - iteration_before, K.ticks - ticks_before, "Master.iteration counts the kernel's ticks")
	TEST_ASSERT_EQUAL(Master.last_run, K.last_tick, "Master.last_run is the kernel heartbeat")
	TEST_ASSERT(SStgui.times_fired > tgui_before, "a host service on a longer wait fires from the kernel")

/// The failsafe watches kernel.last_tick, and Recreate_kernel() replaces the loop without doubling it.
/datum/unit_test/kernel_failsafe_watches_kernel

/datum/unit_test/kernel_failsafe_watches_kernel/Run()
	var/datum/controller/kernel/K = kernel()
	sleep(Failsafe.processing_interval + 2)
	TEST_ASSERT(Failsafe.kernel_tick_seen > 0, "the failsafe has read the kernel heartbeat")
	TEST_ASSERT(K.last_tick - Failsafe.kernel_tick_seen <= Failsafe.processing_interval * 2, "it reads a recent one: [Failsafe.kernel_tick_seen] vs [K.last_tick]")
	TEST_ASSERT_EQUAL(Failsafe.defcon, 5, "a ticking kernel keeps the failsafe at defcon 5")
	TEST_ASSERT(K.stack_end_detector?.check(), "the kernel's stack detector is alive")

	var/generation = K.loop_gen
	var/result = Recreate_kernel()
	TEST_ASSERT_EQUAL(result, 1, "the kernel loop restarts")
	TEST_ASSERT(K.loop_gen > generation, "a new loop generation superseded the old")
	// A second restart straight away is refused (the rate limit), not stacked.
	TEST_ASSERT_EQUAL(Recreate_kernel(), 0, "a restart right after a restart is refused")
	// The new loop starts after its 1 s delay; the old one has exited: one loop, one tick per world tick.
	sleep(3 SECONDS)
	var/ticks_before = K.ticks
	var/time_before = world.time
	sleep(2 SECONDS)
	var/ticks = K.ticks - ticks_before
	var/elapsed = (world.time - time_before) / world.tick_lag
	TEST_ASSERT(ticks > 0, "the restarted kernel ticks")
	TEST_ASSERT(ticks <= elapsed + 1, "one loop runs (not two): [ticks] kernel ticks in [elapsed] world ticks")

/// A hosted run that runtimes is caught: the tick goes on and the fault is counted.
/datum/unit_test/kernel_host_fault_is_contained

/datum/unit_test/kernel_host_fault_is_contained/Run()
	var/datum/controller/kernel/K = kernel()
	var/faults_before = K.phase_faults
	var/expected_before = K.expect_errors
	K.expect_errors = TRUE
	var/datum/controller/subsystem/test_host/host
	for(var/datum/controller/subsystem/S as anything in Master.subsystems)
		if(istype(S, /datum/controller/subsystem/test_host))
			host = S
	TEST_ASSERT(host, "the fixture host exists")
	K.run_hosted(host, TICK_LIMIT_RUNNING, FALSE)
	K.expect_errors = expected_before
	TEST_ASSERT_EQUAL(K.phase_faults, faults_before + 1, "the runtime was counted as a kernel fault")
	TEST_ASSERT_EQUAL(host.state, SS_IDLE, "the host is idle again, not left running")
	TEST_ASSERT(host.next_fire > world.time, "the host is scheduled for its next run")

/// A host service that always runtimes when run by hand (fixture: SS_NO_FIRE keeps the kernel from ever hosting it).
/datum/controller/subsystem/test_host
	name = "test host"
	flags = SS_NO_FIRE | SS_NO_INIT
	wait = 10 SECONDS

// ALLOW(subsystem_fire): test fixture, only ever run by hand
/datum/controller/subsystem/test_host/fire(resumed = FALSE)
	CRASH("test host fault")

// ---------------------------------------------------------------- the converted systems

/// SSx is the system instance (GLOBAL_REAL alias), booted in the DAG, and Master.subsystems no longer lists it.
/datum/unit_test/system_converted_aliases

/datum/unit_test/system_converted_aliases/Run()
	var/list/converted = list(
		/datum/system/access = SSaccess, /datum/system/admin_verbs = SSadmin_verbs, /datum/system/air = SSair,
		/datum/system/contracts = SScontracts, /datum/system/holomaps = SSholomaps, /datum/system/internal_wiki = SSinternal_wiki,
		/datum/system/job = SSjob, /datum/system/lighting = SSlighting, /datum/system/mapping = SSmapping,
		/datum/system/media_tracks = SSmedia_tracks, /datum/system/nerdle = SSnerdle, /datum/system/persistence = SSpersistence,
		/datum/system/robot_sprites = SSrobot_sprites, /datum/system/shuttles = SSshuttles, /datum/system/ticker = SSticker,
		/datum/system/speech_controller = SSspeech_controller, /datum/system/native = SSvg,
	)
	var/list/table = system_table()
	for(var/path in converted)
		var/datum/system/S = converted[path]
		TEST_ASSERT(istype(S, path), "[path]: the SS global is the system")
		TEST_ASSERT_EQUAL(table[path], S, "[path]: the SS global is the registered instance")
		TEST_ASSERT(S.initialized, "[path] booted in the DAG")
		TEST_ASSERT(S in kernel_boot_systems(), "[path] is a boot node")
		for(var/datum/controller/subsystem/SS as anything in Master.subsystems)
			TEST_ASSERT(SS.type != path, "[path] is no longer a subsystem")
	TEST_ASSERT_EQUAL(SSvg, native_system(), "SSvg is the native system")
	TEST_ASSERT(SSvg.entity_census()["dm_bound"] >= 0, "the entity table lives on the native system")
	// The boot order still holds: each needs its needs.
	for(var/path in converted)
		var/datum/system/S = converted[path]
		for(var/need in S.needs)
			if(ispath(need, /datum/system))
				var/datum/system/dep = table[need]
				TEST_ASSERT(dep?.initialized, "[path] needs [need], which booted")
				TEST_ASSERT(dep.init_time_ms >= 0, "[need] recorded its boot time")

/// The fire() shim: a system with a fire(resumed) body runs it as a kernel work item, with MC_TICK_CHECK pauses
/// turned into yields and resumes.
/datum/unit_test/system_fire_shim

/datum/unit_test/system_fire_shim/Run()
	var/datum/system/test_fire/S = new
	S.initialized = TRUE
	TEST_ASSERT(S.fire_ready(), "a booted system that may fire is ready")
	S.can_fire = FALSE
	TEST_ASSERT(!S.fire_ready(), "can_fire = FALSE parks the work")
	S.can_fire = TRUE
	// First slice: the body pauses once.
	S.pause_next = TRUE
	TEST_ASSERT_EQUAL(S.fire_step(0), STEP_YIELD, "a paused body yields")
	TEST_ASSERT(S.fire_resumed, "the next slice is a resume")
	TEST_ASSERT_EQUAL(S.times_fired, 0, "a yield is not a completed run")
	TEST_ASSERT_EQUAL(S.fire_step(0), STEP_DONE, "the resumed slice completes")
	TEST_ASSERT_EQUAL(length(S.calls), 2, "fire() ran twice")
	TEST_ASSERT_EQUAL(S.calls[1], FALSE, "the first call was not a resume")
	TEST_ASSERT_EQUAL(S.calls[2], TRUE, "the second call was the resume")
	TEST_ASSERT_EQUAL(S.times_fired, 1, "one run completed")
	TEST_ASSERT(!S.fire_resumed, "and the state is clean")
	TEST_ASSERT_EQUAL(S.state, SS_IDLE, "the system is idle between runs")
	// A body that finishes in one slice.
	TEST_ASSERT_EQUAL(S.fire_step(0), STEP_DONE, "a body that does not pause completes")
	TEST_ASSERT_EQUAL(S.times_fired, 2, "two runs completed")

/datum/system/test_fire
	abstract_type = /datum/system/test_fire
	var/pause_next = FALSE
	// ALLOW(instance_list): test fixture, one instance per test run
	var/list/calls = list()

/datum/system/test_fire/fire(resumed = FALSE)
	calls += resumed
	if(pause_next)
		pause_next = FALSE
		pause()

/// air, lighting and the ticker run their fire() bodies from the kernel's work items.
/datum/unit_test/system_fire_work_items

/datum/unit_test/system_fire_work_items/Run()
	var/datum/controller/kernel/K = kernel()
	for(var/datum/system/S as anything in list(SSair, SSlighting, SSticker))
		var/datum/work_item/W = K.work_by_key["[S.type]:fire_step"]
		TEST_ASSERT(W, "[S.type] registered its fire work item")
		TEST_ASSERT(!W.parked, "[S.type]'s work item is not parked")
		TEST_ASSERT_EQUAL(W.owner(), S, "the item runs on the system")
	var/datum/work_item/air = K.work_by_key["[/datum/system/air]:fire_step"]
	TEST_ASSERT_EQUAL(air.interval, SSair.wait, "air's every() is its old wait")
	TEST_ASSERT_EQUAL(air.lane, LANE_SIMULATION, "air runs on the simulation lane")
	var/datum/work_item/light = K.work_by_key["[/datum/system/lighting]:fire_step"]
	TEST_ASSERT_EQUAL(light.interval, WORK_EVERY_TICK, "lighting runs every tick (it was a ticker)")
	TEST_ASSERT_EQUAL(light.lane, LANE_PRESENTATION, "lighting is presentation work (sheddable under overload)")
	var/air_before = SSair.times_fired
	var/light_before = SSlighting.times_fired
	var/ticker_before = SSticker.times_fired
	sleep(3 SECONDS)
	TEST_ASSERT(SSair.times_fired > air_before, "air fires from the kernel")
	TEST_ASSERT(SSlighting.times_fired > light_before, "lighting fires from the kernel")
	TEST_ASSERT(SSticker.times_fired > ticker_before, "the ticker fires from the kernel")
	TEST_ASSERT_EQUAL(length(K.work_errors), 0, "the work graph has no errors")

/// The speech controller is a system with its own verb lane: queued verbs run from its phase K work item, and it is
/// not SSverb_manager's lane.
/datum/unit_test/system_speech_controller

/// Counts the verbs the speech lane ran.
/datum/speech_probe
	var/hits = 0

/datum/speech_probe/proc/hit()
	hits++

/datum/unit_test/system_speech_controller/Run()
	var/datum/controller/kernel/K = kernel()
	var/datum/verb_lane/lane = verb_lane_of(SSspeech_controller)
	TEST_ASSERT(lane, "the speech controller owns a verb lane")
	TEST_ASSERT_EQUAL(lane, SSspeech_controller.lane, "verb_lane_of() finds it")
	TEST_ASSERT(lane != verb_lane_of(SSverb_manager), "the speech lane is not SSverb_manager's")
	TEST_ASSERT_EQUAL(verb_lane_of(SSverb_manager), SSverb_manager.lane, "verb_lane_of() finds SSverb_manager's lane")
	var/datum/work_item/W = K.work_by_key["[/datum/system/speech_controller]:run_queue"]
	TEST_ASSERT(W, "the speech lane's work item is registered")
	TEST_ASSERT_EQUAL(W.phase, KERNEL_PHASE_K, "it runs in phase K, with the other input services")
	var/datum/speech_probe/P = new
	lane.queue_verb(VERB_CALLBACK(P, TYPE_PROC_REF(/datum/speech_probe, hit)))
	TEST_ASSERT_EQUAL(length(lane.verb_queue), 1, "the verb is queued")
	sleep(2)
	TEST_ASSERT_EQUAL(P.hits, 1, "the kernel ran the queued verb")
	TEST_ASSERT_EQUAL(length(lane.verb_queue), 0, "and emptied the queue")
