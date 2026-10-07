// AI brain loops (code/modules/combat_ai/brain/scheduling.dm): the strategic and tactical loops are capabilities the brain
// grants its mob; they skip their runs below RELEVANCE_NEAR and wake on events.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// TRUE when loop capability `C` is granted on `E` and its runs are not skipped (relevance, runlevel).
/proc/dq_ai_test_on_ring(mob/living/E, C)
	return granted(E, C) && dq_ai_loops_may_run(E)

/// A new brain runs the strategic loop only; a combat target adds the tactical loop, losing it
/// removes it again.
/datum/unit_test/dq_ai_om_loops_follow_target

/datum/unit_test/dq_ai_om_loops_follow_target/Run()
	var/mob/living/simple_mob/combat_ai_test_subject/hunter = allocate(/mob/living/simple_mob/combat_ai_test_subject)
	var/mob/living/carbon/human/target = allocate(/mob/living/carbon/human)
	var/datum/ai_brain/B = hunter.ai_brain
	TEST_ASSERT_NOTNULL(B, "test subject has no brain")
	TEST_ASSERT(granted(hunter, /datum/capability/ai_loop/tactical), "a new brain did not attach its loop")
	TEST_ASSERT_EQUAL(B.action_interval(), DQ_CALM_TICK, "an idle brain's loop is not on the calm cadence")
	B.give_target(target, TRUE)
	TEST_ASSERT(granted(hunter, /datum/capability/ai_loop/tactical), "a combat target took the loop away")
	TEST_ASSERT(B.action_interval() <= DQ_ACTION_TICK, "a brain with a target is not on the action cadence")
	B.lose_target()
	TEST_ASSERT_EQUAL(B.action_interval(), DQ_CALM_TICK, "the loop stayed fast after the target was lost")
	qdel(B)
	TEST_ASSERT(!granted(hunter, /datum/capability/ai_loop/tactical), "a deleted brain left its loop on the mob")

/// A low-priority AI mob on a z-level with no living player is at RELEVANCE_NONE and its loops
/// skip their runs (the old SSai process_z skip); an observer at NEAR puts them back.
/datum/unit_test/dq_ai_om_parks_without_players

/datum/unit_test/dq_ai_om_parks_without_players/Run()
	var/mob/living/simple_mob/combat_ai_test_subject/hunter = allocate(/mob/living/simple_mob/combat_ai_test_subject, run_loc_floor_bottom_left)
	var/mob/living/carbon/human/target = allocate(/mob/living/carbon/human, run_loc_floor_top_right)
	hunter.low_priority = TRUE
	hunter.life_update_relevance()
	hunter.ai_brain.give_target(target, TRUE)
	TEST_ASSERT(granted(hunter, /datum/capability/ai_loop/tactical), "the loop is not attached")
	if(stat_value(hunter, STAT_RELEVANCE) != RELEVANCE_NONE)
		TEST_NOTICE(src, "the test z-level holds a living player; parking was not exercised")
		return
	TEST_ASSERT(!dq_ai_test_on_ring(hunter, /datum/capability/ai_loop/tactical), "the loop ran with no player on the z-level")
	var/datum/observer = allocate(/datum)
	hold(hunter, STAT_RELEVANCE, RELEVANCE_NEAR, observer)
	TEST_ASSERT(dq_ai_test_on_ring(hunter, /datum/capability/ai_loop/tactical), "the loop did not resume when relevant")
	release(hunter, STAT_RELEVANCE, observer)
	TEST_ASSERT(!dq_ai_test_on_ring(hunter, /datum/capability/ai_loop/tactical), "the loop did not park again")

/// Hibernating calm brains leave the strategic loop; being attacked wakes them and gives them
/// the attacker as their target.
/datum/unit_test/dq_ai_om_attack_wakes_and_acquires

/datum/unit_test/dq_ai_om_attack_wakes_and_acquires/Run()
	var/mob/living/simple_mob/combat_ai_test_subject/victim = allocate(/mob/living/simple_mob/combat_ai_test_subject, run_loc_floor_bottom_left)
	var/mob/living/carbon/human/attacker = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/datum/ai_brain/B = victim.ai_brain
	rel_clear(B, nameof(B.primary_threat))
	B.active_behavior_type = null
	TEST_ASSERT(B.park_calm(), "calm brain refused to park")
	TEST_ASSERT(!granted(victim, /datum/capability/ai_loop/tactical), "a parked brain kept its loop")
	B.notify_damage(10, INJURY_BLUNT, attacker)
	TEST_ASSERT_EQUAL(B.primary_threat, attacker, "an attack did not give the brain its attacker as target")
	TEST_ASSERT(granted(victim, /datum/capability/ai_loop/tactical), "an attack did not wake the loop")
	TEST_ASSERT_NULL(B.sleep_violation(), "a woken brain reported a sleep violation")

/// Driven through its loops, a brain with a target walks to it and attacks it.
/datum/unit_test/dq_ai_om_moves_and_attacks

/datum/unit_test/dq_ai_om_moves_and_attacks/Run()
	var/turf/start = run_loc_floor_bottom_left
	var/turf/goal = locate(start.x + 3, start.y, start.z)
	TEST_ASSERT(goal && !goal.density, "no open floor three tiles from the test origin")
	var/mob/living/simple_mob/combat_ai_test_subject/hunter = allocate(/mob/living/simple_mob/combat_ai_test_subject, start)
	var/mob/living/carbon/human/target = allocate(/mob/living/carbon/human, goal)
	var/datum/ai_brain/B = hunter.ai_brain
	B.give_target(target, TRUE)
	var/start_dist = get_dist(hunter, target)
	var/closest = start_dist
	var/initial_injuries = target.injury_load(INJURY_CATEGORY_PHYSICAL)
	// Breaks as soon as it attacks; the budget only matters on a loaded machine,
	// where 30 rounds sometimes ran out just before the swing (also seen on
	// unsharded merge runs), so it's 60.
	for(var/i in 1 to 60)
		hunter.next_click = 0
		B.strategic_tick()
		B.tactical_tick()
		closest = min(closest, get_dist(hunter, target))
		if(target.injury_load(INJURY_CATEGORY_PHYSICAL) > initial_injuries)
			break
		// Selection is event-driven: arriving next to the target (or the cooldown reset above) asks for a
		// re-pick, and that request can lag behind the manual ticks on a loaded world, leaving the brain on its
		// finished move behaviour. Ask for it each round the hunter is adjacent instead of assuming it landed.
		if(hunter.Adjacent(target))
			B.invalidate_selection()
		om_test_ticks(3)
	TEST_ASSERT(closest < start_dist, "the brain did not move toward its target (distance stayed [start_dist])")
	TEST_ASSERT(target.injury_load(INJURY_CATEGORY_PHYSICAL) > initial_injuries, "the brain reached its target but dealt no physical injury (diag: dist=[get_dist(hunter, target)] closest=[closest] adjacent=[hunter.Adjacent(target)] threat=[B.primary_threat] target_stat=[target.stat] cooldown_ok=[hunter.checkClickCooldown()] last_attack=[B.last_attack_at] hunter=[AREACOORD(hunter)] target=[AREACOORD(target)] behaviour=[B.active_behavior_type])")

/// Mauling a downed target is an attack too: it stamps last_attack_at like a plain strike.
/// (A slam can knock the target out, and then maul outscores melee_attack.)
/datum/unit_test/dq_ai_om_maul_counts_as_attack

/datum/unit_test/dq_ai_om_maul_counts_as_attack/Run()
	var/turf/start = run_loc_floor_bottom_left
	var/turf/next = locate(start.x + 1, start.y, start.z)
	TEST_ASSERT(next && !next.density, "no open floor next to the test origin")
	var/mob/living/simple_mob/combat_ai_test_subject/hunter = allocate(/mob/living/simple_mob/combat_ai_test_subject, start)
	var/mob/living/carbon/human/target = allocate(/mob/living/carbon/human, next)
	target.status_at_least(STAT_PARALYZED, 5)
	target.set_stat(UNCONSCIOUS)
	TEST_ASSERT_EQUAL(target.stat, UNCONSCIOUS, "the target should be unconscious")
	var/datum/ai_brain/B = hunter.ai_brain
	B.give_target(target, TRUE)
	hunter.next_click = 0
	B.strategic_tick()
	B.tactical_tick()
	TEST_ASSERT(!hunter.checkClickCooldown(), "the brain did not attack its downed target")
	TEST_ASSERT(B.last_attack_at, "mauling a downed target did not record an attack")

#endif
