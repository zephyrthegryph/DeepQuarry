// The leftover-air guard (unit_test_air_guard() in unit_test.dm): it must catch what the lingering-fire bridge test once left behind, and the
// turfs it does not judge must be the ones that change by design on an idle world.

/// The pre-fix dq_lingering_fire_bridge: take the first air-bearing turf, add fuel and oxidizer, light a fire, and never put the air back. The guard
/// must report the turf and put its air back.
/datum/unit_test/dq_air_guard_catches_lingering_fire_polluter

/datum/unit_test/dq_air_guard_catches_lingering_fire_polluter/Run()
	var/turf/simulated/T = null
	for(var/turf/simulated/sim_turf in world)
		if(sim_turf.air && !sim_turf.blocks_air)
			T = sim_turf
			break
	TEST_ASSERT_NOTNULL(T, "no simulated turf with air")
	var/hotspots_before = REGISTRY_COUNT(REGISTRY_HOTSPOTS)
	restore_occupant_heat_after(T) // the fire heats what stands on the floor (here the bridge's grille and windows), and they warm the air of every later test
	var/list/before = unit_test_air_snapshot()
	var/oxygen_before = T.air.get_moles(/datum/gas/oxygen)
	// The old test body, minus the snapshot call that fixed it.
	T.air.adjust_gas(/datum/gas/plasma, 30)
	T.air.adjust_gas(/datum/gas/oxygen, 80)
	heat_set(T.air, T20C, HEAT_SOURCE_OTHER)
	T.feed_lingering_fire(2.0)
	log_test("AIR GUARD POLLUTER: fire lit on ([T.x],[T.y],[T.z]) in [get_area(T)], hotspot [T.active_hotspot ? "burning" : "none"], air [round(T.air.return_temperature(), 0.1)] K")
	var/leaked = unit_test_air_guard(before, hotspots_before, "dq_air_guard_catches_lingering_fire_polluter", quiet = TRUE)
	TEST_ASSERT(leaked >= 1, "the guard did not see the turf the fire test left with 80 more moles of oxygen")
	TEST_ASSERT(abs(T.air.get_moles(/datum/gas/oxygen) - oxygen_before) < 1, "the guard did not put the turf's oxygen back ([T.air.get_moles(/datum/gas/oxygen)] vs [oxygen_before])")
	if(T.active_hotspot)
		qdel(T.active_hotspot)
		T.active_hotspot = null

/// The machine guard judges only the machines in the areas a test touched; the full compare (every UNIT_TEST_FULL_COMPARE_EVERY tests and at the end of the run) finds a change made
/// anywhere else. A machine setting changed in a room the test never touched is missed by the scoped pass and caught by the full one, and the baseline then follows it.
/datum/unit_test/dq_guard_full_compare_catches_untouched_machine

/datum/unit_test/dq_guard_full_compare_catches_untouched_machine/Run()
	var/datum/unit_test_guard/guard = unit_test_guard_session()
	var/obj/machinery/alarm/A
	for(var/obj/machinery/alarm/candidate in guard.machine_state)
		if(!QDELETED(candidate) && candidate.use_power == USE_POWER_IDLE)
			A = candidate
			break
	TEST_ASSERT_NOTNULL(A, "no idle air alarm to seed")
	defer_cleanup(A, TYPE_PROC_REF(/obj/machinery/alarm, set_use_power), USE_POWER_IDLE) // the world gets its alarm back whatever the asserts do
	A.set_use_power(USE_POWER_ACTIVE)
	var/list/scoped = list()
	guard.judge_machines("dq_guard_seed", list(), scoped, quiet = TRUE) // no area touched: not judged
	TEST_ASSERT_EQUAL(length(scoped), 0, "the scoped pass judged a machine in an area the test never touched")
	var/list/full = list()
	guard.judge_machines("dq_guard_seed", null, full, TRUE, TRUE)
	TEST_ASSERT(length(full) >= 1, "the full compare did not see the changed alarm")
	// The baseline followed the change: put the alarm back and let the guard take it as the new baseline, so the runner's own compare of this test finds nothing.
	A.set_use_power(USE_POWER_IDLE)
	guard.judge_machines("dq_guard_seed", null, list(), TRUE, TRUE)
