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
		P.set_dir(direction | REVERSE_DIR(direction))
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

/// A turf's air read, and watched, before SSair registers the turfs (the point a mapped sensor's init reads at) is the turf's real air, and the watch
/// is still the turf's after they register: ordering stops mattering. The turf is put back in the state map load leaves it in (its air a main-owned
/// mixture, not yet in the field), then registered the way SSair.setup_allturfs() registers it.
/datum/unit_test/dq_early_air_reads_and_watches_survive_registration

/datum/unit_test/dq_early_air_reads_and_watches_survive_registration/Run()
	var/turf/open/T
	for(var/turf/simulated/floor/candidate in world)
		if(!candidate.blocks_air && !candidate.immutable_atmos && !candidate.planetary_atmos && candidate.air && candidate.z <= 3)
			T = candidate
			break
	TEST_ASSERT_NOTNULL(T, "no mapped open floor with its own air")
	dq_atmos_test_snapshot_air(T)
	var/was_initialized = SSair.initialized
	T.update_air_ref(-1)
	rel_set(T, nameof(T.air), T.create_gas_mixture())
	TEST_ASSERT(T.air.arena_id() < GAS_HANDLE_PIPE_BASE, "the turf's air is a main-owned mixture before it registers ([T.air.arena_id()])")
	SSair.initialized = FALSE
	var/reads_before = GLOB.early_air_reads
	var/datum/gas_mixture/early_air = T.return_air()
	var/early_pressure = early_air.return_pressure()
	var/early_arena_id = early_air.arena_id()
	SSair.initialized = was_initialized
	TEST_ASSERT_EQUAL(GLOB.early_air_reads, reads_before + 1, "an early read is counted")
	TEST_ASSERT(early_pressure > 50, "an early read of a mapped floor's air reads its real pressure, not vacuum ([early_pressure])")
	dq_gas_watch_test_deliver()
	var/datum/gas_watch_test_ear/ear = allocate(/datum/gas_watch_test_ear)
	var/datum/native_watch/gas/W = gas_dependency_watch(ear, early_arena_id, GAS_DEPENDENCY_PRESSURE, TYPE_PROC_REF(/datum/gas_watch_test_ear, heard))
	T.update_air_ref(0, T.air_block_mask())
	TEST_ASSERT(T.air.arena_id() >= GAS_HANDLE_TURF_BASE, "registration moved the turf's air into its field cell ([T.air.arena_id()])")
	TEST_ASSERT_EQUAL(round(T.return_air().return_pressure(), 0.1), round(early_pressure, 0.1), "the reading is the same either side of registration")
	dq_gas_watch_test_deliver()
	ear.masks.Cut()
	T.air.adjust_gas(/datum/gas/oxygen, 50)
	dq_gas_watch_test_deliver()
	TEST_ASSERT(length(ear.masks), "a watch armed before the turf registered heard nothing after it did")
	qdel(W)

/// What initializes on a turf before the turf's own Initialize() finds the turf's real air already made (settle_air(), from InitAtom()), and the turf's own
/// setup keeps that one mixture instead of making a second.
/datum/unit_test/dq_settled_turf_air_is_the_one_the_turfs_setup_keeps

/datum/unit_test/dq_settled_turf_air_is_the_one_the_turfs_setup_keeps/Run()
	var/turf/open/T
	for(var/turf/simulated/floor/candidate in world)
		if(!candidate.blocks_air && !candidate.immutable_atmos && !candidate.planetary_atmos && candidate.air && candidate.z <= 3)
			T = candidate
			break
	TEST_ASSERT_NOTNULL(T, "no mapped open floor with its own air")
	dq_atmos_test_snapshot_air(T)
	T.update_air_ref(-1)
	rel_clear(T, nameof(T.air))
	T.flags &= ~ATOM_INITIALIZED
	TEST_ASSERT_NULL(T.air, "the turf is back before its own Initialize()")
	T.settle_air()
	var/datum/gas_mixture/made = T.air
	TEST_ASSERT_NOTNULL(made, "settle_air() made the turf's air")
	var/pressure = made.return_pressure()
	T.settle_air() // a second thing initializing on it
	T.flags |= ATOM_INITIALIZED
	T.setup_open_air() // the turf's own Initialize() setup, which finds the air made
	TEST_ASSERT(pressure > 50, "the air made before the turf's own Initialize() is its real air, not vacuum ([pressure])")
	TEST_ASSERT(T.air == made, "the turf's own setup kept the one mixture")
	T.update_air_ref(0, T.air_block_mask())
