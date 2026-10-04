// Behaviour-preservation tests for the users of emp_disable(): a pulse takes the holder down for its outage (the declared duration over the pulse's
// severity) and it comes back by itself. Written against the legacy capability (the EMPED bit and an expiry var) before emp_disable() became a
// timed hold on the holder's operability; the same tests pass after. State is read through the adapters below and plain vars.
//
// The users' tests run live (`live = TRUE`): the legacy outage ran on the world clock, which the kernel test clock does not move. A very high
// severity keeps each outage to a few seconds of real time.

/// The holder is down from a pulse.
/proc/p2e_emp_down(atom/A)
	return A.vars["emp_until"] > EXPIRY_NOW(A, CLOCK_WORLD)

/// The second GPS sees the first one.
/proc/p2e_gps_sees(obj/item/gps/watcher, obj/item/gps/other)
	return watcher.can_track(other)

/datum/unit_test/dq_emp_disable
	abstract_type = /datum/unit_test/dq_emp_disable
	/// TRUE: real time and the live kernel.
	var/live = FALSE

/datum/unit_test/dq_emp_disable/Run()
	if(!live)
		test_driver_begin()
	test_rng(3)
	run_gate()
	own_turf_contents(run_loc_floor_bottom_left)
	own_turf_contents(run_loc_floor_top_right)
	if(!live)
		test_driver_end()

/datum/unit_test/dq_emp_disable/proc/run_gate()
	return

/// Time passes: real time when live, the kernel clock otherwise.
/datum/unit_test/dq_emp_disable/proc/pass_time(t)
	if(live)
		sleep(t)
	else
		test_time(t)

/// A pulse switches a PDA multicaster off for 300 s / severity; it comes back on by itself.
/datum/unit_test/dq_emp_disable/multicaster_goes_down_and_comes_back
	live = TRUE

/datum/unit_test/dq_emp_disable/multicaster_goes_down_and_comes_back/run_gate()
	var/obj/machinery/pda_multicaster/M = allocate(/obj/machinery/pda_multicaster, run_loc_floor_bottom_left)
	pass_time(1 SECOND)
	var/was_on = M.on
	M.emp_act(60)
	pass_time(1 SECOND)
	TEST_ASSERT(p2e_emp_down(M), "the pulse took it down (5 s)")
	TEST_ASSERT(!M.on, "and switched it off")
	M.emp_act(20)
	pass_time(6 SECONDS)
	TEST_ASSERT(!p2e_emp_down(M), "a second, longer pulse while down does not lengthen the outage")
	TEST_ASSERT_EQUAL(M.on, was_on, "it is back as it was")

/// A pulse halts a research server for 60 s / severity.
/datum/unit_test/dq_emp_disable/research_server_halts_for_a_while
	live = TRUE

/datum/unit_test/dq_emp_disable/research_server_halts_for_a_while/run_gate()
	var/obj/machinery/rnd/server/S = allocate(/obj/machinery/rnd/server, run_loc_floor_bottom_left)
	pass_time(1 SECOND)
	var/was_working = S.working
	S.emp_act(10)
	pass_time(1 SECOND)
	TEST_ASSERT(!S.working, "the pulse halted it (6 s)")
	pass_time(3 SECONDS)
	TEST_ASSERT(!S.working, "still halted a few seconds on")
	pass_time(4 SECONDS)
	TEST_ASSERT_EQUAL(S.working, was_working, "working again after its outage")

/// A pulsed GPS drops off the other GPS units for 5 minutes / severity; a shielded one is not affected.
/datum/unit_test/dq_emp_disable/gps_drops_off_the_map_for_a_while
	live = TRUE

/datum/unit_test/dq_emp_disable/gps_drops_off_the_map_for_a_while/run_gate()
	var/obj/item/gps/G = allocate(/obj/item/gps, run_loc_floor_bottom_left)
	var/obj/item/gps/watcher = allocate(/obj/item/gps, run_loc_floor_bottom_left)
	if(!G.tracking)
		G.toggle_tracking()
	TEST_ASSERT(p2e_gps_sees(watcher, G), "a tracking GPS is seen")
	G.emp_act(50)
	pass_time(1 SECOND)
	TEST_ASSERT(!p2e_gps_sees(watcher, G), "pulsed, it drops off (6 s)")
	pass_time(3 SECONDS)
	TEST_ASSERT(!p2e_gps_sees(watcher, G), "still off a few seconds on")
	pass_time(4 SECONDS)
	TEST_ASSERT(p2e_gps_sees(watcher, G), "back after its outage")
	G.emp_protection_flags = EMP_PROTECT_SELF
	G.emp_act(1)
	pass_time(1 SECOND)
	TEST_ASSERT(p2e_gps_sees(watcher, G), "a shielded GPS shrugs a pulse off")
