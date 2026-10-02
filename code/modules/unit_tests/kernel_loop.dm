// The kernel as the host loop (code/controllers/kernel/loop.dm): there is no Master Controller and no subsystem queue, the
// watchdog watches the kernel, the loop can be restarted, and the systems that used to be subsystems run as kernel work.

/// The kernel owns the loop: the host systems' work runs as work items in phases K and G, and the kernel's values keep their
/// meaning.
/datum/unit_test/kernel_loop_is_host

/datum/unit_test/kernel_loop_is_host/Run()
	var/datum/controller/kernel/K = kernel()
	TEST_ASSERT(K.loop_gen > 0, "a kernel loop generation is running")
	TEST_ASSERT_EQUAL(Kernel.init_stage_completed, INITSTAGE_MAX, "the loop runs at the last init stage")
	TEST_ASSERT(Kernel.current_runlevel >= 1, "the kernel keeps the run level")
	var/list/key_phase = list(
		"[/datum/system/tgui]:refresh_autoupdating" = KERNEL_PHASE_K,
		"[/datum/system/dbcore]:run_queries" = KERNEL_PHASE_K,
		"[/datum/system/profiler]:sample" = KERNEL_PHASE_K,
		"[/datum/system/garbage]:collect" = KERNEL_PHASE_G,
		"[/datum/system/input]:drain_step" = KERNEL_PHASE_K,
	)
	for(var/key in key_phase)
		var/datum/work_item/W = K.work_by_key[key]
		TEST_ASSERT(W, "[key] is a registered work item")
		TEST_ASSERT_EQUAL(W.phase, key_phase[key], "[key] runs in phase [phase_letter(key_phase[key])]")
	// Kernel.x is the loop's value, written by the kernel.
	var/iteration_before = Kernel.iteration
	var/ticks_before = K.ticks
	var/host_before = SSgarbage.times_fired
	sleep(3 SECONDS)
	TEST_ASSERT(K.ticks > ticks_before, "the kernel loop ticks")
	TEST_ASSERT_EQUAL(Kernel.iteration - iteration_before, K.ticks - ticks_before, "Kernel.iteration counts the kernel's ticks")
	TEST_ASSERT_EQUAL(Kernel.last_run, K.last_tick, "Kernel.last_run is the kernel heartbeat")
	TEST_ASSERT(SSgarbage.times_fired > host_before, "a host system on a longer wait runs from the kernel")

/// The watchdog watches kernel.last_tick, and Recreate_kernel() replaces the loop without doubling it.
/datum/unit_test/kernel_watchdog_watches_kernel

/datum/unit_test/kernel_watchdog_watches_kernel/Run()
	var/datum/controller/kernel/K = kernel()
	var/datum/kernel_watchdog/watchdog = K.watchdog
	TEST_ASSERT_NOTNULL(watchdog, "the kernel started its watchdog")
	sleep(watchdog.processing_interval + 2)
	TEST_ASSERT(watchdog.kernel_tick_seen > 0, "the watchdog has read the kernel heartbeat")
	TEST_ASSERT(K.last_tick - watchdog.kernel_tick_seen <= watchdog.processing_interval * 2, "it reads a recent one: [watchdog.kernel_tick_seen] vs [K.last_tick]")
	TEST_ASSERT_EQUAL(watchdog.defcon, 5, "a ticking kernel keeps the watchdog at defcon 5")
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

/// reset_work() drops every in-flight run, so the next loop starts the items clean.
/datum/unit_test/kernel_reset_work

/datum/unit_test/kernel_reset_work/Run()
	var/datum/controller/kernel/K = new
	var/datum/test_work_owner/O = new
	var/datum/work_item/test_fixture/W = K.register_work(/datum/test_work_owner, test_work_item(O, interval = 100))
	W.cursor = 5
	W.yielded = TRUE
	W.next_run = 1000
	K.reset_work()
	TEST_ASSERT_EQUAL(W.cursor, 0, "an open sweep is closed")
	TEST_ASSERT(!W.yielded, "a yield is forgotten")
	TEST_ASSERT_EQUAL(W.next_run, 0, "and the item is due")

// ---------------------------------------------------------------- the systems

/// SSx is the system instance (GLOBAL_REAL alias), booted in the DAG.
/datum/unit_test/system_converted_aliases

/datum/unit_test/system_converted_aliases/Run()
	var/list/converted = list(
		/datum/system/access = SSaccess, /datum/system/admin_verbs = SSadmin_verbs, /datum/system/air = SSair,
		/datum/system/contracts = SScontracts, /datum/system/holomaps = SSholomaps, /datum/system/internal_wiki = SSinternal_wiki,
		/datum/system/job = SSjob, /datum/system/lighting = SSlighting, /datum/system/mapping = SSmapping,
		/datum/system/media_tracks = SSmedia_tracks, /datum/system/nerdle = SSnerdle, /datum/system/persistence = SSpersistence,
		/datum/system/robot_sprites = SSrobot_sprites, /datum/system/shuttles = SSshuttles, /datum/system/ticker = SSticker,
		/datum/system/input = SSinput, /datum/system/native = SSvg, /datum/system/assets = SSassets, /datum/system/atoms = SSatoms,
		/datum/system/behaviours = SSbehaviours, /datum/system/dbcore = SSdbcore, /datum/system/early_assets = SSearly_assets,
		/datum/system/garbage = SSgarbage, /datum/system/overlays = SSoverlays, /datum/system/profiler = SSprofiler,
		/datum/system/sqlite = SSsqlite, /datum/system/tgui = SStgui,
	)
	var/list/table = system_table()
	for(var/path in converted)
		var/datum/system/S = converted[path]
		TEST_ASSERT(istype(S, path), "[path]: the SS global is the system")
		TEST_ASSERT_EQUAL(table[path], S, "[path]: the SS global is the registered instance")
		TEST_ASSERT(S.initialized, "[path] booted in the DAG")
		TEST_ASSERT(S in kernel_boot_systems(), "[path] is a boot node")
	TEST_ASSERT_EQUAL(SSvg, native_system(), "SSvg is the native system")
	TEST_ASSERT(SSvg.entity_census()["dm_bound"] >= 0, "the entity table lives on the native system")
	// The boot order still holds: each needs its needs.
	for(var/path in converted)
		var/datum/system/S = converted[path]
		for(var/need in S.needs)
			var/datum/system/dep = table[need]
			TEST_ASSERT(dep?.initialized, "[path] needs [need], which booted")
			TEST_ASSERT(dep.init_time_ms >= 0, "[need] recorded its boot time")

/// A system's periodic work: ready() is its gate, and the kernel reports each run of its items to note_run().
/datum/unit_test/system_note_run

/datum/unit_test/system_note_run/Run()
	var/datum/system/test_runs/S = new
	S.initialized = TRUE
	TEST_ASSERT(S.work_ready(), "a booted system that may run is ready")
	S.can_fire = FALSE
	TEST_ASSERT(!S.work_ready(), "can_fire = FALSE parks the work")
	S.can_fire = TRUE
	S.note_run(4, TRUE)
	TEST_ASSERT_EQUAL(S.times_fired, 0, "a yielded run is not a completed one")
	TEST_ASSERT_EQUAL(S.run_ms, 4, "but its cost is recorded")
	S.note_run(6, FALSE)
	TEST_ASSERT_EQUAL(S.times_fired, 1, "a finished run counts")
	TEST_ASSERT_EQUAL(S.fire_cost, 6, "its cost is the first average")
	S.note_run(2, FALSE)
	TEST_ASSERT_EQUAL(S.times_fired, 2, "two runs completed")
	TEST_ASSERT(S.fire_cost < 6 && S.fire_cost > 2, "the cost is a running average")

/datum/system/test_runs
	abstract_type = /datum/system/test_runs

/// air, lighting, the ticker and the other former subsystems run from the kernel's work items, in the phases the host table gives.
/datum/unit_test/system_work_items

/datum/unit_test/system_work_items/Run()
	var/datum/controller/kernel/K = kernel()
	var/list/expected = list(
		"[/datum/system/air]:atmos_step" = KERNEL_PHASE_N,
		"[/datum/system/lighting]:light_step" = KERNEL_PHASE_K,
		"[/datum/system/ticker]:round_step" = KERNEL_PHASE_K,
	)
	for(var/key in expected)
		var/datum/work_item/W = K.work_by_key[key]
		TEST_ASSERT(W, "[key] is a registered work item")
		TEST_ASSERT(!W.parked, "[key] is not parked")
		TEST_ASSERT(W.system_owned, "[key] reports its runs to its system")
		TEST_ASSERT_EQUAL(W.phase, expected[key], "[key] runs in phase [phase_letter(expected[key])]")
	var/datum/work_item/air = K.work_by_key["[/datum/system/air]:atmos_step"]
	TEST_ASSERT_EQUAL(air.interval, SSair.wait, "air's every() is its old wait")
	TEST_ASSERT_EQUAL(air.lane, LANE_SIMULATION, "air runs on the simulation lane")
	TEST_ASSERT_EQUAL(air.owner(), SSair, "the item runs on the system")
	var/datum/work_item/light = K.work_by_key["[/datum/system/lighting]:light_step"]
	TEST_ASSERT_EQUAL(light.interval, WORK_EVERY_TICK, "lighting runs every tick (it was a ticker)")
	TEST_ASSERT_EQUAL(light.lane, LANE_PRESENTATION, "lighting is presentation work (sheddable under overload)")
	var/air_before = SSair.times_fired
	var/light_before = SSlighting.times_fired
	var/ticker_before = SSticker.times_fired
	// Lighting is presentation work, shed while the machine is overloaded (as under a sharded
	// suite), so wait for all three rather than a fixed three seconds.
	for(var/waited in 1 to 30)
		sleep(1 SECONDS)
		if(SSair.times_fired > air_before && SSlighting.times_fired > light_before && SSticker.times_fired > ticker_before)
			break
	TEST_ASSERT(SSair.times_fired > air_before, "air runs from the kernel")
	TEST_ASSERT(SSlighting.times_fired > light_before, "lighting runs from the kernel")
	TEST_ASSERT(SSticker.times_fired > ticker_before, "the ticker runs from the kernel")
	TEST_ASSERT_EQUAL(length(K.work_errors), 0, "the work graph has no errors")
