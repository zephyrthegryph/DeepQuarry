// The cheap idle path of a calm brain nobody sees (cost measurements: dq_ai_idle_cost_tests.dm).

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// A calm unseen mouse's run takes the cheap path: the idle wander is an instant behaviour (no start, tick and stop across two runs), the behaviour list is
/// not rebuilt for an unchanged brain, the footstep work of an unheard step is skipped, and the mouse still wanders.
/datum/unit_test/dq_ai_idle_cheap_path

/datum/unit_test/dq_ai_idle_cheap_path/Run()
	var/turf/start = locate(run_loc_floor_bottom_left.x + 2, run_loc_floor_bottom_left.y + 2, run_loc_floor_bottom_left.z)
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse, start)
	var/datum/ai_brain/B = M.ai_brain
	TEST_ASSERT_NOTNULL(B, "the mouse has no brain")
	var/datum/observer = allocate(/datum)
	hold(M, STAT_RELEVANCE, RELEVANCE_NEAR, observer)
	B.rebuild_behaviors()
	var/runs = 120
	var/instants_before = B.instants_run
	var/done_before = B.rebuilds_done
	var/skipped_before = B.rebuilds_skipped
	var/moves = 0
	for(var/i in 1 to runs)
		B.strategic_wait = 0
		var/turf/was = get_turf(M)
		B.tactical_tick()
		TEST_ASSERT_NULL(B.active_behavior_type, "an idle wander became the active behaviour (run [i])")
		if(get_turf(M) != was)
			moves++
		if(get_dist(get_turf(M), start) > 2)
			M.forceMove(start) // keep it inside the open arena
	TEST_ASSERT_EQUAL(B.instants_run - instants_before, runs, "every calm run was one instant behaviour")
	TEST_ASSERT_EQUAL(B.rebuilds_done - done_before, 0, "an unchanged calm brain rebuilt its behaviour list")
	TEST_ASSERT_EQUAL(B.rebuilds_skipped - skipped_before, runs, "every run skipped the rebuild")
	TEST_ASSERT(moves > 0, "the mouse never wandered in [runs] runs")
	TEST_ASSERT_NULL(M.footfall, "a step nobody can hear still did its footstep work ([moves] moves)")
	TEST_ASSERT_EQUAL(B.strategic_wait, 0, "the brain did not ask to pick again at the next run")
	for(var/obj/effect/decal/cleanable/dirt/D in range(3, start))
		qdel(D) // a wandering mouse dirties the floor

/// What the cheap path may not change: a threat stops the instant wander and the loop engages, losing it brings the wander back, and a changed behaviour
/// input (a flag the build injects from, a held item's grant) rebuilds the list.
/datum/unit_test/dq_ai_idle_cheap_path_reacts

/datum/unit_test/dq_ai_idle_cheap_path_reacts/Run()
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse, run_loc_floor_bottom_left)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, locate(run_loc_floor_bottom_left.x + 5, run_loc_floor_bottom_left.y, run_loc_floor_bottom_left.z))
	var/datum/ai_brain/B = M.ai_brain
	var/datum/observer = allocate(/datum)
	hold(M, STAT_RELEVANCE, RELEVANCE_NEAR, observer)
	B.strategic_wait = 0
	B.tactical_tick()
	var/instants = B.instants_run
	TEST_ASSERT(instants > 0, "a calm run did not run the wander")
	B.give_target(H, TRUE)
	for(var/i in 1 to 6)
		B.strategic_wait = 0
		B.tactical_tick()
	TEST_ASSERT_EQUAL(B.primary_threat, H, "the threat was dropped")
	TEST_ASSERT_EQUAL(B.instants_run, instants, "an engaged brain ran an idle instant")
	B.lose_target()
	for(var/i in 1 to 6)
		B.strategic_wait = 0
		B.tactical_tick()
	TEST_ASSERT(B.instants_run > instants, "the wander did not come back after the threat was gone")
	TEST_ASSERT(!(/datum/ai_behavior/return_home in B.effective_behaviors), "a mouse that does not return home had return_home")
	var/done = B.rebuilds_done
	B.returns_home = TRUE
	B.rebuild_behaviors()
	TEST_ASSERT_EQUAL(B.rebuilds_done, done + 1, "a flipped build flag did not rebuild")
	TEST_ASSERT(/datum/ai_behavior/return_home in B.effective_behaviors, "returns_home did not add its behaviour")
	B.returns_home = FALSE
	B.rebuild_behaviors()
	TEST_ASSERT(!(/datum/ai_behavior/return_home in B.effective_behaviors), "clearing returns_home kept its behaviour")
	var/mob/living/carbon/human/armed = allocate(/mob/living/carbon/human)
	armed.set_use_modern_ai(TRUE)
	armed.initialize_ai_brain()
	var/datum/ai_brain/AB = armed.ai_brain
	AB.rebuild_behaviors()
	AB.rebuild_behaviors()
	TEST_ASSERT(AB.rebuilds_skipped > 0, "an unchanged human brain rebuilt twice")
	var/obj/item/grenade/G = allocate(/obj/item/grenade)
	armed.put_in_hands(G)
	AB.rebuild_behaviors()
	TEST_ASSERT(/datum/ai_behavior/throw_grenade in AB.effective_behaviors, "a held item's grant was not rebuilt in")
	armed.drop_from_inventory(G)
	AB.rebuild_behaviors()
	TEST_ASSERT(!(/datum/ai_behavior/throw_grenade in AB.effective_behaviors), "a dropped item's grant stayed in the list")

#endif
