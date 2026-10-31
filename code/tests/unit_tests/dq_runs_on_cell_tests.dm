// runs_on_cell() (code/library/machine/runs_on_cell.dm), through the emergency floodlight: the capability owns the cell drain and keeps one tracked
// state var that moves only when the cell crosses the threshold.

/datum/unit_test/dq_runs_on_cell
	abstract_type = /datum/unit_test/dq_runs_on_cell
	var/obj/machinery/floodlight/light

/datum/unit_test/dq_runs_on_cell/Run()
	test_driver_begin()
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	light = allocate(/obj/machinery/floodlight/starts_on, test_floor())
	refresh_flush()
	TEST_ASSERT(light.cell_powered, "a floodlight with a charged cell starts with cell power")
	check()

/datum/unit_test/dq_runs_on_cell/proc/check()
	return

/datum/unit_test/dq_runs_on_cell/steps_drain_without_crossing
/datum/unit_test/dq_runs_on_cell/runs_flat_and_stays_off_when_recharged
/datum/unit_test/dq_runs_on_cell/timer_drains_while_on
/datum/unit_test/dq_runs_on_cell/no_cell

/datum/unit_test/dq_runs_on_cell/steps_drain_without_crossing/check()
	var/need = light.use * CELLRATE
	light.cell.set_charge(need * 3.5)
	for(var/i in 1 to 3)
		var/before = light.cell.charge
		cell_run_step(light)
		TEST_ASSERT(light.cell.charge < before, "step [i] takes charge from the cell")
		TEST_ASSERT(light.cell_powered && light.on, "step [i] leaves the state alone while the cell can feed another")
	cell_run_step(light)
	TEST_ASSERT(!light.cell_powered, "the step that finds the cell short crosses the state")
	TEST_ASSERT(!light.on, "and the light's on_lost switched it off")

/datum/unit_test/dq_runs_on_cell/runs_flat_and_stays_off_when_recharged/check()
	light.cell.set_charge(0)
	cell_run_step(light)
	TEST_ASSERT(!light.cell_powered && !light.on, "a flat cell: no power, light off")
	light.cell.set_charge(light.cell.maxcharge)
	cell_run_step(light)
	TEST_ASSERT(light.cell_powered, "a charged cell has power again")
	TEST_ASSERT(!light.on, "but the light stays off until it is switched on (as before)")
	TEST_ASSERT(light.turn_on(), "and it can be switched on")
	refresh_flush()
	TEST_ASSERT(glow_of(light).range > 0, "and then it casts light")

/datum/unit_test/dq_runs_on_cell/timer_drains_while_on/check()
	var/before = light.cell.charge
	var/list/early = light.rx?.timer_ids ? light.rx.timer_ids.Copy() : list()
	test_time(MACHINE_SERVICE_INTERVAL * 3)
	TEST_ASSERT(light.cell.charge < before, "the timer drains the cell while the light is on (early [json_encode(early)] on [light.on], operable [stat_value(light, STAT_OPERABLE)], has_power [stat_value(light, STAT_HAS_POWER)], timers [json_encode(light.rx?.timer_ids ? light.rx.timer_ids.Copy() : list())], cap [!!cap_of(light, CAP_RUNS_ON_CELL)], gate [condition_holds(light, all_of(nameof(light.on), STAT_OPERABLE))])")
	light.turn_off()
	var/switched_off = light.cell.charge
	test_time(MACHINE_SERVICE_INTERVAL * 3)
	TEST_ASSERT_EQUAL(light.cell.charge, switched_off, "and stops draining when it is off")

/datum/unit_test/dq_runs_on_cell/no_cell/check()
	rel_take(light, nameof(light.cell))
	test_time(1)
	TEST_ASSERT(!light.cell_powered, "taking the cell out crosses the state")
	TEST_ASSERT(!cell_can_feed(light), "no cell feeds nothing")
