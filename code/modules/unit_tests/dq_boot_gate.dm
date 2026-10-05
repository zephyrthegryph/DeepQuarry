/**
 * The boot-only check (doc/rewrite/boot_gate.md): `bash tools/dq_focused_test.sh --boot` runs this one test.
 * It asserts nothing itself; the boot gate (unit_test_boot_gate(), run before the first test of every run)
 * fails the run when the world logged a runtime or a warning while booting. Use it to check a change that
 * only touches boot (a map, an Initialize(), a system's init) without picking a test.
 */
/datum/unit_test/dq_boot_gate

/datum/unit_test/dq_boot_gate/Run()
	// A clean boot reads boot_unclean as null; the run's verdict comes from FinishTestRun().
	TEST_ASSERT(isnull(GLOB.boot_unclean), GLOB.boot_unclean)
