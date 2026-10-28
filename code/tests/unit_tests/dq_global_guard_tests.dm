// The state guard (unit_test_globals_guard): a scalar global that flips is reported, a declared diagnostic counter (GLOBAL_COUNTER) is not.

/// A plain global number that flips 0 -> 1 is reported as a leak, whatever its name.
GLOBAL_VAR_INIT(dq_guard_probe_flag, 0)

/datum/unit_test/dq_state_guard_reports_a_global_flag_flip

/datum/unit_test/dq_state_guard_reports_a_global_flag_flip/Run()
	var/list/before = unit_test_globals_snapshot()
	GLOB.dq_guard_probe_flag = 1
	var/list/found = list()
	unit_test_globals_guard(before, "/datum/unit_test/dq_guard_probe", found)
	GLOB.dq_guard_probe_flag = 0
	TEST_ASSERT_EQUAL(length(found), 1, "an undeclared global that flipped 0 to 1 is reported once")
	TEST_ASSERT(findtext(found[1], "dq_guard_probe_flag"), "the report names the global")

/// A declared counter moves without a report: it is a count of work done, not state a test left behind.
/datum/unit_test/dq_state_guard_ignores_declared_counters

/datum/unit_test/dq_state_guard_ignores_declared_counters/Run()
	var/list/before = unit_test_globals_snapshot()
	GLOB.act_taken.n++
	GLOB.every_activation_runs.n++
	var/list/found = list()
	unit_test_globals_guard(before, "/datum/unit_test/dq_guard_probe", found)
	GLOB.act_taken.n--
	GLOB.every_activation_runs.n--
	TEST_ASSERT_EQUAL(length(found), 0, "a declared counter that moved is not a leak")
