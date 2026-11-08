// The leftover-air guard (unit_test_air_guard() in unit_test.dm): it must catch what the lingering-fire bridge test once left behind, and the
// turfs it does not judge must be the ones that change by design on an idle world.

/// The pre-fix dq_lingering_fire_bridge: take the first air-bearing turf, add fuel and oxidizer, light a fire, and never put the air back. The guard
/// must report the turf and put its air back.
/datum/unit_test/dq_air_guard_catches_lingering_fire_polluter

/datum/unit_test/dq_air_guard_catches_lingering_fire_polluter/Run()
	var/turf/simulated/T = null
	for(var/turf/simulated/sim_turf in world)
		if(sim_turf.turf_air() && !sim_turf.blocks_air)
			T = sim_turf
			break
	TEST_ASSERT_NOTNULL(T, "no simulated turf with air")
	var/hotspots_before = REGISTRY_COUNT(REGISTRY_HOTSPOTS)
	restore_occupant_heat_after(T) // the fire heats what stands on the floor (here the bridge's grille and windows), and they warm the air of every later test
	var/list/before = unit_test_air_snapshot()
	var/oxygen_before = T.turf_air().get_moles(/datum/gas/oxygen)
	// The old test body, minus the snapshot call that fixed it.
	T.turf_air().adjust_gas(/datum/gas/plasma, 30)
	T.turf_air().adjust_gas(/datum/gas/oxygen, 80)
	heat_set(T.turf_air(), T20C, HEAT_SOURCE_OTHER)
	T.feed_lingering_fire(2.0)
	log_test("AIR GUARD POLLUTER: fire lit on ([T.x],[T.y],[T.z]) in [get_area(T)], hotspot [T.active_hotspot ? "burning" : "none"], air [round(T.turf_air().return_temperature(), 0.1)] K")
	var/leaked = unit_test_air_guard(before, hotspots_before, "dq_air_guard_catches_lingering_fire_polluter", quiet = TRUE)
	TEST_ASSERT(leaked >= 1, "the guard did not see the turf the fire test left with 80 more moles of oxygen")
	TEST_ASSERT(abs(T.turf_air().get_moles(/datum/gas/oxygen) - oxygen_before) < 1, "the guard did not put the turf's oxygen back ([T.turf_air().get_moles(/datum/gas/oxygen)] vs [oxygen_before])")
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
		if(!QDELETED(candidate) && candidate.use_power == USE_POWER_IDLE && !guard.drifted_areas[get_area(candidate)])
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

/// A floor replaced during a test (taken to space and back, a breach repaired) is judged through the air standing there now: unchanged, it is no leak.
/datum/unit_test/dq_air_guard_judges_a_replaced_turf_by_its_current_air

/datum/unit_test/dq_air_guard_judges_a_replaced_turf_by_its_current_air/Run()
	var/turf/open/T = run_loc_floor_bottom_left
	var/original = T.type
	var/list/before = unit_test_air_snapshot()
	var/moles_before = T.turf_air().total_moles()
	var/turf/S = T.ChangeTurf(/turf/space)
	var/turf/open/back = S.ChangeTurf(original)
	var/list/only = list()
	only[back] = TRUE
	var/list/diff = unit_test_air_diff(before, only = only)
	log_test("AIR GUARD REPLACED: ([back.x],[back.y],[back.z]) [round(moles_before, 0.1)] -> [round(back.turf_air().total_moles(), 0.1)] mol; guard says [diff["leaked"]] leak(s) [jointext(diff["examples"], "; ")]")
	TEST_ASSERT_EQUAL(diff["leaked"], 0, "the guard called a floor put back as it was a leak: [jointext(diff["examples"], "; ")]")

/// The guard stays strict on a replaced floor: gas added to the floor that stands there after the change is still a leak, and is put back.
/datum/unit_test/dq_air_guard_catches_gas_on_a_replaced_turf

/datum/unit_test/dq_air_guard_catches_gas_on_a_replaced_turf/Run()
	var/turf/open/T = run_loc_floor_bottom_left
	var/original = T.type
	var/list/before = unit_test_air_snapshot()
	var/nitrogen_before = T.turf_air().get_moles(/datum/gas/nitrogen)
	var/turf/S = T.ChangeTurf(/turf/space)
	var/turf/open/back = S.ChangeTurf(original)
	back.turf_air().adjust_gas(/datum/gas/nitrogen, 200)
	var/list/only = list()
	only[back] = TRUE
	var/list/diff = unit_test_air_diff(before, TRUE, only = only)
	TEST_ASSERT(diff["leaked"] >= 1, "the guard missed 200 mol of nitrogen added to a replaced floor")
	TEST_ASSERT(abs(back.turf_air().get_moles(/datum/gas/nitrogen) - nitrogen_before) < 1, "the guard did not put the replaced floor's nitrogen back ([back.turf_air().get_moles(/datum/gas/nitrogen)] vs [nitrogen_before])")


/// The block reset puts a floor's solid temperature back to the heat guard's session baseline, not to T20C: a floor that settled with its room
/// (the test room's sit near 286 K) comes back where it was, so a test that lets time pass is not blamed for the reset's own write. The baseline is
/// set to 270 K for the test (T20C would not tell the two apart), and the tolerance is measured: a solid write lands at the next world step, and
/// that same step conducts the floor toward its room, so a direct write of 270 K followed by one step gives the drift a correct reset may show.
/datum/unit_test/dq_block_reset_restores_session_floor_temperature

/datum/unit_test/dq_block_reset_restores_session_floor_temperature/Run()
	var/datum/unit_test_guard/guard = unit_test_guard_session()
	var/turf/open/T = run_loc_floor_bottom_left
	var/list/turfs = guard.solids["turfs"]
	var/list/kelvin = guard.solids["k"]
	var/i = turfs.Find(T)
	TEST_ASSERT(i, "the heat guard does not watch the block floor")
	var/session = kelvin[i]
	kelvin[i] = 270
	// Control: the drift of one step after a direct write of the target.
	heat_set_solid(T, 270)
	SSair.run_gas_frames(1)
	var/list/control = vg_heat_turf_temperatures(list(T))
	var/drift = abs(control[1] - 270)
	heat_set_solid(T, 330)
	SSair.run_gas_frames(1)
	unit_test_block_reset_turf(T)
	SSair.run_gas_frames(1)
	var/list/now = vg_heat_turf_temperatures(list(T))
	log_test("BLOCK RESET SOLID: ([T.x],[T.y],[T.z]) baseline 270 K, one-step drift of a direct write [round(drift, 0.01)] K, after reset [round(now[1], 0.01)] K")
	kelvin[i] = session
	heat_set_solid(T, session)
	SSair.run_gas_frames(1)
	TEST_ASSERT(abs(now[1] - 270) <= drift + 0.5, "the reset left the floor at [now[1]] K: its session baseline is 270 K, and one step after a direct write drifts [drift] K")
	TEST_ASSERT(abs(now[1] - T20C) > 10, "the reset put the floor at T20C ([now[1]] K), not its session baseline")
