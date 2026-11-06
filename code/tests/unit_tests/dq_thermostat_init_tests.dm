// A freezer or heater decides whether it works when it is made (after_init(0, reconsider) in its CAPABILITIES block), not at the first gas wake or switch after
// the map loads: a powered one reads pumping from the start.

/// A freezer that is switched on from the start, as a mapped one is.
/obj/machinery/atmospherics/unary/freezer/dq_test_on
	use_power = USE_POWER_IDLE

/// A heater that is switched on from the start.
/obj/machinery/atmospherics/unary/heater/dq_test_on
	use_power = USE_POWER_IDLE

/datum/unit_test/dq_freezer_decides_at_init

/datum/unit_test/dq_freezer_decides_at_init/Run()
	var/turf/simulated/floor/T = dq_test_powered_floor()
	TEST_ASSERT_NOTNULL(T, "no powered floor for the freezer init test")
	var/obj/machinery/atmospherics/unary/freezer/dq_test_on/cooler = allocate(/obj/machinery/atmospherics/unary/freezer/dq_test_on, T)
	TEST_ASSERT(cooler.pumping, "a freshly made, switched-on freezer has not decided it works (pumping stayed [cooler.pumping])")
	var/obj/machinery/atmospherics/unary/freezer/off = allocate(/obj/machinery/atmospherics/unary/freezer, T)
	TEST_ASSERT(!off.pumping, "a freshly made freezer that is switched off pumps")

/datum/unit_test/dq_heater_decides_at_init

/datum/unit_test/dq_heater_decides_at_init/Run()
	var/turf/simulated/floor/T = dq_test_powered_floor()
	TEST_ASSERT_NOTNULL(T, "no powered floor for the heater init test")
	var/obj/machinery/atmospherics/unary/heater/dq_test_on/warmer = allocate(/obj/machinery/atmospherics/unary/heater/dq_test_on, T)
	TEST_ASSERT(warmer.pumping, "a freshly made, switched-on heater has not decided it works (pumping stayed [warmer.pumping])")
	var/obj/machinery/atmospherics/unary/heater/off = allocate(/obj/machinery/atmospherics/unary/heater, T)
	TEST_ASSERT(!off.pumping, "a freshly made heater that is switched off pumps")
