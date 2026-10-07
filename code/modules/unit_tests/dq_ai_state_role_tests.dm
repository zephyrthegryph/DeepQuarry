// AI states, roles, orders, shared paths and the pack-forming factions (code/modules/combat_ai/{states,roles,pack}, doc/rewrite/ai_packs.md B3, B4, B6, B7).

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// A state of a test faction's own set: it allows nothing, so a brain in it runs no tactic.
CAPABILITY_TYPE(ai_state_test_hush, CAP_AI_STATE_TEST_HUSH, /datum/capability/ai_state/test_hush, key = NONE)
/datum/capability/ai_state/test_hush
	state_name = "hush"

/datum/capability/ai_state/test_hush/entries()
	return list()

/datum/capability/ai_state/test_hush/allows(datum/ai_behavior/B)
	return FALSE

/// A faction with its own state set: its calm is the hush state.
/datum/faction_data/test_states
	faction_key = "test_states"
	player_disposition = DQ_DISPOSITION_HOSTILE

/datum/faction_data/test_states/New()
	. = ..()
	states = list(
		"calm" = /datum/capability/ai_state/test_hush,
		"alert" = /datum/capability/ai_state/alert,
		"engaged" = /datum/capability/ai_state/engaged,
		"fleeing" = /datum/capability/ai_state/fleeing,
		"regroup" = /datum/capability/ai_state/regroup)

/mob/living/simple_mob/combat_ai_pack_subject/states
	faction = "test_states"

/// A brain moves through calm, engaged, alert, calm as its facts change; what a state allows and how soon its pack perceives are the state's.
/datum/unit_test/dq_ai_state_transitions

/datum/unit_test/dq_ai_state_transitions/Run()
	var/list/pair = ai_pair(ai_floor(0), ai_floor(2))
	var/mob/living/simple_mob/combat_ai_tactics_subject/S = pair[1]
	var/datum/ai_brain/B = S.ai_brain
	B.lose_target()
	B.assess_state()
	TEST_ASSERT_EQUAL(B.ai_state, /datum/capability/ai_state/calm, "a brain with nothing to fight is not calm")
	TEST_ASSERT(granted(B, /datum/capability/ai_state/calm), "the calm capability is not granted to the brain")
	var/datum/ai_behavior/melee = dq_get_behavior(/datum/ai_behavior/melee_attack)
	var/datum/ai_behavior/wander = dq_get_behavior(/datum/ai_behavior/idle_wander)
	TEST_ASSERT(!B.state_allows(melee), "calm allowed a combat tactic")
	TEST_ASSERT(B.state_allows(wander), "calm did not allow an idle tactic")
	TEST_ASSERT_EQUAL(B.state_window(), PACK_PERCEIVE_CALM, "a calm brain does not ask its pack for the calm window")
	B.give_target(pair[2], TRUE)
	B.assess_state()
	TEST_ASSERT_EQUAL(B.ai_state, /datum/capability/ai_state/engaged, "a brain with a target is not engaged")
	TEST_ASSERT(granted(B, /datum/capability/ai_state/engaged) && !granted(B, /datum/capability/ai_state/calm), "modes() did not swap the capability")
	TEST_ASSERT(B.state_allows(melee), "engaged did not allow a combat tactic")
	TEST_ASSERT(B.state_window() <= PACK_PERCEIVE_OFFSCREEN, "an engaged brain's window is longer than the off-screen one")
	B.lose_target()
	TEST_ASSERT_EQUAL(B.ai_state, /datum/capability/ai_state/alert, "a brain that lost its target did not stay alert")
	B.settle_state()
	TEST_ASSERT_EQUAL(B.ai_state, /datum/capability/ai_state/calm, "an alert brain with nothing hostile known did not settle to calm")
	// fleeing: while a fleeing tactic runs
	B.give_target(pair[2], TRUE)
	S.test_vitality = 0.1
	B.run_behavior(/datum/ai_behavior/flee_low_hp, pair[2], null)
	TEST_ASSERT_EQUAL(B.ai_state, /datum/capability/ai_state/fleeing, "running a fleeing tactic did not make the brain fleeing")
	TEST_ASSERT(!B.state_allows(melee), "fleeing allowed a combat tactic")
	B.stop_active(DQ_BEHAVIOR_STOP_COMPLETED)
	TEST_ASSERT(B.ai_state != /datum/capability/ai_state/fleeing, "the brain stayed fleeing after the flight ended")

/// A faction supplies its own state set: its calm is the hush state, which allows nothing.
/datum/unit_test/dq_ai_state_faction_swap

/datum/unit_test/dq_ai_state_faction_swap/Run()
	var/mob/living/simple_mob/S = pack_mob(0, /mob/living/simple_mob/combat_ai_pack_subject/states)
	var/datum/ai_brain/B = S.ai_brain
	TEST_ASSERT_EQUAL(B.ai_state, /datum/capability/ai_state/test_hush, "the brain did not start in its faction's calm")
	TEST_ASSERT(!B.state_allows(dq_get_behavior(/datum/ai_behavior/idle_wander)), "the faction's calm still allowed a tactic")
	TEST_ASSERT(granted(B, /datum/capability/ai_state/test_hush), "the faction's state capability is not granted")

/// The leader is the member with the most authority: roles and the alpha trait hold on the stat, health and seniority add; a change re-elects.
/datum/unit_test/dq_ai_roles_authority_election

/datum/unit_test/dq_ai_roles_authority_election/Run()
	var/mob/living/simple_mob/A = pack_mob(0)
	var/mob/living/simple_mob/B = pack_mob(1)
	var/datum/ai_pack/P = A.ai_brain.pack
	TEST_ASSERT_EQUAL(length(P.members), 2, "the two did not form a pack")
	TEST_ASSERT_EQUAL(P.leader, A.ai_brain, "the first member is not the leader")
	A.ai_brain.set_alpha(TRUE)
	TEST_ASSERT_EQUAL(stat_value(A, STAT_AI_AUTHORITY), 30, "the alpha trait does not hold +30 authority")
	B.ai_brain.grant_role(/datum/capability/ai_role/lord)
	TEST_ASSERT_EQUAL(stat_value(B, STAT_AI_AUTHORITY), 100, "the lord role does not hold +100 authority")
	TEST_ASSERT(B.ai_brain.has_role(/datum/capability/ai_role/lord), "the lord role is not granted")
	TEST_ASSERT_EQUAL(P.leader, B.ai_brain, "the lord did not become the leader")
	B.ai_brain.revoke_role(/datum/capability/ai_role/lord)
	TEST_ASSERT_EQUAL(P.leader, A.ai_brain, "the alpha did not lead once the lord role was revoked")
	TEST_ASSERT_EQUAL(stat_value(B, STAT_AI_AUTHORITY), 0, "revoking the lord role left authority held")

/// A sworn member joins its lord's pack, never splits off, takes the lord as an ally and the lord's hostile standings as its own, and is freed when the lord dies.
/datum/unit_test/dq_ai_roles_sworn_serves_lord

/datum/unit_test/dq_ai_roles_sworn_serves_lord/Run()
	var/mob/living/simple_mob/lord = pack_mob(0)
	var/mob/living/simple_mob/servant = allocate(/mob/living/simple_mob/combat_ai_tactics_subject, ai_floor(1))
	var/mob/living/carbon/human/H = pack_human(2)
	lord.ai_brain.grant_role(/datum/capability/ai_role/lord)
	servant.ai_brain.set_leader(lord)
	var/datum/ai_pack/P = lord.ai_brain.pack
	TEST_ASSERT_EQUAL(servant.ai_brain.pack, P, "a follower did not join its leader's pack")
	TEST_ASSERT(servant.ai_brain.has_role(/datum/capability/ai_role/sworn), "a follower is not sworn")
	TEST_ASSERT(servant.ai_brain.is_tethered(), "a sworn member is not tethered")
	TEST_ASSERT_EQUAL(servant.ai_brain.disposition_to(lord), DQ_DISPOSITION_ALLY, "a sworn member does not hold its lord as an ally")
	// tether: beyond the leave radius it stays
	servant.forceMove(ai_floor(4))
	P.upkeep()
	TEST_ASSERT_EQUAL(servant.ai_brain.pack, P, "a sworn member split off beyond the leave radius")
	// serves(lord): the lord's grudge is the servant's
	lord.ai_brain.add_personal(H, DQ_DISPOSITION_HOSTILE, DQ_GRUDGE_DURATION, "test")
	servant.ai_brain.sync_serves()
	TEST_ASSERT_EQUAL(servant.ai_brain.disposition_to(H), DQ_DISPOSITION_HOSTILE, "a sworn member did not take its lord's hostile standing")
	TEST_ASSERT_EQUAL(standing_decided_by(servant, H), lord, "the lord's row is not what decides it")
	// the lord dies: freed
	lord.set_stat(DEAD)
	TEST_ASSERT(!servant.ai_brain.has_role(/datum/capability/ai_role/sworn), "a servant stayed sworn after its lord died")
	TEST_ASSERT(servant.ai_brain.pack != P, "a servant stayed in the dead lord's pack")
	TEST_ASSERT(standing_decided_by(servant, H) != lord, "a freed servant kept its lord's standing rows")

/// Orders: an intent has a source and a lifetime, is read through active_intents(), and ends with its issuer; a retreat order makes the packmates retreat.
/datum/unit_test/dq_ai_roles_intents

/datum/unit_test/dq_ai_roles_intents/Run()
	var/mob/living/simple_mob/A = pack_mob(0)
	var/mob/living/simple_mob/B = pack_mob(1)
	var/mob/living/carbon/human/H = pack_human(2)
	var/datum/ai_pack/P = A.ai_brain.pack
	var/datum/ai_intent/order = intend(P, /datum/ai_intent/retreat, H, A, 8 SECONDS)
	TEST_ASSERT_NOTNULL(order, "no intent was made")
	TEST_ASSERT(order in B.ai_brain.active_intents(), "a packmate does not see the order")
	TEST_ASSERT_NOTNULL(B.ai_brain.intent_from_others(/datum/ai_intent/retreat), "the order is not from somebody else for the packmate")
	TEST_ASSERT_NULL(A.ai_brain.intent_from_others(/datum/ai_intent/retreat), "the issuer counts its own order as somebody else's")
	B.ai_brain.give_target(H, TRUE)
	TEST_ASSERT_EQUAL(dq_ai_test_score(dq_ai_test_eval(B.ai_brain, /datum/ai_behavior/pack_retreat)), 110, "a retreat order did not make the packmate's pack_retreat score")
	var/datum/ai_intent/again = intend(P, /datum/ai_intent/retreat, H, A, 8 SECONDS)
	TEST_ASSERT_EQUAL(again, order, "the same order made a second intent")
	// it ends with its issuer
	A.set_stat(DEAD)
	TEST_ASSERT_EQUAL(length(P.active_intents()), 0, "an order outlived its dead issuer")

/// Shared paths: one flow field per goal for the whole pack, read as each member's next step; it reaches the goal in as many steps as the individual
/// route in the open, and a door change builds a new one.
/datum/unit_test/dq_ai_pack_flow_field

/datum/unit_test/dq_ai_pack_flow_field/Run()
	var/mob/living/simple_mob/A = pack_mob(0)
	var/mob/living/simple_mob/B = pack_mob(0)
	var/mob/living/simple_mob/C = pack_mob(1)
	var/datum/ai_pack/P = A.ai_brain.pack
	TEST_ASSERT_EQUAL(length(P.members), 3, "three mobs did not form one pack")
	TEST_ASSERT(P.shares_paths(), "a pack of three does not share paths")
	var/turf/goal = ai_floor(4)
	var/builds = P.flow_builds
	var/start_dist = get_dist(A, goal)
	var/turf/first = P.flow_step(A.ai_brain, goal)
	TEST_ASSERT_NOTNULL(first, "the flow field gave no step")
	TEST_ASSERT(get_dist(first, goal) < start_dist, "the flow step does not approach the goal")
	P.flow_step(B.ai_brain, goal)
	P.flow_step(C.ai_brain, goal)
	TEST_ASSERT_EQUAL(P.flow_builds, builds + 1, "the pack built more than one field for one goal")
	// walk the field: as many steps as the straight route in the open
	var/steps = 0
	while(get_turf(A) != goal && steps < 10)
		var/turf/next = P.flow_step(A.ai_brain, goal)
		if(!next)
			break
		A.forceMove(next)
		steps++
	TEST_ASSERT_EQUAL(get_turf(A), goal, "walking the flow field did not reach the goal")
	TEST_ASSERT_EQUAL(steps, start_dist, "the flow field route is longer than the individual route in the open")
	// the navigation revision invalidates the field
	publish_navigation_change()
	P.flow_step(B.ai_brain, goal)
	TEST_ASSERT_EQUAL(P.flow_builds, builds + 2, "a navigation change did not build a new field")
	// a pack of one never builds fields
	var/mob/living/simple_mob/solo = allocate(/mob/living/simple_mob/combat_ai_tactics_subject, ai_floor(0))
	TEST_ASSERT(!solo.ai_brain.pack.shares_paths(), "a pack of one shares paths")

/// The pack-forming factions: wolves, spiders and xenomorphs form packs; real mobs of those types join one.
/datum/unit_test/dq_ai_pack_forming_factions

/datum/unit_test/dq_ai_pack_forming_factions/Run()
	for(var/faction in list(FACTION_WOLF, FACTION_SPIDERS, FACTION_XENO))
		var/datum/faction_data/data = dq_faction_data_for(faction)
		TEST_ASSERT_EQUAL(data.faction_key, faction, "[faction] has no faction data of its own")
		TEST_ASSERT(data.pack_join_radius > 0, "[faction] does not form packs")
	TEST_ASSERT_EQUAL(dq_faction_data_for(FACTION_CREATURE).pack_join_radius, 0, "a faction that should form no packs does")
	for(var/type in list(/mob/living/simple_mob/vore/wolf, /mob/living/simple_mob/animal/giant_spider/hunter, /mob/living/simple_mob/xeno_ch/hunter))
		var/mob/living/simple_mob/first = allocate(type, ai_floor(0))
		var/mob/living/simple_mob/second = allocate(type, ai_floor(1))
		TEST_ASSERT_NOTNULL(first.ai_brain, "[type] has no brain")
		TEST_ASSERT_EQUAL(first.ai_brain.pack, second.ai_brain.pack, "two [type] side by side did not form a pack")
		TEST_ASSERT_EQUAL(length(first.ai_brain.pack.members), 2, "the [type] pack has the wrong size")

#endif
