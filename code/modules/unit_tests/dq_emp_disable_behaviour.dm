// Behaviour-preservation tests for the users of emp_disable(): a pulse takes the holder down for its outage (the declared duration over the pulse's
// severity) and it comes back by itself. Written against the legacy capability (the EMPED bit and an expiry var) before emp_disable() became a
// timed hold on the holder's operability; the same tests pass after. State is read through the adapters below and plain vars.

/// The holder is down from a pulse.
/proc/p2e_emp_down(atom/A)
	return A.vars["emp_until"] > EXPIRY_NOW(A, CLOCK_WORLD)

/// The second GPS sees the first one.
/proc/p2e_gps_sees(obj/item/gps/watcher, obj/item/gps/other)
	return watcher.can_track(other)

/datum/unit_test/dq_emp_disable
	abstract_type = /datum/unit_test/dq_emp_disable

/datum/unit_test/dq_emp_disable/Run()
	test_driver_begin()
	test_rng(3)
	run_gate()
	own_turf_contents(run_loc_floor_bottom_left)
	own_turf_contents(run_loc_floor_top_right)
	test_driver_end()

/datum/unit_test/dq_emp_disable/proc/run_gate()
	return

/// A pulse switches a PDA multicaster off for 300 s / severity; it comes back on by itself.
/datum/unit_test/dq_emp_disable/multicaster_goes_down_and_comes_back

/datum/unit_test/dq_emp_disable/multicaster_goes_down_and_comes_back/run_gate()
	var/obj/machinery/pda_multicaster/M = allocate(/obj/machinery/pda_multicaster, run_loc_floor_bottom_left)
	test_time(2 SECONDS)
	var/was_on = M.on
	M.emp_act(2)
	test_time(2 SECONDS)
	TEST_ASSERT(p2e_emp_down(M), "the pulse took it down")
	TEST_ASSERT(!M.on, "and switched it off")
	test_time(1 MINUTE)
	TEST_ASSERT(p2e_emp_down(M), "still down a minute on")
	M.emp_act(1)
	test_time(2 MINUTES)
	TEST_ASSERT(!p2e_emp_down(M), "a second pulse while down does not lengthen the outage (150 s)")
	TEST_ASSERT_EQUAL(M.on, was_on, "it is back as it was")

/// A pulse halts a research server for 60 s / severity.
/datum/unit_test/dq_emp_disable/research_server_halts_for_a_while

/datum/unit_test/dq_emp_disable/research_server_halts_for_a_while/run_gate()
	var/obj/machinery/rnd/server/S = allocate(/obj/machinery/rnd/server, run_loc_floor_bottom_left)
	test_time(2 SECONDS)
	var/was_working = S.working
	S.emp_act(1)
	test_time(2 SECONDS)
	TEST_ASSERT(!S.working, "the pulse halted it")
	test_time(30 SECONDS)
	TEST_ASSERT(!S.working, "still halted half a minute on")
	test_time(40 SECONDS)
	TEST_ASSERT_EQUAL(S.working, was_working, "working again after its minute")

/// A pulsed GPS drops off the other GPS units for 5 minutes / severity; a shielded one is not affected.
/datum/unit_test/dq_emp_disable/gps_drops_off_the_map_for_a_while

/datum/unit_test/dq_emp_disable/gps_drops_off_the_map_for_a_while/run_gate()
	var/obj/item/gps/G = allocate(/obj/item/gps, run_loc_floor_bottom_left)
	var/obj/item/gps/watcher = allocate(/obj/item/gps, run_loc_floor_bottom_left)
	if(!G.tracking)
		G.toggle_tracking()
	TEST_ASSERT(p2e_gps_sees(watcher, G), "a tracking GPS is seen")
	G.emp_act(2)
	test_time(2 SECONDS)
	TEST_ASSERT(!p2e_gps_sees(watcher, G), "pulsed, it drops off")
	test_time(2 MINUTES)
	TEST_ASSERT(!p2e_gps_sees(watcher, G), "still off two minutes on")
	test_time(1 MINUTE)
	TEST_ASSERT(p2e_gps_sees(watcher, G), "back after its two and a half minutes")
	G.emp_protection_flags = EMP_PROTECT_SELF
	G.emp_act(1)
	test_time(2 SECONDS)
	TEST_ASSERT(p2e_gps_sees(watcher, G), "a shielded GPS shrugs a pulse off")
