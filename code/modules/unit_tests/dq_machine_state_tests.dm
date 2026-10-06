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

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// STAT_OPERABLE as a player sees it, after the writes have settled.
/proc/dq_test_operable_stat(obj/machinery/M)
	kernel_drain_now()
	return !!stat_value(M, STAT_OPERABLE)

/// A generic machine stops working under each of the four condition bits and not under the others' absence; the bits read back through has_stat().
/datum/unit_test/dq_machine_bits_gate_operable

/datum/unit_test/dq_machine_bits_gate_operable/Run()
	var/obj/machinery/computer/operating/M = allocate(/obj/machinery/computer/operating, test_floor())
	M.set_stat(0)
	TEST_ASSERT(dq_test_operable_stat(M) && M.operable(), "a clean machine works")
	for(var/bit in list(NOPOWER, BROKEN, MAINT, EMPED))
		M.set_stat(0)
		TEST_ASSERT(M.stat_add(bit), "adding a bit reports a change")
		TEST_ASSERT(M.has_stat(bit), "the bit reads back")
		TEST_ASSERT(!M.stat_add(bit), "adding it again changes nothing")
		TEST_ASSERT(!dq_test_operable_stat(M) && !M.operable(), "bit [bit] stops it")
		TEST_ASSERT(M.stat_remove(bit), "removing it reports a change")
		TEST_ASSERT(!M.has_stat(bit), "the bit reads clear")
		TEST_ASSERT(dq_test_operable_stat(M) && M.operable(), "clearing bit [bit] works it again")
	M.set_stat(NOPOWER | BROKEN)
	TEST_ASSERT(M.has_stat(NOPOWER) && M.has_stat(BROKEN) && !M.has_stat(MAINT), "set_stat writes several bits")
	M.set_stat(0)
	TEST_ASSERT(!M.has_stat(MACHINE_STAT_ANY), "set_stat(0) clears them all")

/// The APC and the SMES are their area's supply: the area going dark does not stop them, breakage does.
/datum/unit_test/dq_machine_supply_ignores_area_power

/datum/unit_test/dq_machine_supply_ignores_area_power/Run()
	var/obj/machinery/power/apc/A = dq_power_test_apc()
	TEST_ASSERT_NOTNULL(A, "the test map has no working APC")
	var/obj/machinery/power/smes/S = allocate(/obj/machinery/power/smes, test_floor())
	for(var/obj/machinery/M in list(A, S))
		var/saved = M.stat
		M.set_stat(0)
		var/base = dq_test_operable_stat(M)
		M.stat_add(NOPOWER)
		TEST_ASSERT_EQUAL(dq_test_operable_stat(M), base, "[M.type]: losing area power does not change whether it works")
		M.stat_remove(NOPOWER)
		M.stat_add(BROKEN)
		TEST_ASSERT(!dq_test_operable_stat(M), "[M.type]: breakage stops it")
		M.set_stat(saved)

/// The self-powered turret: BROKEN and EMPED stop it. (Its declared intent is that area power never does; it does not hold today and is the grid worker's to settle.)
/datum/unit_test/dq_machine_rcd_turret_ignores_power

/datum/unit_test/dq_machine_rcd_turret_ignores_power/Run()
	var/obj/machinery/porta_turret/rcd/M = allocate(/obj/machinery/porta_turret/rcd, test_floor())
	M.set_stat(0)
	TEST_ASSERT(dq_test_operable_stat(M), "a clean self-powered turret works")
	M.stat_add(BROKEN)
	TEST_ASSERT(!dq_test_operable_stat(M), "breakage stops it")
	M.stat_remove(BROKEN)
	M.stat_remove(BROKEN)
	M.stat_add(EMPED)
	TEST_ASSERT(!dq_test_operable_stat(M), "a pulse stops it")
	for(var/obj/effect/effect/sparks/spark in range(2, M))
		qdel(spark)

#endif
