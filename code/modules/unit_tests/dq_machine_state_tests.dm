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
	M.set_broken_condition(TRUE)
	TEST_ASSERT(!M.operable(), "a broken machine does not work")
	M.set_broken_condition(FALSE)
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

/// Switching between idle and active use moves the area's demand by the difference of the two draws; leaving use off removes it.
/datum/unit_test/dq_machine_draw_follows_use_mode

/datum/unit_test/dq_machine_draw_follows_use_mode/Run()
	var/turf/T = test_floor()
	var/area/A = get_area(T)
	var/obj/machinery/dq_draw_probe/M = allocate(/obj/machinery/dq_draw_probe, T)
	var/idle = dq_grid_demand(A, EQUIP)
	M.set_use_power(USE_POWER_ACTIVE)
	TEST_ASSERT_EQUAL(dq_grid_demand(A, EQUIP) - idle, 90, "active use adds the difference of the two draws")
	M.set_use_power(USE_POWER_OFF)
	TEST_ASSERT_EQUAL(dq_grid_demand(A, EQUIP) - idle, -10, "off use drops the whole draw")
	M.set_use_power(USE_POWER_IDLE)
	TEST_ASSERT_EQUAL(dq_grid_demand(A, EQUIP), idle, "back to idle restores the demand")

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

/// A generic machine stops working while any of power, wholeness or maintenance holds it; a pulse is a timed hold; the switch does not stop it.
/datum/unit_test/dq_machine_bits_gate_operable

/datum/unit_test/dq_machine_bits_gate_operable/Run()
	var/obj/machinery/computer/operating/M = allocate(/obj/machinery/computer/operating, test_floor())
	M.set_grid_power(TRUE)
	TEST_ASSERT(dq_test_operable_stat(M) && M.operable(), "a clean machine works")
	TEST_ASSERT(M.set_grid_power(FALSE), "losing power reports a change")
	TEST_ASSERT(M.power_lost() && M.power_lost(), "the reader says so")
	TEST_ASSERT(!M.set_grid_power(FALSE), "again changes nothing")
	TEST_ASSERT(!dq_test_operable_stat(M) && !M.operable(), "no power stops it")
	TEST_ASSERT(M.set_grid_power(TRUE) && dq_test_operable_stat(M) && M.operable(), "power back works it again")
	TEST_ASSERT(M.set_broken_condition(TRUE) && M.broken_now(), "breaking reports a change")
	TEST_ASSERT(!dq_test_operable_stat(M) && !M.operable(), "broken stops it")
	TEST_ASSERT(M.set_broken_condition(FALSE) && dq_test_operable_stat(M), "mended works it again")
	TEST_ASSERT(M.set_maintenance(TRUE) && M.under_maintenance(), "maintenance reports a change")
	TEST_ASSERT(!dq_test_operable_stat(M) && !M.operable(), "maintenance stops it")
	TEST_ASSERT(M.set_maintenance(FALSE) && dq_test_operable_stat(M), "out of maintenance works it again")
	hold(M, STAT_OPERABLE, FALSE, SRC_EMP, 30 SECONDS)
	TEST_ASSERT(M.emp_held() && !M.operable(), "a pulse stops it")
	release(M, STAT_OPERABLE, SRC_EMP)
	TEST_ASSERT(M.operable(), "and releases")
	TEST_ASSERT(M.set_switched_on(FALSE) && M.switched_off(), "the switch reports a change")
	TEST_ASSERT(M.operable(), "the switch alone does not stop it working")
	TEST_ASSERT(M.has_condition(), "but it is a condition")
	M.set_switched_on(TRUE)
	TEST_ASSERT(!M.has_condition(), "all clear")

/// The APC and the SMES are their area's supply: the area going dark does not stop them, breakage does.
/datum/unit_test/dq_machine_supply_ignores_area_power

/datum/unit_test/dq_machine_supply_ignores_area_power/Run()
	var/obj/machinery/power/apc/A = dq_power_test_apc()
	TEST_ASSERT_NOTNULL(A, "the test map has no working APC")
	var/obj/machinery/power/smes/S = allocate(/obj/machinery/power/smes, test_floor())
	for(var/obj/machinery/M in list(A, S))
		var/was_dark = M.power_lost()
		var/was_broken = M.broken_now()
		M.set_broken_condition(FALSE)
		M.set_grid_power(TRUE)
		var/base = dq_test_operable_stat(M)
		M.set_grid_power(FALSE)
		TEST_ASSERT_EQUAL(dq_test_operable_stat(M), base, "[M.type]: losing area power does not change whether it works")
		M.set_grid_power(TRUE)
		M.set_broken_condition(TRUE)
		TEST_ASSERT(!dq_test_operable_stat(M), "[M.type]: breakage stops it")
		M.set_broken_condition(was_broken)
		M.set_grid_power(!was_dark)

/// The self-powered turret: BROKEN and EMPED stop it. (Its declared intent is that area power never does; it does not hold today and is the grid worker's to settle.)
/datum/unit_test/dq_machine_rcd_turret_ignores_power

/datum/unit_test/dq_machine_rcd_turret_ignores_power/Run()
	var/obj/machinery/porta_turret/rcd/M = allocate(/obj/machinery/porta_turret/rcd, test_floor())
	dq_machine_clear(M)
	TEST_ASSERT(dq_test_operable_stat(M), "a clean self-powered turret works")
	M.set_broken_condition(TRUE)
	TEST_ASSERT(!dq_test_operable_stat(M), "breakage stops it")
	M.set_broken_condition(FALSE)
	M.set_broken_condition(FALSE)
	hold(M, STAT_OPERABLE, FALSE, SRC_EMP, 30 SECONDS)
	TEST_ASSERT(!dq_test_operable_stat(M), "a pulse stops it")
	for(var/obj/effect/effect/sparks/spark in range(2, M))
		qdel(spark)

#endif

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// A machine as a test wants it: powered, whole, out of maintenance, switched on.
/proc/dq_machine_clear(obj/machinery/M)
	M.set_grid_power(TRUE)
	M.set_broken_condition(FALSE)
	M.set_maintenance(FALSE)
	M.set_switched_on(TRUE)

#endif

/datum/unit_test/dq_machinery_ai_status_native_choice

/datum/unit_test/dq_machinery_ai_status_native_choice/Run()
	test_driver_begin()
	run_choice_case()
	test_driver_end()

/datum/unit_test/dq_machinery_ai_status_native_choice/proc/run_choice_case()
	var/turf/T = dq_containment_floor()
	var/mob/living/silicon/robot/actor = allocate(/mob/living/silicon/robot, T)
	var/obj/machinery/ai_status_display/display = allocate(/obj/machinery/ai_status_display, T)
	dq_machine_clear(display)
	TEST_ASSERT(display.operable(), "actual display is powered and operational")
	TEST_ASSERT(actor.remote_link_up(), "real robot has its ordinary operational remote interface")
	var/list/options = get_ai_emotions(actor.ckey)
	var/selected
	for(var/option in options)
		if(option != display.emotion)
			selected = option
			break
	TEST_ASSERT(selected, "real emotion registry offers a changed selection")
	var/original = display.emotion
	var/datum/op_result/opened = test_click(actor, display, null)
	TEST_ASSERT(opened && isnull(opened.outcome), "real robot click opens the native status question")
	test_answer(actor, null, REQ_CANCELLED)
	TEST_ASSERT_EQUAL(display.emotion, original, "cancel preserves actual displayed emotion")
	opened = test_click(actor, display, null)
	TEST_ASSERT(opened && isnull(opened.outcome), "second real click opens a fresh status question")
	var/datum/op_result/answered = test_answer(actor, selected)
	TEST_ASSERT_EQUAL(answered?.outcome, ACT_COMMITTED, "real answer commits the status operation")
	TEST_ASSERT_EQUAL(display.emotion, selected, "actual display stores the chosen registered emotion")
