// H4 (doc/rewrite/temperature.md): machines declare heat_output/heat_dissipation
// (heat_objects.dm) and emit it through their heat body while powered.

/obj/machinery/dq_h4_heater
	name = "test heater"
	use_power = USE_POWER_IDLE

CAPABILITIES(/obj/machinery/dq_h4_heater)
	configure(machine_heat(output = 1000, dissipation = 100))
	configure(uses_power(idle = 1000))

/datum/unit_test/dq_h4_machine_heat_regulator

/datum/unit_test/dq_h4_machine_heat_regulator/Run()
	var/obj/machinery/dq_h4_heater/heater = allocate(/obj/machinery/dq_h4_heater, test_floor())
	heater.set_grid_power(TRUE)
	heater.set_broken_condition(FALSE)
	heater.update_heat_output()
	TEST_ASSERT_EQUAL(emitted_machine_heat(heater), 1000, "a powered machine emits its declared heat_output")
	TEST_ASSERT(!isnull(heater.heat_body), "emitting keeps a heat body")
	var/list/properties = heater.thermal_properties()
	TEST_ASSERT_EQUAL(properties[THERMAL_CONDUCTANCE], 100, "heat_dissipation sets the body's conductance")

	heater.set_grid_power(FALSE)
	heater.update_heat_output()
	TEST_ASSERT_EQUAL(emitted_machine_heat(heater), 0, "an unpowered machine emits nothing")

	heater.set_grid_power(TRUE)
	heater.set_broken_condition(TRUE)
	heater.update_heat_output()
	TEST_ASSERT_EQUAL(emitted_machine_heat(heater), 0, "a broken machine emits nothing")

	// The RD server declares heat and only emits while working.
	var/obj/machinery/rnd/server/server = allocate(/obj/machinery/rnd/server, test_floor())
	server.set_grid_power(TRUE)
	server.set_broken_condition(FALSE)
	server.set_maintenance(FALSE)
	release(server, STAT_OPERABLE, SRC_EMP)
	server.research_disabled = FALSE
	server.refresh_working()
	TEST_ASSERT_EQUAL(server.current_heat_output(), machine_heat_of(server).output, "a working RD server emits its declared heat")
	server.research_disabled = TRUE
	server.refresh_working()
	TEST_ASSERT_EQUAL(emitted_machine_heat(server), 0, "a halted RD server emits nothing")

/obj/machinery/dq_h4_heater/inherited
CAPABILITIES(/obj/machinery/dq_h4_heater/inherited)
	configure(machine_heat(output = 250))

/obj/machinery/dq_h4_heater/default_conductance
CAPABILITIES(/obj/machinery/dq_h4_heater/default_conductance)
	configure(machine_heat(dissipation = TRAIT_NONE))

/datum/unit_test/dq_h4_machine_heat_trait_home
/datum/unit_test/dq_h4_machine_heat_trait_home/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	var/datum/type_trait/machine_heat/base = machine_heat_of_type(/obj/machinery)
	TEST_ASSERT_EQUAL(base.output, 0, "unconfigured machinery emits no heat")
	TEST_ASSERT_NULL(base.dissipation, "unconfigured machinery retains default conductance")
	var/datum/type_trait/machine_heat/child = machine_heat_of_type(/obj/machinery/dq_h4_heater/inherited)
	TEST_ASSERT_EQUAL(child.output, 250, "a child overrides declared wattage")
	TEST_ASSERT_EQUAL(child.dissipation, 100, "unnamed conductance is inherited")
	TEST_ASSERT_NULL(machine_heat_of_type(/obj/machinery/dq_h4_heater/default_conductance).dissipation, "explicit TRAIT_NONE restores default conductance")
	var/obj/machinery/dq_h4_heater/A = allocate(/obj/machinery/dq_h4_heater, test_floor())
	var/obj/machinery/dq_h4_heater/B = allocate(/obj/machinery/dq_h4_heater, test_floor())
	TEST_ASSERT(machine_heat_of(A) == machine_heat_of(B), "unmodified siblings share their type configuration")
	var/list/old_field = type_trait_field_for_var(A, "heat_output")
	TEST_ASSERT(old_field && old_field[1] == ENTRY_MACHINE_HEAT && old_field[2] == "output", "legacy map and VV names resolve to the real trait field")
	TEST_ASSERT(set_trait(A, old_field[1], old_field[2], 750), "an instance override takes effect through the native writer")
	TEST_ASSERT_EQUAL(machine_heat_of(A).output, 750, "the modified machine reads its own override")
	TEST_ASSERT_EQUAL(machine_heat_of(B).output, 1000, "a sibling retains the original type default")
	TEST_ASSERT_EQUAL(machine_heat_of_type(/obj/machinery/dq_h4_heater).output, 1000, "the shared type remains unchanged")
	A.set_heat_output(0)
	TEST_ASSERT(!sparse_has(A, heat_output_now), "an idle machine retains no optional output slot")
