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

/// The midnight rollover is the wall clock's own state (/datum/wall_clock), not a scalar global: a midnight crossing during a test
/// leaves nothing for the state guard to report (28 October: gr/bumped-notices was bounced for dq_boot_gate at 00:00:05), while a
/// real flag the test leaves changed is still a leak. The guard has no name exemption for it.
/datum/unit_test/dq_state_guard_midnight_is_clock
	boot_needs = list()

/datum/unit_test/dq_state_guard_midnight_is_clock/Run()
	TEST_ASSERT(!("midnight_rollovers" in unit_test_globals_ignored()), "the guard exempts the rollover by name")
	var/datum/wall_clock/clock = wall_clock()
	TEST_ASSERT(istype(clock), "no wall clock")
	// a midnight crossing, driven through the real update path: the last read is after now, so the next check sees the day wrap
	var/list/before = unit_test_globals_snapshot()
	var/saved_last = clock.last_timeofday
	var/saved_safety = clock.safety_date
	var/saved_rollovers = clock.rollovers
	clock.last_timeofday = world.timeofday + 1
	clock.safety_date = world.realtime - (13 HOURS)
	update_midnight_rollover()
	TEST_ASSERT_EQUAL(clock.rollovers, saved_rollovers + 1, "the clock did not count the midnight crossing")
	var/list/found = list()
	unit_test_globals_guard(before, type, found)
	clock.rollovers = saved_rollovers
	clock.last_timeofday = saved_last
	clock.safety_date = saved_safety
	for(var/line in found)
		TEST_ASSERT(!findtext(line, "rollover"), "the guard reported the clock's rollover as a leak: [line]")
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
