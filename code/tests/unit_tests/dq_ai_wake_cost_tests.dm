// A calm mouse's strategic run when it wakes: what each stage costs while nothing is near, when a crowd stands in its view and when a player arrives,
// and that the counters of one run stay bounded.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// Times `runs` forced strategic passes of `B`: the dearest one's total and the stage times of it, plus the pack's perception counters over the whole batch.
/datum/unit_test/proc/wake_cost_batch(datum/ai_brain/B, runs, label)
	var/worst = 0
	var/worst_stages = ""
	var/views0 = GLOB.ai_pack_view_builds
	var/los0 = GLOB.ai_pack_los_checks
	var/perc0 = GLOB.ai_pack_perceptions
	for(var/i in 1 to runs)
		B.strategic_wait = 0
		if(B.pack)
			B.pack.last_perceived_at = 0 // the backstop is due: the run pays a pass
		var/t0 = TICK_USAGE_REAL
		B.tactical_tick()
		var/took = TICK_DELTA_TO_MS(TICK_USAGE_REAL - t0)
		if(took > worst)
			worst = took
			worst_stages = ""
			for(var/s in B.strategic_stage_ms)
				worst_stages += " [s]=[round(B.strategic_stage_ms[s], 0.01)]"
	TEST_NOTICE(src, "WAKE_COST [label]: worst run [round(worst, 0.01)] ms ([worst_stages]); over [runs] runs: [GLOB.ai_pack_perceptions - perc0] passes, [GLOB.ai_pack_los_checks - los0] los checks, [GLOB.ai_pack_view_builds - views0] view builds")
	return list("ms" = worst, "passes" = GLOB.ai_pack_perceptions - perc0, "views" = GLOB.ai_pack_view_builds - views0, "los" = GLOB.ai_pack_los_checks - los0)

/datum/unit_test/dq_ai_wake_cost

/datum/unit_test/dq_ai_wake_cost/Run()
	set_global(nameof(GLOB.staleness_on), FALSE)
	var/turf/start = locate(run_loc_floor_bottom_left.x + 4, run_loc_floor_bottom_left.y + 4, run_loc_floor_bottom_left.z)
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse, start)
	var/datum/ai_brain/B = M.ai_brain
	TEST_ASSERT_NOTNULL(B, "the mouse has no brain")
	var/datum/observer = allocate(/datum)
	hold(M, STAT_RELEVANCE, RELEVANCE_NEAR, observer)
	wake_cost_batch(B, 20, "warm-up")
	wake_cost_batch(B, 40, "alone")
	var/list/crowd = list()
	for(var/i in 1 to 12)
		crowd += allocate(/mob/living/simple_mob/animal/passive/mouse, locate(start.x + (i % 4) - 1, start.y + round(i / 4) - 1, start.z))
	wake_cost_batch(B, 40, "twelve mice near")
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, locate(start.x + 3, start.y, start.z))
	var/list/near = wake_cost_batch(B, 40, "human arrived 3 tiles away")
	// One strategic run does at most one pass, and builds at most one view per member (a pack of one: one).
	TEST_ASSERT(near["passes"] <= 40, "a strategic run made more than one perception pass ([near["passes"]] in 40 runs)")
	TEST_ASSERT(near["views"] <= 40, "a strategic run built more than one view ([near["views"]] in 40 runs)")
	// A calm run on a tick with no budget left is put off, and runs once there is room.
	var/mob/living/carbon/human/gone = H
	qdel(gone)
	B.strategic_wait = 0
	var/before = B.budget_deferrals
	var/was_limit = Kernel.current_ticklimit
	Kernel.current_ticklimit = 0
	B.strategic_tick()
	Kernel.current_ticklimit = 1e9 // room: the test's own tick is long
	TEST_ASSERT_EQUAL(B.budget_deferrals, before + 1, "a calm strategic run on an over-budget tick was not deferred")
	var/ran = B.instants_run + B.rebuilds_skipped + B.rebuilds_done
	B.strategic_tick()
	Kernel.current_ticklimit = was_limit
	TEST_ASSERT_EQUAL(B.budget_deferrals, before + 1, "a calm strategic run with budget left was deferred")
	TEST_ASSERT(B.instants_run + B.rebuilds_skipped + B.rebuilds_done > ran, "the deferred strategic run did not run once there was room")
	for(var/mob/living/simple_mob/S as anything in crowd)
		qdel(S)

#endif
