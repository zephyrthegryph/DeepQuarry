// Behaviour of the things that sleep on a gas level (doc/rewrite/framework_gaps.md, F5): a device whose work stops until its air reaches a
// state, an object that breaks when its air gets too hot, a material service woken by its surroundings. The tests state what the holder does
// when the gas changes, not how it is told, so they hold through the move from the old watch helpers to the gas_level() capability.

/// Delivers what a gas change published, however the holder listens, without letting time pass: the native gas frame, the machine service's
/// gas wakes (the observation stream), the world's crossings on every lane, and the marked drain that runs the holder's reactions. The live
/// kernel never runs in between (nothing sleeps), so no deadline, retire or lane budget of its own can race the test: a wait of a few ticks
/// for the live loop to deliver the wake was the flake (the loop skips ticks under load, and runs unrelated work on the holder meanwhile).
/proc/dq_gas_level_test_deliver()
	SSair.run_gas_frames(2)
	SSmachines.wake_dirty_gas_subscribers()
	var/datum/om/scheduler/sched = GLOB.om_live_sched
	if(sched)
		for(var/lane in 1 to OM_LANE_COUNT)
			sched.run_world_wakes(lane)
	SSmachines.wake_dirty_gas_subscribers()
	kernel_drain_now()

/// A machine that sleeps on a gas watch is woken once at creation, as its first wake does (materialize_wakes()); a holder with no started work needs
/// nothing.
/proc/dq_gas_level_test_first_wake(obj/machinery/M)
	if(cap_of(M, CAP_STARTED_WORK))
		work_start(M)

/// Runs `M`'s started work once if it is started, as the kernel's interval would.
/proc/dq_gas_level_test_step(obj/machinery/M)
	if(QDELETED(M) || !cap_of(M, CAP_STARTED_WORK) || !work_started(M) || !hascall(M, "work_step"))
		return
	if(call(M, "work_step")(null) == PROCESS_KILL && !QDELETED(M))
		work_stop(M)

/// A floor with sealed standard air, snapshotted so the test's restore puts it back.
/datum/unit_test/proc/gas_level_test_room()
	var/list/pair = dq_atmos_test_find_clear_pipe_run(1)
	TEST_ASSERT_NOTNULL(pair, "no clear floor for the gas level test")
	var/turf/simulated/floor/T = pair[1]
	dq_atmos_test_snapshot_air(T)
	dq_atmos_test_isolate_pair(T, T)
	dq_atmos_test_fill_standard_air(T)
	T.air_update_turf(TRUE, FALSE)
	return T

/// An artifact in air that stays under its breaking temperature is left alone; heat the air past it and it breaks, with nobody polling it.
/datum/unit_test/dq_gas_level_artifact_breaks_in_hot_air

/datum/unit_test/dq_gas_level_artifact_breaks_in_hot_air/Run()
	var/turf/simulated/floor/T = gas_level_test_room()
	var/obj/machinery/artifact/A = new(T)
	dq_gas_level_test_first_wake(A)
	dq_gas_level_test_step(A)
	dq_gas_level_test_deliver()
	dq_gas_level_test_step(A)
	TEST_ASSERT(!QDELETED(A), "an artifact in ordinary air broke")
	heat_set(T.air, ARTIFACT_HEAT_BREAK - 300, HEAT_SOURCE_OTHER)
	dq_gas_level_test_deliver()
	dq_gas_level_test_step(A)
	TEST_ASSERT(!QDELETED(A), "an artifact in air under its breaking temperature broke")
	heat_set(T.air, ARTIFACT_HEAT_BREAK + 500, HEAT_SOURCE_OTHER)
	dq_gas_level_test_deliver()
	dq_gas_level_test_step(A)
	TEST_ASSERT(QDELETED(A), "an artifact in air past its breaking temperature did not break")

/// An artifact moved into hot air breaks: the move re-points whatever listens to its air.
/datum/unit_test/dq_gas_level_artifact_follows_its_move

/datum/unit_test/dq_gas_level_artifact_follows_its_move/Run()
	var/list/pair = dq_atmos_test_find_clear_pipe_run(2)
	TEST_ASSERT_NOTNULL(pair, "no clear two-tile run for the gas level test")
	var/turf/simulated/floor/T = pair[1]
	var/turf/simulated/floor/other = pair[2]
	dq_atmos_test_snapshot_air(T)
	dq_atmos_test_snapshot_air(other)
	dq_atmos_test_isolate_pair(T, other)
	dq_atmos_test_fill_standard_air(T)
	dq_atmos_test_fill_standard_air(other)
	T.air_update_turf(TRUE, FALSE)
	var/obj/machinery/artifact/A = new(T)
	dq_gas_level_test_first_wake(A)
	dq_gas_level_test_step(A)
	dq_gas_level_test_deliver()
	dq_gas_level_test_step(A)
	heat_set(other.air, ARTIFACT_HEAT_BREAK + 2500, HEAT_SOURCE_OTHER)
	A.forceMove(other)
	dq_gas_level_test_deliver()
	dq_gas_level_test_step(A)
	TEST_ASSERT(QDELETED(A), "an artifact moved into air past its breaking temperature did not break")

/// A charging disposal bin with no air to draw sleeps; air coming back wakes it.
/datum/unit_test/dq_gas_level_disposal_wakes_when_air_returns

/datum/unit_test/dq_gas_level_disposal_wakes_when_air_returns/Run()
	var/turf/simulated/floor/T = gas_level_test_room()
	var/obj/machinery/disposal/disposal = allocate(/obj/machinery/disposal, T)
	disposal.set_grid_power(TRUE) // the test room's area may be left unpowered by an earlier test: this is about the gas wake, not the grid
	disposal.air_contents.clear()
	var/datum/gas_mixture/environment = T.return_air()
	var/datum/gas_mixture/standard = environment.copy()
	environment.clear()
	TEST_ASSERT(test_machine_idle(disposal), "an airless disposal kept retrying pressurization")
	dq_gas_level_test_deliver()
	TEST_ASSERT(!work_started(disposal), "an airless disposal woke with nothing to draw")
	environment.copy_from(standard)
	qdel(standard)
	dq_gas_level_test_deliver()
	TEST_ASSERT(work_started(disposal), "a sleeping disposal did not wake when air came back")

/// A material service wakes when its surroundings get hotter by more than its resolution, and stays asleep for a change below it.
/datum/unit_test/dq_gas_level_material_service_hears_heat

/datum/unit_test/dq_gas_level_material_service_hears_heat/Run()
	var/turf/simulated/floor/T = gas_level_test_room()
	var/obj/machinery/portable_atmospherics/canister/air/C = allocate(/obj/machinery/portable_atmospherics/canister/air, T)
	var/datum/material_service/service = C.enable_material_service()
	TEST_ASSERT_NOTNULL(service, "the canister has a material service")
	dq_gas_level_test_deliver()
	// The exposure work queued at creation is dropped and the service re-bound to the room's mixture: nothing runs it meanwhile, so it cannot
	// retire the service (spent() clears its gas watches) before the heat arrives.
	cancel_after(service, "material_service")
	service.rebind()
	dq_gas_level_test_deliver()
	cancel_after(service, "material_service")
	service.timer = FALSE
	service.active = FALSE
	heat_set(T.air, T.air.return_temperature() + MATERIAL_THERMAL_RESOLUTION / 4, HEAT_SOURCE_OTHER)
	dq_gas_level_test_deliver()
	TEST_ASSERT(!after_pending(service, "material_service"), "a change under its resolution woke the service")
	heat_set(T.air, T.air.return_temperature() + MATERIAL_THERMAL_RESOLUTION * 20, HEAT_SOURCE_OTHER)
	dq_gas_level_test_deliver()
	TEST_ASSERT(after_pending(service, "material_service"), "a large change in its surroundings did not queue exposure work")
	qdel(C)
	dq_gas_level_test_deliver()

// ---------------------------------------------------------------- gas_level()

/// A holder with two levels on the mixture a test hands it: hot (temperature at or over T20C + 30) and thin (total moles at or under 5).
/obj/test_gas_level_holder
	var/datum/gas_mixture/watched_air
	var/hot = FALSE
	var/thin = FALSE
	var/hot_runs = 0
	var/thin_runs = 0

TRACKED(/obj/test_gas_level_holder, hot)
TRACKED(/obj/test_gas_level_holder, thin)

CAPABILITIES(/obj/test_gas_level_holder)
	gas_level(into = nameof(hot), reading = CH_GAS_TEMPERATURE, above = T20C + 30, hysteresis = 5, air = nameof(watched_air))
	gas_level(into = nameof(thin), reading = CH_GAS_MOLES, below = 5, hysteresis = 1, air = nameof(watched_air))
	on_change(nameof(hot), ANY, then(PROC_REF(hot_changed)))
	on_change(nameof(thin), ANY, then(PROC_REF(thin_changed)))

/obj/test_gas_level_holder/proc/hot_changed(datum/act/A)
	hot_runs++

/obj/test_gas_level_holder/proc/thin_changed(datum/act/A)
	thin_runs++

/// A holder over `air`, armed.
/datum/unit_test/proc/gas_level_test_holder(datum/gas_mixture/air)
	var/obj/test_gas_level_holder/holder = allocate(/obj/test_gas_level_holder)
	holder.watched_air = air
	gas_level_rearm_all(holder)
	dq_gas_level_test_deliver()
	return holder

/datum/unit_test/proc/gas_level_test_warm(datum/gas_mixture/air)
	heat_set(air, T20C + 60, HEAT_SOURCE_OTHER)

/datum/unit_test/proc/gas_level_test_cool(datum/gas_mixture/air)
	heat_set(air, T20C, HEAT_SOURCE_OTHER)

/// A level on a mixture a machine owns turns its var at the crossing in each direction, and not for a move that stays on one side.
/datum/unit_test/dq_gas_level_crosses_a_private_mixture

/datum/unit_test/dq_gas_level_crosses_a_private_mixture/Run()
	var/datum/gas_mixture/tank = allocate(/datum/gas_mixture, 70)
	tank.adjust_gas(/datum/gas/nitrogen, 10)
	heat_set(tank, T20C, HEAT_SOURCE_OTHER)
	var/obj/test_gas_level_holder/holder = gas_level_test_holder(tank)
	TEST_ASSERT(!holder.hot, "a mixture under the level started hot")
	TEST_ASSERT(!holder.thin, "a mixture over the level started thin")
	heat_set(tank, T20C + 10, HEAT_SOURCE_OTHER)
	dq_gas_level_test_deliver()
	TEST_ASSERT(!holder.hot, "a rise that stays under the level turned the var")
	gas_level_test_warm(tank)
	dq_gas_level_test_deliver()
	TEST_ASSERT(holder.hot, "a rise past the level did not turn the var")
	TEST_ASSERT_EQUAL(holder.hot_runs, 1, "the holder's on_change did not run once for the crossing")
	gas_level_test_cool(tank)
	dq_gas_level_test_deliver()
	TEST_ASSERT(!holder.hot, "a fall back past the level did not turn the var off")
	TEST_ASSERT_EQUAL(holder.hot_runs, 2, "the holder's on_change did not run for the fall")
	// The second level of the same holder is its own: moles under 5 turns thin, nothing else.
	tank.adjust_gas(/datum/gas/nitrogen, -7)
	dq_gas_level_test_deliver()
	TEST_ASSERT(holder.thin, "total moles under its level did not turn the thin var")
	TEST_ASSERT(!holder.hot, "the thin level turned the hot var")
	tank.adjust_gas(/datum/gas/nitrogen, 20)
	dq_gas_level_test_deliver()
	TEST_ASSERT(!holder.thin, "moles back over the level did not turn the thin var off")

/// The var holds inside the hysteresis band: it turns on at the level and off only once the reading is the hysteresis back from it.
/datum/unit_test/dq_gas_level_hysteresis

/datum/unit_test/dq_gas_level_hysteresis/Run()
	var/datum/gas_mixture/tank = allocate(/datum/gas_mixture, 70)
	tank.adjust_gas(/datum/gas/nitrogen, 10)
	heat_set(tank, T20C, HEAT_SOURCE_OTHER)
	var/obj/test_gas_level_holder/holder = gas_level_test_holder(tank)
	heat_set(tank, T20C + 31, HEAT_SOURCE_OTHER)
	dq_gas_level_test_deliver()
	TEST_ASSERT(holder.hot, "just past the level did not turn the var")
	heat_set(tank, T20C + 28, HEAT_SOURCE_OTHER)
	dq_gas_level_test_deliver()
	TEST_ASSERT(holder.hot, "a fall inside the hysteresis band turned the var off")
	heat_set(tank, T20C + 20, HEAT_SOURCE_OTHER)
	dq_gas_level_test_deliver()
	TEST_ASSERT(!holder.hot, "a fall past the hysteresis band did not turn the var off ([tank.return_temperature()] K, level [T20C + 30])")
	TEST_ASSERT_EQUAL(holder.hot_runs, 2, "the var turned more than once for one rise and one fall")

/// A burst of writes inside one tick runs the holder's reaction once, with the var where the last write left it.
/datum/unit_test/dq_gas_level_burst_coalesces

/datum/unit_test/dq_gas_level_burst_coalesces/Run()
	var/datum/gas_mixture/tank = allocate(/datum/gas_mixture, 70)
	tank.adjust_gas(/datum/gas/nitrogen, 10)
	heat_set(tank, T20C, HEAT_SOURCE_OTHER)
	var/obj/test_gas_level_holder/holder = gas_level_test_holder(tank)
	for(var/i in 1 to 5)
		gas_level_test_warm(tank)
		gas_level_test_cool(tank)
	gas_level_test_warm(tank)
	dq_gas_level_test_deliver()
	TEST_ASSERT(holder.hot, "the last write left it hot")
	TEST_ASSERT(holder.hot_runs <= 1, "a burst of writes ran the holder's reaction [holder.hot_runs] times")

/// The guarantee the watches keep: a heat write to a pipe network's region, which reaches Rust without any DM write to the mixture, still turns the
/// level, in both directions.
/datum/unit_test/dq_gas_level_hears_pipe_region_heat

/datum/unit_test/dq_gas_level_hears_pipe_region_heat/Run()
	var/list/run = dq_atmos_test_find_clear_pipe_run(2)
	TEST_ASSERT_NOTNULL(run, "no clear two-tile pipe run")
	var/turf/A = run[1]
	var/turf/B = run[2]
	var/direction = get_dir(A, B)
	var/obj/machinery/atmospherics/pipe/simple/P1 = allocate(/obj/machinery/atmospherics/pipe/simple, A)
	var/obj/machinery/atmospherics/pipe/simple/P2 = allocate(/obj/machinery/atmospherics/pipe/simple, B)
	for(var/obj/machinery/atmospherics/pipe/simple/P as anything in list(P1, P2))
		P.dir = direction | REVERSE_DIR(direction)
		P.initialize_directions = P.dir
	P1.atmos_init()
	P2.atmos_init()
	dq_atmos_test_publish_rust_pipenets(list(P1, P2))
	var/datum/gas_mixture/pipe_air = P1.parent?.air
	TEST_ASSERT_NOTNULL(pipe_air, "the pipes have no pipeline air")
	pipe_air.adjust_gas(/datum/gas/nitrogen, 10)
	heat_set(pipe_air, T20C, HEAT_SOURCE_OTHER)
	var/obj/test_gas_level_holder/holder = gas_level_test_holder(pipe_air)
	TEST_ASSERT(!holder.hot, "a cool pipe region started hot")
	heat_add(pipe_air, pipe_air.heat_capacity() * 60, HEAT_SOURCE_OTHER)
	dq_gas_level_test_deliver()
	TEST_ASSERT(holder.hot, "heat_add() on a pipe region did not turn the level ([pipe_air.return_temperature()] K)")
	gas_level_test_cool(pipe_air)
	dq_gas_level_test_deliver()
	TEST_ASSERT(!holder.hot, "cooling a pipe region did not turn the level off ([pipe_air.return_temperature()] K)")

/// A turf's air: a level on the air a holder stands in turns with the room.
/datum/unit_test/dq_gas_level_hears_a_turfs_air

/datum/unit_test/dq_gas_level_hears_a_turfs_air/Run()
	var/turf/simulated/floor/T = gas_level_test_room()
	var/obj/test_gas_level_holder/holder = gas_level_test_holder(T.air)
	TEST_ASSERT(!holder.hot, "a room at 20 C started hot")
	heat_set(T.air, T20C + 60, HEAT_SOURCE_OTHER)
	dq_gas_level_test_deliver()
	TEST_ASSERT(holder.hot, "heating a turf's air did not turn the level")

/// A level that starts past its limit is told at arming, and a holder with no air reads under it.
/datum/unit_test/dq_gas_level_settles_at_arming

/datum/unit_test/dq_gas_level_settles_at_arming/Run()
	var/datum/gas_mixture/tank = allocate(/datum/gas_mixture, 70)
	tank.adjust_gas(/datum/gas/nitrogen, 10)
	heat_set(tank, T20C + 100, HEAT_SOURCE_OTHER)
	var/obj/test_gas_level_holder/holder = gas_level_test_holder(tank)
	TEST_ASSERT(holder.hot, "a mixture already past the level did not turn the var at arming")
	holder.watched_air = null
	gas_level_rearm_all(holder)
	TEST_ASSERT(!holder.hot, "a holder with no mixture stayed hot")
