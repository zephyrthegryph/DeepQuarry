/// Regression tests for the track F fixes B2, B4, B8, Q11, Q13 and Q14
/// (doc/rewrite/fixes.md).

/// B2: every fire_act override takes (exposed_temperature, exposed_volume). A
/// window read the volume as the temperature, so a hot hotspot never hurt it
/// and a cool one with a big volume did.
/datum/unit_test/dq_fire_act_reads_temperature

/datum/unit_test/dq_fire_act_reads_temperature/Run()
	// H3: an exposure heats the object's body; damage comes from its rules.
	// The shared test floor (test_floor() always returns the same turf) can
	// be left hot by an earlier heat test; reset it so "before" is a known
	// room-temperature baseline and the exposure is guaranteed to be an
	// actual increase.
	dq_h3_cool_floor(test_floor())
	var/obj/structure/window/hot = allocate(/obj/structure/window, test_floor())
	var/before = hot.get_temperature()
	hot.fire_act(hot.maximal_heat + 500, 1)
	var/hot_gain = hot.get_temperature() - before
	TEST_ASSERT(hot_gain > 0, "a hot exposure did not heat the window")

	var/obj/structure/window/cool = allocate(/obj/structure/window, test_floor())
	before = cool.get_temperature()
	cool.fire_act(T20C, CELL_VOLUME * 10)
	var/cool_gain = cool.get_temperature() - before
	TEST_ASSERT(cool_gain < hot_gain, "a room-temperature exposure with a large volume heated the window as much as a hot one ([cool_gain] vs [hot_gain])")

/// Q11 (was the SSmachines roster; roadmap S5): work_start() gives a machine work, work_stop() ends it, and neither disturbs another machine.
/datum/unit_test/dq_machine_roster_swap_remove

/datum/unit_test/dq_machine_roster_swap_remove/Run()
	var/turf/T = test_floor()
	var/list/machines = list()
	for(var/i in 1 to 3)
		var/obj/machinery/dq_step_probe/M = allocate(/obj/machinery/dq_step_probe, T)
		M.work = 100
		work_start(M)
		machines += M
	var/obj/machinery/middle = machines[2]
	work_stop(middle)
	TEST_ASSERT(!machine_stepping(middle), "stopped machine still has step work")
	TEST_ASSERT(machine_stepping(machines[1]) && machine_stepping(machines[3]), "stopping one machine stopped another")
	work_start(middle)
	TEST_ASSERT(machine_stepping(middle), "restarted machine has no step work")

/// B8: a wall's heat transfer coefficient follows its material instead of
/// always clamping to the maximum.
/datum/unit_test/dq_wall_conductance_uses_material

/datum/unit_test/dq_wall_conductance_uses_material/Run()
	var/datum/material/steel = get_material_by_name(MAT_STEEL)
	var/datum/material/glass = get_material_by_name(MAT_GLASS)
	TEST_ASSERT_NOTNULL(steel, "no steel material")
	TEST_ASSERT_NOTNULL(glass, "no glass material")
	var/steel_coefficient = steel.thermal_conductance(2.5, 0.25, T20C) / WALL_CONDUCTANCE_PER_TRANSFER_COEFFICIENT
	var/glass_coefficient = glass.thermal_conductance(2.5, 0.25, T20C) / WALL_CONDUCTANCE_PER_TRANSFER_COEFFICIENT
	TEST_ASSERT(steel_coefficient < WALL_MAX_HEAT_TRANSFER_COEFFICIENT, "steel walls still hit the conductance cap ([steel_coefficient])")
	TEST_ASSERT(glass_coefficient < steel_coefficient, "glass conducts no worse than steel ([glass_coefficient] vs [steel_coefficient])")

	var/turf/simulated/wall/W
	for(var/turf/simulated/wall/candidate in world)
		if(candidate.material?.name == MAT_STEEL && !candidate.reinf_material)
			W = candidate
			break
	if(!W)
		return
	W.update_material()
	TEST_ASSERT(W.thermal_conductivity < WALL_MAX_HEAT_TRANSFER_COEFFICIENT, "steel wall still clamps to the maximum coefficient ([W.thermal_conductivity])")

/// Q14: a leak on one pipe network wakes only the shutoff valves on it.
/datum/unit_test/dq_shutoff_wake_is_network_local

/datum/unit_test/dq_shutoff_wake_is_network_local/Run()
	test_driver_begin()
	var/obj/machinery/atmospherics/valve/shutoff/valve = allocate(/obj/machinery/atmospherics/valve/shutoff, test_floor())
	var/datum/pipe_network/ours = new()
	var/datum/pipe_network/theirs = new()
	rel_set(valve, nameof(valve.network_node1), ours)
	test_time(1 SECOND)

	// A change on another network leaves the valve alone; its own network makes it look again.
	TEST_ASSERT(!after_pending(valve, "leak_check"), "the valve had a check pending before any change")
	wake_automatic_shutoff_valves(theirs)
	TEST_ASSERT(!after_pending(valve, "leak_check"), "a change on another network woke the valve")
	wake_automatic_shutoff_valves(ours)
	TEST_ASSERT(after_pending(valve, "leak_check"), "a change on its own network did not wake the valve")
	test_time(1 SECOND)
	test_driver_end()

	rel_clear(valve, nameof(valve.network_node1))
	qdel(ours)
	qdel(theirs)
