/// The step protocol a system's every() handler returns (STEP_DONE / STEP_YIELD / STEP_PARK) and the
/// periodic_runlevels gate its every() items ask (code/world/kernel/system.dm).

/datum/system/test_periodic
	abstract_type = /datum/system/test_periodic

/datum/unit_test/kernel_periodic
	boot_needs = list()

/datum/unit_test/kernel_periodic/Run()
	TEST_ASSERT(STEP_YIELD != PROCESS_KILL && STEP_PARK != PROCESS_KILL && STEP_DONE != PROCESS_KILL, "no step result equals PROCESS_KILL")
	TEST_ASSERT(STEP_YIELD != STEP_PARK && STEP_YIELD != STEP_DONE && STEP_PARK != STEP_DONE, "the step results are distinct")

	// The runlevel gate: a system that excludes the current runlevel does not run.
	var/datum/system/test_periodic/S = new
	var/current_bit = 1 << (Kernel.current_runlevel - 1)
	S.periodic_runlevels = 0
	TEST_ASSERT(S.periodic_runlevel_ok(), "no runlevel restriction: every runlevel is accepted")
	S.periodic_runlevels = current_bit
	TEST_ASSERT(S.periodic_runlevel_ok(), "the current runlevel is accepted")
	S.periodic_runlevels = ~current_bit & (RUNLEVEL_LOBBY | RUNLEVEL_SETUP | RUNLEVEL_GAME | RUNLEVEL_POSTGAME)
	TEST_ASSERT(!S.periodic_runlevel_ok(), "another runlevel's system is not run")
	qdel(S)
