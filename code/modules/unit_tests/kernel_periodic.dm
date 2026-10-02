/// The step protocol on a live cadence: STEP_DONE / STEP_YIELD / STEP_PARK, wake and park, the member
/// driver, and periodic_runlevels (code/controllers/kernel/system.dm, om/periodic.dm).

/datum/system/test_periodic
	abstract_type = /datum/system/test_periodic
	periodic_cadence = CADENCE_FAST
	var/steps = 0
	var/yields = 0
	var/park_at = 0
	var/yield_at = 0
	var/list/deltas

/datum/system/test_periodic/periodic_step(delta)
	steps++
	LAZYADD(deltas, delta)
	if(park_at && steps >= park_at)
		return STEP_PARK
	if(yield_at && steps == yield_at)
		yields++
		return STEP_YIELD
	return STEP_DONE

/datum/system/test_periodic_members
	abstract_type = /datum/system/test_periodic_members
	member_cadence = CADENCE_FAST
	var/list/stepped
	var/refused

/datum/system/test_periodic_members/member_should_run(atom/A)
	return A != refused

/datum/system/test_periodic_members/member_step(atom/A, dt)
	LAZYINITLIST(stepped)
	stepped[A] = (stepped[A] || 0) + 1
	return STEP_DONE

/datum/unit_test/kernel_periodic

/datum/unit_test/kernel_periodic/proc/steps_at_least(datum/system/test_periodic/S, n)
	return S.steps >= n

/datum/unit_test/kernel_periodic/proc/members_stepped(datum/system/test_periodic_members/S, atom/A)
	return S.stepped?[A] >= 2

/datum/unit_test/kernel_periodic/Run()
	TEST_ASSERT(STEP_YIELD != PROCESS_KILL && STEP_PARK != PROCESS_KILL && STEP_DONE != PROCESS_KILL, "no step result equals PROCESS_KILL")
	TEST_ASSERT(STEP_YIELD != STEP_PARK && STEP_YIELD != STEP_DONE && STEP_PARK != STEP_DONE, "the step results are distinct")

	// A system on a cadence is stepped by the periodic engine with the cadence's delta.
	var/datum/system/test_periodic/S = new
	S.yield_at = 2
	S.wake_periodic()
	TEST_ASSERT(run_until(CALLBACK(src, PROC_REF(steps_at_least), S, 4)), "the engine stepped the system on its cadence")
	TEST_ASSERT_EQUAL(S.deltas[1], 2, "each step gets the cadence's delta")
	TEST_ASSERT_EQUAL(S.yields, 1, "the step that yielded ran once and was resumed")

	// STEP_PARK leaves the cadence; the system stops being stepped until it is woken.
	S.park_at = S.steps + 1
	TEST_ASSERT(run_until(CALLBACK(src, PROC_REF(steps_at_least), S, S.park_at)), "the parking step ran")
	var/parked_steps = S.steps
	wait_ticks(12)
	TEST_ASSERT_EQUAL(S.steps, parked_steps, "a parked system is not stepped")
	S.park_at = 0
	S.wake_periodic()
	TEST_ASSERT(run_until(CALLBACK(src, PROC_REF(steps_at_least), S, parked_steps + 2)), "wake_periodic() restarts a parked system")

	// The runlevel gate: a system that excludes the current runlevel does not run.
	var/current_bit = 1 << (Kernel.current_runlevel - 1)
	S.periodic_runlevels = 0
	TEST_ASSERT(S.should_run(), "no runlevel restriction: the cadence's own gate applies")
	S.periodic_runlevels = current_bit
	TEST_ASSERT(S.should_run(), "the current runlevel is accepted")
	S.periodic_runlevels = ~current_bit & (RUNLEVEL_LOBBY | RUNLEVEL_SETUP | RUNLEVEL_GAME | RUNLEVEL_POSTGAME)
	TEST_ASSERT(!S.should_run(), "another runlevel's system is not run")

	// park_periodic() takes it off the cadence at will, and should_run() says so.
	S.periodic_runlevels = 0
	S.park_periodic()
	TEST_ASSERT(!S.should_run(), "a parked system's should_run() is FALSE")
	var/held = S.steps
	wait_ticks(12)
	TEST_ASSERT_EQUAL(S.steps, held, "park_periodic() stops the cadence")

	// Members: the driver steps each member that member_should_run() accepts, on member_cadence.
	var/datum/system/test_periodic_members/M = new
	var/atom/a = allocate(/obj/effect/landmark)
	var/atom/b = allocate(/obj/effect/landmark)
	M.refused = b
	M.kernel_join(a)
	M.kernel_join(b)
	M.wake_periodic()
	TEST_ASSERT(run_until(CALLBACK(src, PROC_REF(members_stepped), M, a)), "the accepted member was stepped on the member cadence")
	TEST_ASSERT_NULL(M.stepped?[b], "a member member_should_run() refuses is not stepped")
	M.park_periodic()
	qdel(M)
	qdel(S)
