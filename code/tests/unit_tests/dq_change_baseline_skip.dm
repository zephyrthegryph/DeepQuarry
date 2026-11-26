/// A floor's on_change hooks are all ANY on plain vars: it takes no baseline at init (no rx_state for them), and a write through the setter
/// still runs the hook at the next drain, which then records the value it saw.
/datum/unit_test/dq_change_baseline_skip/Run()
	var/turf/simulated/floor/F = run_loc_floor_bottom_left
	TEST_ASSERT(istype(F), "the test floor is a floor")
	TEST_ASSERT(GLOB.change_baselines_skipped > 0, "the map's floors took no baseline for their ANY hooks on plain vars")
	F.rx?.change_last?.Cut()
	F.set_broken("broken0")
	hooks_drain_changes()
	TEST_ASSERT(length(F.rx?.change_last), "the write ran the hook at the drain, which recorded the value it saw")
	F.set_broken(null)
	hooks_drain_changes()
