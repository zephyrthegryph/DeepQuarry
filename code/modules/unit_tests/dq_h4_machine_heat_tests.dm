// H4 (doc/rewrite/temperature.md): machines declare heat_output/heat_dissipation
// (heat_objects.dm) and emit it through their heat body while powered.

/obj/machinery/dq_h4_heater
	name = "test heater"
	use_power = USE_POWER_IDLE
	idle_power_usage = 1000
	heat_output = 1000
	heat_dissipation = 100

/datum/unit_test/dq_h4_machine_heat_regulator

/datum/unit_test/dq_h4_machine_heat_regulator/Run()
	var/obj/machinery/dq_h4_heater/heater = allocate(/obj/machinery/dq_h4_heater, test_floor())
	heater.set_grid_power(TRUE)
	heater.set_broken_condition(FALSE)
	heater.update_heat_output()
	TEST_ASSERT_EQUAL(heater.heat_output_now, 1000, "a powered machine emits its declared heat_output")
	TEST_ASSERT(!isnull(heater.heat_body), "emitting keeps a heat body")
	var/list/properties = heater.thermal_properties()
	TEST_ASSERT_EQUAL(properties[THERMAL_CONDUCTANCE], 100, "heat_dissipation sets the body's conductance")

	heater.set_grid_power(FALSE)
	heater.update_heat_output()
	TEST_ASSERT_EQUAL(heater.heat_output_now, 0, "an unpowered machine emits nothing")

	heater.set_grid_power(TRUE)
	heater.set_broken_condition(TRUE)
	heater.update_heat_output()
	TEST_ASSERT_EQUAL(heater.heat_output_now, 0, "a broken machine emits nothing")

	// The RD server declares heat and only emits while working.
	var/obj/machinery/rnd/server/server = allocate(/obj/machinery/rnd/server, test_floor())
	server.set_grid_power(TRUE)
	server.set_broken_condition(FALSE)
	server.set_maintenance(FALSE)
	release(server, STAT_OPERABLE, SRC_EMP)
	server.research_disabled = FALSE
	server.refresh_working()
	TEST_ASSERT_EQUAL(server.current_heat_output(), server.heat_output, "a working RD server emits its declared heat")
	server.research_disabled = TRUE
	server.refresh_working()
	TEST_ASSERT_EQUAL(server.heat_output_now, 0, "a halted RD server emits nothing")
