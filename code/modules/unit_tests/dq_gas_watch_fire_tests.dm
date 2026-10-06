// Gas watches fire from Rust's change tracking (code/domains/atmos/gas_watch.dm): a write to a mixture, whoever owns its gas (a machine's own
// mixture, a turf's air, a pipe network's region), reaches every watch whose mask covers the change, with no DM bookkeeping. A heat write that
// changes only the temperature reaches a temperature watch.

/// Records what a gas watch heard.
/datum/gas_watch_test_ear
	var/list/masks = list()

/datum/gas_watch_test_ear/proc/heard(datum/native_watch/gas/W, mixture_id, change_mask, list/observation, observation_index)
	masks += change_mask

/// Delivers what the mixtures' writes published to their watches (what the next frame would deliver).
/proc/dq_gas_watch_test_deliver()
	SSmachines.wake_dirty_gas_subscribers()

/// Arms a temperature-only watch on `air`, makes `change` (a proc ref on the test taking the mixture), delivers, and returns the masks heard.
/datum/unit_test/proc/gas_watch_heard(datum/gas_mixture/air, mask, change)
	dq_gas_watch_test_deliver()
	var/datum/gas_watch_test_ear/ear = allocate(/datum/gas_watch_test_ear)
	var/datum/native_watch/gas/W = gas_dependency_watch(ear, air.arena_id(), mask, TYPE_PROC_REF(/datum/gas_watch_test_ear, heard))
	dq_gas_watch_test_deliver()
	ear.masks.Cut()
	call(src, change)(air)
	dq_gas_watch_test_deliver()
	. = ear.masks.Copy()
	qdel(W)

/datum/unit_test/proc/gas_watch_heat_up(datum/gas_mixture/air)
	heat_set(air, air.return_temperature() + 40, HEAT_SOURCE_OTHER)

/datum/unit_test/proc/gas_watch_heat_move_in(datum/gas_mixture/air)
	heat_add(air, air.heat_capacity() * 40, HEAT_SOURCE_OTHER)

/// A heat write to a mixture of each kind fires a temperature-only watch on it.
/datum/unit_test/dq_gas_watch_hears_heat_writes

/datum/unit_test/dq_gas_watch_hears_heat_writes/Run()
	// A main-owned mixture (a machine's own gas).
	var/datum/gas_mixture/tank = allocate(/datum/gas_mixture, 70)
	tank.adjust_gas(/datum/gas/nitrogen, 10)
	heat_set(tank, T20C, HEAT_SOURCE_OTHER)
	TEST_ASSERT(length(gas_watch_heard(tank, GAS_DEPENDENCY_TEMPERATURE, PROC_REF(gas_watch_heat_up))), "heat_set() on a main mixture fired no temperature watch")
	TEST_ASSERT(length(gas_watch_heard(tank, GAS_DEPENDENCY_TEMPERATURE, PROC_REF(gas_watch_heat_move_in))), "heat_add() on a main mixture fired no temperature watch")

	// A pipe network's region.
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
	TEST_ASSERT(pipe_air.arena_id() >= GAS_HANDLE_PIPE_BASE && pipe_air.arena_id() < GAS_HANDLE_TURF_BASE, "the pipeline's air is a pipe region ([pipe_air.arena_id()])")
	pipe_air.adjust_gas(/datum/gas/nitrogen, 10)
	heat_set(pipe_air, T20C, HEAT_SOURCE_OTHER)
	TEST_ASSERT(length(gas_watch_heard(pipe_air, GAS_DEPENDENCY_TEMPERATURE, PROC_REF(gas_watch_heat_up))), "heat_set() on a pipe region fired no temperature watch")
	TEST_ASSERT(length(gas_watch_heard(pipe_air, GAS_DEPENDENCY_TEMPERATURE, PROC_REF(gas_watch_heat_move_in))), "heat_add() on a pipe region fired no temperature watch")

	// A turf's air.
	var/turf/simulated/floor/T = A
	dq_atmos_test_snapshot_air(T)
	dq_atmos_test_isolate_pair(T, T)
	TEST_ASSERT(length(gas_watch_heard(T.air, GAS_DEPENDENCY_TEMPERATURE, PROC_REF(gas_watch_heat_up))), "heat_set() on a turf's air fired no temperature watch")
	heat_set(T.air, T20C, HEAT_SOURCE_OTHER)

/// A machine's gas_watch() on its own mixture (a canister's contents) hears a change of it: the canister's gauge follows an emptied canister
/// with nobody calling its handler.
/datum/unit_test/dq_gas_watch_hears_a_machines_own_mixture

/datum/unit_test/dq_gas_watch_hears_a_machines_own_mixture/Run()
	var/turf/simulated/floor/T = locate() in world
	var/obj/machinery/portable_atmospherics/canister/oxygen/C = allocate(/obj/machinery/portable_atmospherics/canister/oxygen, T)
	var/datum/cap_data/gas_watch/data = gas_watch_data(C)
	TEST_ASSERT_NOTNULL(data?.watch, "the canister watches its contents")
	TEST_ASSERT_EQUAL(data.armed_id, C.air_contents.arena_id(), "on its own mixture")
	dq_gas_watch_test_deliver()
	TEST_ASSERT(C.gauge_band > 1, "a full canister's gauge is up ([C.gauge_band])")
	C.air_contents.clear()
	dq_gas_watch_test_deliver()
	TEST_ASSERT_EQUAL(C.gauge_band, 1, "the gauge did not follow the emptied canister: its watch did not fire")

/// A machine the compiled-in map placed (created before /world/New() rebuilds the native world, which starts with no gas watches) still hears
/// its own mixture: its watch was armed again on the rebuilt world, not left pointing at a watch that no longer exists.
/datum/unit_test/dq_gas_watch_survives_the_world_rebuild_for_map_machines

/datum/unit_test/dq_gas_watch_survives_the_world_rebuild_for_map_machines/Run()
	var/obj/machinery/portable_atmospherics/canister/C
	for(var/obj/machinery/portable_atmospherics/canister/candidate in world)
		if(!candidate.destroyed && candidate.air_contents?.total_moles() > 10 && !candidate.valve_open && gas_watch_data(candidate)?.watch)
			C = candidate
			break
	TEST_ASSERT_NOTNULL(C, "no map-placed canister holding gas")
	var/datum/gas_mixture/saved = new
	saved.copy_from(C.air_contents)
	dq_gas_watch_test_deliver()
	var/band = C.gauge_band
	TEST_ASSERT(band > 1, "a full map canister's gauge is up ([band])")
	C.air_contents.clear()
	dq_gas_watch_test_deliver()
	var/heard = C.gauge_band
	C.air_contents.copy_from(saved)
	dq_gas_watch_test_deliver()
	qdel(saved)
	TEST_ASSERT_EQUAL(heard, 1, "a map canister's gauge did not follow its emptied contents: its gas watch did not fire")

/// Every machine that watches a private mixture of its own arms its watch on that mixture, and a change of it reaches the watch.
/datum/unit_test/dq_gas_watch_private_mixtures_report

/datum/unit_test/dq_gas_watch_private_mixtures_report/Run()
	var/turf/simulated/floor/T = locate() in world
	var/list/kinds = list(
		/obj/machinery/atmospherics/unary/freezer = "air_contents",
		/obj/machinery/atmospherics/unary/heater = "air_contents",
		/obj/machinery/atmospherics/binary/algae_farm = "air1",
		/obj/machinery/portable_atmospherics/canister/air = "air_contents",
	)
	for(var/path in kinds)
		var/air_var = kinds[path]
		var/obj/machinery/M = allocate(path, T)
		var/datum/gas_mixture/air = M.vars[air_var]
		TEST_ASSERT_NOTNULL(air, "[path] has its [air_var]")
		var/datum/cap_data/gas_watch/data = gas_watch_data(M)
		TEST_ASSERT_NOTNULL(data?.watch, "[path] watches its [air_var]")
		TEST_ASSERT_EQUAL(data.armed_id, air.arena_id(), "[path]'s watch is on its own [air_var]")
		dq_gas_watch_test_deliver()
		native_system().drain()
		native_system().take_gas_changes()
		air.adjust_gas(/datum/gas/carbon_dioxide, 40)
		heat_set(air, air.return_temperature() + 50, HEAT_SOURCE_OTHER)
		native_system().drain()
		var/list/changes = native_system().take_gas_changes()
		var/heard = FALSE
		for(var/i in 1 to length(changes) step GAS_DEPENDENCY_OBSERVATION_STRIDE)
			if(changes[i] == data.watch.handle)
				heard = TRUE
		TEST_ASSERT(heard, "[path]'s watch on its own [air_var] heard nothing of a change")

/// Under the test driver (the kernel on its injected clock) time passing delivers gas watches as a live round does: a canister's gauge follows
/// its emptied contents after test_time() with nobody draining the queue by hand.
/datum/unit_test/dq_gas_watch_delivers_under_the_test_clock

/datum/unit_test/dq_gas_watch_delivers_under_the_test_clock/Run()
	test_driver_begin()
	var/turf/simulated/floor/T = locate() in world
	var/obj/machinery/portable_atmospherics/canister/oxygen/C = allocate(/obj/machinery/portable_atmospherics/canister/oxygen, T)
	test_time(5 SECONDS)
	TEST_ASSERT(C.gauge_band > 1, "a full canister's gauge is up ([C.gauge_band])")
	C.air_contents.clear()
	test_time(5 SECONDS)
	var/band = C.gauge_band
	test_driver_end()
	TEST_ASSERT_EQUAL(band, 1, "the test clock did not deliver the canister's gas watch")
