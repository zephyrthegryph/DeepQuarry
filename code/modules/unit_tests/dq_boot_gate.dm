/**
 * The boot-only check (doc/rewrite/boot_gate.md): `bash tools/dq_focused_test.sh --boot` runs this one test.
 * It asserts nothing itself; the boot gate (unit_test_boot_gate(), run before the first test of every run)
 * fails the run when the world logged a runtime or a warning while booting. Use it to check a change that
 * only touches boot (a map, an Initialize(), a system's init) without picking a test.
 */
/datum/unit_test/dq_boot_gate
	/// Asserts one global: nothing deferred boot work builds is read.
	boot_needs = list()

/datum/unit_test/dq_boot_gate/Run()
	// A clean boot reads boot_unclean as null; the run's verdict comes from FinishTestRun().
	TEST_ASSERT(isnull(GLOB.boot_unclean), GLOB.boot_unclean)

/// A flag only the state-guard test writes: the guard's control case (a 0/1 flag a test leaves changed is a leak).
GLOBAL_VAR_INIT(dq_state_guard_probe, 0)

/// The state guard treats the midnight rollover counter as clock state: the real-time clock crossing midnight during a
/// test bumps it, and that is no test's leak (28 October: gr/bumped-notices was bounced for dq_boot_gate at 00:00:05).
/// A real flag the test leaves changed is still reported, so the guard itself is not loosened.
/datum/unit_test/dq_state_guard_midnight_is_clock
	boot_needs = list()

/datum/unit_test/dq_state_guard_midnight_is_clock/Run()
	var/list/before = unit_test_globals_snapshot()
	var/rollovers = GLOB.midnight_rollovers
	GLOB.midnight_rollovers = rollovers + 1 // what update_midnight_rollover() does at midnight
	var/list/found = list()
	unit_test_globals_guard(before, type, found)
	GLOB.midnight_rollovers = rollovers
	for(var/line in found)
		TEST_ASSERT(!findtext(line, "midnight_rollovers"), "the guard reported the clock's rollover as a leak: [line]")
	// control: a 0/1 flag changed in between is still a leak
	before = unit_test_globals_snapshot()
	GLOB.dq_state_guard_probe = 1
	found = list()
	unit_test_globals_guard(before, type, found)
	GLOB.dq_state_guard_probe = 0
	var/flagged = FALSE
	for(var/line in found)
		if(findtext(line, "dq_state_guard_probe"))
			flagged = TRUE
	TEST_ASSERT(flagged, "the guard no longer reports a changed flag: [jointext(found, " | ")]")
