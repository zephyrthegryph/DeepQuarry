#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

// Machine state behaviour (power, breakage, EMP, draw, periodic work): the facts a machine's work depends on, written against what a
// player or another system sees, so they hold while the machine pipeline gives way to stats and every(when =).

/// A machine that draws idle and active power on the equipment channel.
/obj/machinery/dq_draw_probe
	use_power = USE_POWER_IDLE
	idle_power_usage = 10
	active_power_usage = 100
	power_channel = EQUIP

/// Losing power or breaking makes a machine inoperable; restoring either makes it work again.
/datum/unit_test/dq_machine_operable_follows_power_and_repair

/datum/unit_test/dq_machine_operable_follows_power_and_repair/Run()
	var/obj/machinery/igniter/M = allocate(/obj/machinery/igniter, test_floor())
	M.set_powered(TRUE)
	TEST_ASSERT(M.operable(), "a powered whole machine works")
	M.set_powered(FALSE)
	TEST_ASSERT(!M.operable(), "losing power stops it working")
	M.set_powered(TRUE)
	TEST_ASSERT(M.operable(), "restoring power works it again")
	M.stat_add(BROKEN)
	TEST_ASSERT(!M.operable(), "a broken machine does not work")
	M.stat_remove(BROKEN)
	TEST_ASSERT(M.operable(), "a repaired machine works")

/// A pulse holds a machine down for its outage and releases it by itself.
/datum/unit_test/dq_machine_emp_outage_ends

/datum/unit_test/dq_machine_emp_outage_ends/Run()
	test_driver_begin()
	var/obj/machinery/igniter/M = allocate(/obj/machinery/igniter, test_floor())
	M.set_powered(TRUE)
	hold(M, STAT_OPERABLE, FALSE, SRC_EMP, 5 SECONDS)
	TEST_ASSERT(!M.operable(), "a pulse takes the machine down")
	test_time(6 SECONDS)
	TEST_ASSERT(M.operable(), "the outage ended by itself")
	test_driver_end()

/// Switching between idle and active use moves the area's tally by the difference of the two draws; leaving use off removes it.
/datum/unit_test/dq_machine_draw_follows_use_mode

/datum/unit_test/dq_machine_draw_follows_use_mode/Run()
	var/turf/T = test_floor()
	var/area/A = get_area(T)
	var/obj/machinery/dq_draw_probe/M = allocate(/obj/machinery/dq_draw_probe, T)
	var/idle = A.static_equip
	M.set_use_power(USE_POWER_ACTIVE)
	TEST_ASSERT_EQUAL(A.static_equip - idle, 90, "active use adds the difference of the two draws")
	M.set_use_power(USE_POWER_OFF)
	TEST_ASSERT_EQUAL(A.static_equip - idle, -10, "off use drops the whole draw")
	M.set_use_power(USE_POWER_IDLE)
	TEST_ASSERT_EQUAL(A.static_equip, idle, "back to idle restores the tally")

/// A distillery works while it is switched on and parks when switched off.
/datum/unit_test/dq_distillery_work_follows_on

/datum/unit_test/dq_distillery_work_follows_on/Run()
	test_driver_begin()
	var/obj/machinery/portable_atmospherics/powered/reagent_distillery/unit_test/D = allocate(/obj/machinery/portable_atmospherics/powered/reagent_distillery/unit_test, test_floor())
	test_time(MACHINE_SERVICE_INTERVAL + 1)
	TEST_ASSERT(test_machine_idle(D), "a switched-off distillery has no work")
	D.set_on(TRUE)
	test_time(MACHINE_SERVICE_INTERVAL + 1)
	TEST_ASSERT(test_work_allowed(D), "switching it on gives it work")
	D.set_on(FALSE)
	test_time(MACHINE_SERVICE_INTERVAL + 1)
	TEST_ASSERT(test_machine_idle(D), "switching it off parks it again")
	test_driver_end()

/// An unpowered machine with started work does nothing and costs no steps; it resumes by itself when power returns.
/datum/unit_test/dq_machine_work_parks_unpowered

/datum/unit_test/dq_machine_work_parks_unpowered/Run()
	test_driver_begin()
	var/obj/machinery/dq_step_probe/M = allocate(/obj/machinery/dq_step_probe, test_floor())
	M.work = 100
	M.set_powered(FALSE)
	work_start(M)
	test_time(MACHINE_SERVICE_INTERVAL + 1)
	TEST_ASSERT_EQUAL(M.steps, 0, "an unpowered machine's work parked")
	M.set_powered(TRUE)
	test_time(MACHINE_SERVICE_INTERVAL + 1)
	TEST_ASSERT(M.steps > 0, "power returning un-parked it")
	work_stop(M)
	test_driver_end()

#endif
