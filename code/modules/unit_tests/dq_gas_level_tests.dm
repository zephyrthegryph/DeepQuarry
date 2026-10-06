// Behaviour of the things that sleep on a gas level (doc/rewrite/framework_gaps.md, F5): a device whose work stops until its air reaches a
// state, an object that breaks when its air gets too hot, a material service woken by its surroundings. The tests state what the holder does
// when the gas changes, not how it is told, so they hold through the move from the old watch helpers to the gas_level() capability.

/// Delivers what a gas change published, however the holder listens: the native gas frame, the machine service's gas wakes (the observation
/// stream), the world's crossings on their lane, and the marked drain that runs the holder's reactions.
/proc/dq_gas_level_test_deliver()
	SSair.run_gas_frames(1)
	SSmachines.wake_dirty_gas_subscribers()
	sleep(world.tick_lag * 4)
	SSmachines.wake_dirty_gas_subscribers()
	kernel_drain_now()

/// Runs `M`'s started work once if it is started, as the kernel's interval would.
/proc/dq_gas_level_test_step(obj/machinery/M)
	if(QDELETED(M) || !cap_of(M, CAP_STARTED_WORK) || !work_started(M))
		return
	test_step_machine(M)

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
	var/turf/simulated/floor/T = gas_level_test_room()
	var/turf/simulated/floor/other = locate(T.x + 1, T.y, T.z)
	if(!istype(other) || !other.air)
		other = locate(T.x - 1, T.y, T.z)
	TEST_ASSERT(istype(other) && other.air, "no second floor beside the test floor")
	dq_atmos_test_snapshot_air(other)
	var/obj/machinery/artifact/A = new(T)
	dq_gas_level_test_step(A)
	dq_gas_level_test_deliver()
	dq_gas_level_test_step(A)
	heat_set(other.air, ARTIFACT_HEAT_BREAK + 500, HEAT_SOURCE_OTHER)
	dq_gas_level_test_deliver()
	dq_gas_level_test_step(A)
	TEST_ASSERT(!QDELETED(A), "an artifact broke from the heat of a tile it is not on")
	A.forceMove(other)
	dq_gas_level_test_deliver()
	dq_gas_level_test_step(A)
	TEST_ASSERT(QDELETED(A), "an artifact moved into air past its breaking temperature did not break")

/// A charging disposal bin with no air to draw sleeps; air coming back wakes it.
/datum/unit_test/dq_gas_level_disposal_wakes_when_air_returns

/datum/unit_test/dq_gas_level_disposal_wakes_when_air_returns/Run()
	var/turf/simulated/floor/T = gas_level_test_room()
	var/obj/machinery/disposal/disposal = allocate(/obj/machinery/disposal, T)
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
