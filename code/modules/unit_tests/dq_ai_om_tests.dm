// AI brains on the object model (code/modules/combat_ai/brain/scheduling.dm): the strategic and
// tactical loops are OM behaviours on the mob, park by relevance and wake on events.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// TRUE when `B` is on a cadence ring for `E` (attached, started, not parked by relevance/clock).
/proc/dq_ai_test_on_ring(datum/E, B)
	var/datum/om/rec/rec = E?.om_rec
	if(!rec)
		return FALSE
	var/i = rec.att.Find(om_registry().behaviour(B))
	return i && !isnull(rec.att_ring[i])

/// A new brain runs the strategic loop only; a combat target adds the tactical loop, losing it
/// removes it again.
/datum/unit_test/dq_ai_om_loops_follow_target

/datum/unit_test/dq_ai_om_loops_follow_target/Run()
	var/mob/living/simple_mob/combat_ai_test_subject/hunter = allocate(/mob/living/simple_mob/combat_ai_test_subject)
	var/mob/living/carbon/human/target = allocate(/mob/living/carbon/human)
	var/datum/ai_brain/B = hunter.ai_brain
	TEST_ASSERT_NOTNULL(B, "test subject has no brain")
	TEST_ASSERT(om_attached(hunter, /datum/om/behaviour/ai_brain/strategic), "a new brain did not attach its strategic loop")
	TEST_ASSERT(!om_attached(hunter, /datum/om/behaviour/ai_brain/tactical), "an idle brain attached its tactical loop")
	B.give_target(target, TRUE)
	TEST_ASSERT(om_attached(hunter, /datum/om/behaviour/ai_brain/tactical), "a combat target did not attach the tactical loop")
	B.lose_target()
	TEST_ASSERT(!om_attached(hunter, /datum/om/behaviour/ai_brain/tactical), "the tactical loop stayed after the target was lost")
	qdel(B)
	TEST_ASSERT(!om_attached(hunter, /datum/om/behaviour/ai_brain/strategic), "a deleted brain left its strategic loop on the mob")

/// A low-priority AI mob on a z-level with no living player is at RELEVANCE_NONE and its loops
/// park (the old SSai process_z skip); an observer at NEAR puts them back on the ring.
/datum/unit_test/dq_ai_om_parks_without_players

/datum/unit_test/dq_ai_om_parks_without_players/Run()
	var/mob/living/simple_mob/combat_ai_test_subject/hunter = allocate(/mob/living/simple_mob/combat_ai_test_subject, run_loc_floor_bottom_left)
	var/mob/living/carbon/human/target = allocate(/mob/living/carbon/human, run_loc_floor_top_right)
	hunter.low_priority = TRUE
	hunter.life_update_relevance()
	hunter.ai_brain.give_target(target, TRUE)
	TEST_ASSERT(om_attached(hunter, /datum/om/behaviour/ai_brain/strategic), "strategic loop not attached")
	TEST_ASSERT(om_attached(hunter, /datum/om/behaviour/ai_brain/tactical), "tactical loop not attached")
	if(om_relevance(hunter) != RELEVANCE_NONE)
		TEST_NOTICE(src, "the test z-level holds a living player; parking was not exercised")
		return
	TEST_ASSERT(!dq_ai_test_on_ring(hunter, /datum/om/behaviour/ai_brain/strategic), "strategic loop ran with no player on the z-level")
	TEST_ASSERT(!dq_ai_test_on_ring(hunter, /datum/om/behaviour/ai_brain/tactical), "tactical loop ran with no player on the z-level")
	var/datum/observer = allocate(/datum)
	om_observe(hunter, observer, RELEVANCE_NEAR)
	TEST_ASSERT(dq_ai_test_on_ring(hunter, /datum/om/behaviour/ai_brain/strategic), "strategic loop did not resume when relevant")
	TEST_ASSERT(dq_ai_test_on_ring(hunter, /datum/om/behaviour/ai_brain/tactical), "tactical loop did not resume when relevant")
	om_unobserve(hunter, observer)
	TEST_ASSERT(!dq_ai_test_on_ring(hunter, /datum/om/behaviour/ai_brain/strategic), "strategic loop did not park again")

/// Hibernating calm brains leave the strategic ring; being attacked wakes them and gives them
/// the attacker as their target.
/datum/unit_test/dq_ai_om_attack_wakes_and_acquires

/datum/unit_test/dq_ai_om_attack_wakes_and_acquires/Run()
	var/mob/living/simple_mob/combat_ai_test_subject/victim = allocate(/mob/living/simple_mob/combat_ai_test_subject, run_loc_floor_bottom_left)
	var/mob/living/carbon/human/attacker = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/datum/ai_brain/B = victim.ai_brain
	B.primary_threat = null
	B.active_behavior_type = null
	TEST_ASSERT(B.hibernate_calm(), "calm brain refused to hibernate")
	TEST_ASSERT(!om_attached(victim, /datum/om/behaviour/ai_brain/strategic), "hibernating brain kept its strategic loop")
	B.notify_damage(10, INJURY_BLUNT, attacker)
	TEST_ASSERT_EQUAL(B.primary_threat, attacker, "an attack did not give the brain its attacker as target")
	TEST_ASSERT(om_attached(victim, /datum/om/behaviour/ai_brain/strategic), "an attack did not wake the strategic loop")
	TEST_ASSERT(om_attached(victim, /datum/om/behaviour/ai_brain/tactical), "an attack did not start the tactical loop")
	TEST_ASSERT_NULL(B.om_sleep_violation(), "a woken brain reported a sleep violation")

/// Driven through its OM behaviours, a brain with a target walks to it and attacks it.
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
	// Breaks as soon as it attacks; the budget only matters on a loaded machine,
	// where 30 rounds sometimes ran out just before the swing (also seen on
	// unsharded merge runs), so it's 60.
	for(var/i in 1 to 60)
		hunter.next_click = 0
		om_tick_now(hunter, /datum/om/behaviour/ai_brain/strategic, 2)
		om_tick_now(hunter, /datum/om/behaviour/ai_brain/tactical, 0.25)
		closest = min(closest, get_dist(hunter, target))
		if(B.last_attack_at)
			break
		om_test_ticks(3)
	TEST_ASSERT(closest < start_dist, "the brain did not move toward its target (distance stayed [start_dist])")
	TEST_ASSERT(B.last_attack_at, "the brain reached its target but never attacked (diag: dist=[get_dist(hunter, target)] closest=[closest] adjacent=[hunter.Adjacent(target)] threat=[B.primary_threat] target_stat=[target.stat] cooldown_ok=[hunter.checkClickCooldown()] hunter=[AREACOORD(hunter)] target=[AREACOORD(target)] behaviour=[B.active_behavior_type])")

#endif
