// AI action cadence (code/modules/combat_ai/brain/scheduling.dm, doc/rewrite/ai_packs.md B2): each behaviour ticks at its own interval,
// IDLE and BACKGROUND stretch x3 below RELEVANCE_VISIBLE, and a brain re-selects on events and at least once a second while engaged.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// A behaviour's interval defaults to the action tick, a tactic may set its own, and only IDLE and BACKGROUND stretch.
/datum/unit_test/dq_ai_cadence_interval_by_relevance

/datum/unit_test/dq_ai_cadence_interval_by_relevance/Run()
	var/mob/living/simple_mob/S = allocate(/mob/living/simple_mob/combat_ai_tactics_subject, run_loc_floor_bottom_left)
	var/datum/ai_brain/B = S.ai_brain
	var/datum/ai_behavior/melee = dq_get_behavior(/datum/ai_behavior/melee_attack)
	var/datum/ai_behavior/wander = dq_get_behavior(/datum/ai_behavior/idle_wander)
	var/datum/ai_behavior/walk = dq_get_behavior(/datum/ai_behavior/follow_leader)
	var/datum/observer = allocate(/datum)
	hold(S, STAT_RELEVANCE, RELEVANCE_VISIBLE, observer)
	TEST_ASSERT_EQUAL(melee.interval_for(B), DQ_ACTION_TICK, "a combat tactic did not default to the action tick")
	TEST_ASSERT_EQUAL(wander.interval_for(B), DQ_ACTION_TICK, "an idle tactic stretched while visible")
	release(S, STAT_RELEVANCE, observer)
	hold(S, STAT_RELEVANCE, RELEVANCE_NEAR, observer)
	TEST_ASSERT(stat_value(S, STAT_RELEVANCE) < RELEVANCE_VISIBLE, "the test mob is visible to a player; the stretch was not exercised")
	TEST_ASSERT_EQUAL(melee.interval_for(B), DQ_ACTION_TICK, "a NORMAL tactic stretched below RELEVANCE_VISIBLE")
	TEST_ASSERT_EQUAL(wander.interval_for(B), DQ_ACTION_TICK * DQ_IDLE_STRETCH, "an IDLE tactic did not stretch x3 below RELEVANCE_VISIBLE")
	TEST_ASSERT_EQUAL(walk.interval_for(B), DQ_ACTION_TICK * DQ_IDLE_STRETCH, "follow_leader did not stretch x3 below RELEVANCE_VISIBLE")
	release(S, STAT_RELEVANCE, observer)

/// The action loop's interval is the active behaviour's.
/datum/unit_test/dq_ai_cadence_loop_follows_active

/datum/unit_test/dq_ai_cadence_loop_follows_active/Run()
	var/mob/living/simple_mob/S = allocate(/mob/living/simple_mob/combat_ai_tactics_subject, run_loc_floor_bottom_left)
	var/datum/ai_brain/B = S.ai_brain
	var/datum/observer = allocate(/datum)
	hold(S, STAT_RELEVANCE, RELEVANCE_VISIBLE, observer)
	TEST_ASSERT_EQUAL(S.ai_action_interval(null), DQ_ACTION_TICK, "an idle brain's action interval is not the action tick")
	B.active_behavior_type = /datum/ai_behavior/idle_wander
	TEST_ASSERT_EQUAL(S.ai_action_interval(null), DQ_ACTION_TICK, "the action interval does not follow the active behaviour (visible)")
	release(S, STAT_RELEVANCE, observer)
	hold(S, STAT_RELEVANCE, RELEVANCE_NEAR, observer)
	TEST_ASSERT_EQUAL(S.ai_action_interval(null), DQ_ACTION_TICK * DQ_IDLE_STRETCH, "a stretched idle behaviour did not stretch the action loop")
	TEST_ASSERT_EQUAL(B.armed_interval, DQ_ACTION_TICK * DQ_IDLE_STRETCH, "the armed interval was not recorded")
	B.active_behavior_type = null
	release(S, STAT_RELEVANCE, observer)

/// An engaged brain with a running behaviour re-selects at least every DQ_ENGAGED_RECHECK without an event, and not before.
/datum/unit_test/dq_ai_cadence_engaged_recheck

/datum/unit_test/dq_ai_cadence_engaged_recheck/Run()
	var/mob/living/simple_mob/S = allocate(/mob/living/simple_mob/combat_ai_tactics_subject, run_loc_floor_bottom_left)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, locate(run_loc_floor_bottom_left.x + 8, run_loc_floor_bottom_left.y, run_loc_floor_bottom_left.z))
	var/datum/ai_brain/B = S.ai_brain
	B.give_target(H, TRUE)
	B.pick_and_run()
	TEST_ASSERT_NOTNULL(B.active_behavior_type, "the engaged brain picked nothing")
	var/stamp = B.last_pick_at
	TEST_ASSERT(stamp, "a pick did not stamp last_pick_at")
	B.selection_dirty = FALSE
	B.tactical_tick()
	TEST_ASSERT_EQUAL(B.last_pick_at, stamp, "the brain re-selected inside the minimum interval with no event")
	B.last_pick_at = stamp - DQ_ENGAGED_RECHECK - 1
	B.selection_dirty = FALSE
	B.tactical_tick()
	TEST_ASSERT(B.last_pick_at != stamp - DQ_ENGAGED_RECHECK - 1, "an engaged brain did not re-select after the minimum interval (busy=[B.is_busy()] active=[B.active_behavior_type] threat=[B.primary_threat] now=[world.time] pick=[B.last_pick_at] stamp=[stamp] dirty=[B.selection_dirty])")

#endif
