// Idle-server redraw cost: the audit sweep is paced by world time, the applied-look counters tell first draws from wasted ones, and an idle world
// redraws no turf (doc: perf/roundstart-churn).

/// The audit takes a step at most once per interval and counts the steps it skipped.
/datum/unit_test/dq_refresh_sweep_paced

/datum/unit_test/dq_refresh_sweep_paced/Run()
	set_global(nameof(GLOB.refresh_sweep_next), -1)
	var/ran = GLOB.refresh_sweep_ran
	var/skipped = GLOB.refresh_sweep_skipped
	TEST_ASSERT(refresh_sweep_due(), "the first step is due")
	TEST_ASSERT(!refresh_sweep_due(), "a second step in the same tick is not")
	TEST_ASSERT(!refresh_sweep_due(), "nor a third")
	TEST_ASSERT_EQUAL(GLOB.refresh_sweep_ran - ran, 1, "one step ran")
	TEST_ASSERT_EQUAL(GLOB.refresh_sweep_skipped - skipped, 2, "two were skipped")
	set_global(nameof(GLOB.refresh_sweep_next), world.time - 1)
	TEST_ASSERT(refresh_sweep_due(), "once the interval has passed the next step is due")

/// Drawing an atom again to the same key counts as "same", and an idle world redraws no turf.
/datum/unit_test/dq_idle_turfs_not_redrawn

/datum/unit_test/dq_idle_turfs_not_redrawn/Run()
	test_driver_begin()
	var/turf/simulated/floor/F = test_floor()
	refresh_look(F)
	var/same = GLOB.refresh_look_stats["same"] || 0
	refresh_look(F)
	TEST_ASSERT_EQUAL((GLOB.refresh_look_stats["same"] || 0) - same, 1, "a second draw to the same key counts as same: [refresh_look_stats_text()]")
	// The map's first draws are a backlog the presentation lane works off in the first seconds (they are not redraws): let it finish.
	var/list/before = turf_look_counts()
	for(var/settle in 1 to 24)
		test_time(5 SECONDS)
		var/list/now = turf_look_counts()
		var/moved = FALSE
		for(var/kind in now)
			if(now[kind] != (before[kind] || 0))
				moved = TRUE
		before = now
		if(!moved)
			break
	TEST_ASSERT(!moved_after_settle(before), "the first-draw backlog never settled: [refresh_look_stats_text(12)]")
	test_time(10 SECONDS)
	var/list/after = turf_look_counts()
	test_driver_end()
	for(var/kind in after)
		TEST_ASSERT_EQUAL(after[kind] - (before[kind] || 0), 0, "an idle world redrew turfs ([kind]): [refresh_look_stats_text(12)]")

/datum/unit_test/dq_idle_turfs_not_redrawn/proc/moved_after_settle(list/before)
	var/list/now = turf_look_counts()
	for(var/kind in now)
		if(now[kind] != (before[kind] || 0))
			return TRUE
	return FALSE

/// Applied turf looks so far, by kind.
/datum/unit_test/dq_idle_turfs_not_redrawn/proc/turf_look_counts()
	. = list()
	for(var/key in GLOB.refresh_look_stats)
		var/space = findtext(key, " ")
		if(!space)
			continue
		var/kind = copytext(key, 1, space)
		if(ispath(text2path(copytext(key, space + 1)), /turf))
			.[kind] = (.[kind] || 0) + GLOB.refresh_look_stats[key]
