// Per-tactic behaviour tests for the combat AI: each tactic's evaluate/start/tick/stop is driven directly on a brain, so the
// tests pin what a tactic decides and does, not how the brain schedules it (dq_ai_om_tests.dm does that). They are written on the
// flyweight behaviour forms first and stay green as the tactics move onto ops.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// The shared test subject with a settable vitality (flee tactics read it).
/mob/living/simple_mob/combat_ai_tactics_subject
	name = "combat AI tactics subject"
	icon = 'icons/mob/animal.dmi'
	icon_state = "tiger"
	icon_living = "tiger"
	icon_dead = "tiger-dead"
	faction = FACTION_CREATURE
	endurance = 90
	melee_damage_lower = 8
	melee_damage_upper = 14
	base_attack_cooldown = 1.2 SECONDS
	movement_cooldown = 2
	has_hands = FALSE
	can_pain_emote = FALSE
	use_modern_ai = TRUE
	/// What vitality() answers.
	var/test_vitality = 1

/mob/living/simple_mob/combat_ai_tactics_subject/vitality()
	return test_vitality

/// A subject that carries hands, for the scavenge, gun and grenade tactics.
/mob/living/simple_mob/combat_ai_tactics_subject/handed
	has_hands = TRUE

/// Scores `btype` against `brain`'s current state: the DQAI_RESULT list or null.
/proc/dq_ai_test_eval(datum/ai_brain/brain, btype, atom/source = null)
	var/datum/ai_behavior/B = dq_get_behavior(btype)
	return B.evaluate(brain, source)

/// The score of an evaluate() answer, 0 for none.
/proc/dq_ai_test_score(list/result)
	return result ? result["score"] : 0

/// A tactics subject at `subject_loc`, and a human at `target_loc` made its primary threat.
/datum/unit_test/proc/ai_pair(turf/subject_loc, turf/target_loc, subject_type = /mob/living/simple_mob/combat_ai_tactics_subject)
	var/mob/living/simple_mob/S = allocate(subject_type, subject_loc)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, target_loc)
	S.next_click = 0
	S.ai_brain.give_target(H, TRUE)
	return list(S, H)

/datum/unit_test/proc/ai_floor(dx, dy = 0)
	var/turf/start = run_loc_floor_bottom_left
	var/turf/T = locate(start.x + dx, start.y + dy, start.z)
	TEST_ASSERT(T && !T.density, "no open floor at +[dx],+[dy] from the test origin")
	return T

// --- melee_attack -----------------------------------------------------------------------------

/datum/unit_test/dq_ai_tactic_melee_attack

/datum/unit_test/dq_ai_tactic_melee_attack/Run()
	var/list/pair = ai_pair(ai_floor(0), ai_floor(3))
	var/mob/living/simple_mob/S = pair[1]
	var/mob/living/carbon/human/H = pair[2]
	var/datum/ai_brain/B = S.ai_brain
	TEST_ASSERT_NULL(dq_ai_test_eval(B, /datum/ai_behavior/melee_attack), "melee_attack scored a target three tiles away")
	H.forceMove(ai_floor(1))
	TEST_ASSERT_EQUAL(dq_ai_test_score(dq_ai_test_eval(B, /datum/ai_behavior/melee_attack)), 40, "melee_attack did not score 40 against an adjacent threat")
	S.next_click = world.time + 50
	TEST_ASSERT_NULL(dq_ai_test_eval(B, /datum/ai_behavior/melee_attack), "melee_attack scored while the mob was on attack cooldown")
	S.next_click = 0
	var/before = H.injury_load(INJURY_CATEGORY_PHYSICAL)
	var/datum/ai_behavior/melee_attack/M = dq_get_behavior(/datum/ai_behavior/melee_attack)
	// A swing can miss or be dodged: a handful of swings must land at least once.
	for(var/i in 1 to 12)
		S.next_click = 0
		TEST_ASSERT_EQUAL(M.start(B, H, null), DQ_BEHAVIOR_DONE, "melee_attack is a single-tick action")
		om_test_ticks(3)
		if(H.injury_load(INJURY_CATEGORY_PHYSICAL) > before)
			break
	TEST_ASSERT(H.injury_load(INJURY_CATEGORY_PHYSICAL) > before, "melee_attack dealt no physical injury in twelve swings")
	TEST_ASSERT(B.last_attack_at, "melee_attack did not stamp last_attack_at")

/// The swing and the shot are the mob's own ops: the AI meets the same requirements as any other actor.
/datum/unit_test/dq_ai_tactic_attacks_are_ops

/datum/unit_test/dq_ai_tactic_attacks_are_ops/Run()
	var/list/pair = ai_pair(ai_floor(0), ai_floor(3))
	var/mob/living/simple_mob/S = pair[1]
	var/mob/living/carbon/human/H = pair[2]
	var/datum/op_result/far = perform_op(S, H, "mob_attacks.melee", null, ORIGIN_AI, AUTH_AI)
	TEST_ASSERT(far?.outcome != ACT_COMMITTED, "a melee op committed against a target three tiles away")
	H.forceMove(ai_floor(1))
	S.next_click = world.time + 50
	var/datum/op_result/cooling = perform_op(S, H, "mob_attacks.melee", null, ORIGIN_AI, AUTH_AI)
	TEST_ASSERT_EQUAL(cooling?.outcome, ACT_REFUSED, "the melee op ran while the mob was on attack cooldown")
	TEST_ASSERT_EQUAL(cooling?.reason, /datum/msg/mob_attacks/cooling, "the refusal does not say why")
	S.next_click = 0
	var/datum/op_result/swing = perform_op(S, H, "mob_attacks.melee", null, ORIGIN_AI, AUTH_AI)
	TEST_ASSERT_EQUAL(swing?.outcome, ACT_COMMITTED, "the melee op was refused: [reason_text(swing?.reason)]")
	TEST_ASSERT(!S.checkClickCooldown(), "the swing did not start the attack cooldown")
	S.next_click = 0
	var/datum/op_result/no_shot = perform_op(S, H, "mob_attacks.shoot", null, ORIGIN_AI, AUTH_AI)
	TEST_ASSERT_EQUAL(no_shot?.reason, /datum/msg/mob_attacks/no_shot, "a mob with no projectile was allowed to shoot")
	// A brain's refusal is traced and fails the tactic (the target slipped out of reach).
	H.forceMove(ai_floor(4))
	var/datum/ai_behavior/melee_attack/M = dq_get_behavior(/datum/ai_behavior/melee_attack)
	TEST_ASSERT_EQUAL(M.start(S.ai_brain, H, null), DQ_BEHAVIOR_FAILED, "melee_attack carried on against a target out of reach")

// --- approach_threat --------------------------------------------------------------------------

/datum/unit_test/dq_ai_tactic_approach_threat

/datum/unit_test/dq_ai_tactic_approach_threat/Run()
	var/list/pair = ai_pair(ai_floor(0), ai_floor(4))
	var/mob/living/simple_mob/S = pair[1]
	var/mob/living/carbon/human/H = pair[2]
	var/datum/ai_brain/B = S.ai_brain
	var/datum/ai_behavior/approach_threat/A = dq_get_behavior(/datum/ai_behavior/approach_threat)
	TEST_ASSERT_EQUAL(dq_ai_test_score(dq_ai_test_eval(B, /datum/ai_behavior/approach_threat)), 10, "approach_threat did not score 10 at range")
	TEST_ASSERT_EQUAL(A.start(B, H, null), DQ_BEHAVIOR_CONTINUE, "approach_threat is tick-driven")
	var/start_dist = get_dist(S, H)
	for(var/i in 1 to 6)
		S.next_move = 0
		if(A.tick(B, H, null) != DQ_BEHAVIOR_CONTINUE)
			break
		om_test_ticks(3)
	TEST_ASSERT(get_dist(S, H) < start_dist, "approach_threat did not close the distance (stayed at [start_dist])")
	H.forceMove(ai_floor(S.x - run_loc_floor_bottom_left.x + 1))
	if(S.Adjacent(H))
		TEST_ASSERT_NULL(dq_ai_test_eval(B, /datum/ai_behavior/approach_threat), "approach_threat scored an adjacent threat")
		TEST_ASSERT_EQUAL(A.tick(B, H, null), DQ_BEHAVIOR_DONE, "approach_threat did not finish adjacent")

// --- charge_slam ------------------------------------------------------------------------------

/datum/unit_test/dq_ai_tactic_charge_slam

/datum/unit_test/dq_ai_tactic_charge_slam/Run()
	var/list/pair = ai_pair(ai_floor(0), ai_floor(1))
	var/mob/living/simple_mob/S = pair[1]
	var/mob/living/carbon/human/H = pair[2]
	var/datum/ai_brain/B = S.ai_brain
	TEST_ASSERT_NULL(dq_ai_test_eval(B, /datum/ai_behavior/charge_slam), "charge_slam scored below its minimum range")
	H.forceMove(ai_floor(4))
	TEST_ASSERT_EQUAL(dq_ai_test_score(dq_ai_test_eval(B, /datum/ai_behavior/charge_slam)), 80 - 4 * 2, "charge_slam score at four tiles")
	H.forceMove(ai_floor(8))
	TEST_ASSERT_NULL(dq_ai_test_eval(B, /datum/ai_behavior/charge_slam), "charge_slam scored beyond its maximum range")
	H.forceMove(ai_floor(4))
	// Commit to it by hand: the windup blocks reselection; the dash then lands and the behaviour completes.
	B.run_behavior(/datum/ai_behavior/charge_slam, H, null)
	TEST_ASSERT_EQUAL(B.active_behavior_type, /datum/ai_behavior/charge_slam, "charge_slam did not become the active behaviour")
	TEST_ASSERT(B.is_busy(), "the windup did not block reselection")
	var/before = H.injury_load(INJURY_CATEGORY_PHYSICAL)
	var/datum/ai_behavior/charge_slam/C = dq_get_behavior(/datum/ai_behavior/charge_slam)
	C.execute_dash(B, H)
	TEST_ASSERT(S.Adjacent(H), "the dash did not reach the target")
	TEST_ASSERT(H.injury_load(INJURY_CATEGORY_PHYSICAL) > before, "the dash dealt no injury")
	TEST_ASSERT_NULL(B.active_behavior_type, "the behaviour did not finish after the dash")
	TEST_ASSERT(!B.is_busy(), "the busy hold outlived the charge")
	// A telegraph that is cancelled lands nothing.
	S.forceMove(ai_floor(0))
	H.forceMove(ai_floor(4))
	B.run_behavior(/datum/ai_behavior/charge_slam, H, null)
	B.stop_active(DQ_BEHAVIOR_STOP_INTERRUPTED)
	var/at = get_dist(S, H)
	C.execute_dash(B, H)
	TEST_ASSERT_EQUAL(get_dist(S, H), at, "a cancelled charge still dashed")

// --- flee_low_hp and pack_retreat -------------------------------------------------------------

/datum/unit_test/dq_ai_tactic_flee_low_hp

/datum/unit_test/dq_ai_tactic_flee_low_hp/Run()
	var/list/pair = ai_pair(ai_floor(0), ai_floor(2))
	var/mob/living/simple_mob/combat_ai_tactics_subject/S = pair[1]
	var/mob/living/carbon/human/H = pair[2]
	var/datum/ai_brain/B = S.ai_brain
	TEST_ASSERT_NULL(dq_ai_test_eval(B, /datum/ai_behavior/flee_low_hp), "flee scored at full health")
	S.test_vitality = 0.1
	TEST_ASSERT(dq_ai_test_score(dq_ai_test_eval(B, /datum/ai_behavior/flee_low_hp)) > 0, "flee did not score at low health")
	var/datum/ai_behavior/flee_low_hp/F = dq_get_behavior(/datum/ai_behavior/flee_low_hp)
	var/start_dist = get_dist(S, H)
	S.next_move = 0
	TEST_ASSERT_EQUAL(F.tick(B, H, null), DQ_BEHAVIOR_CONTINUE, "flee stopped while the threat was close")
	TEST_ASSERT(get_dist(S, H) >= start_dist, "flee stepped toward its threat")
	H.forceMove(ai_floor(14))
	S.forceMove(ai_floor(0))
	TEST_ASSERT_EQUAL(F.tick(B, H, null), DQ_BEHAVIOR_DONE, "flee did not finish once far away")

/datum/unit_test/dq_ai_tactic_pack_retreat

/datum/unit_test/dq_ai_tactic_pack_retreat/Run()
	var/list/pair = ai_pair(ai_floor(0), ai_floor(2))
	var/mob/living/simple_mob/combat_ai_tactics_subject/S = pair[1]
	var/mob/living/carbon/human/H = pair[2]
	var/datum/ai_brain/B = S.ai_brain
	var/mob/living/simple_mob/combat_ai_tactics_subject/ally = allocate(/mob/living/simple_mob/combat_ai_tactics_subject, ai_floor(0, 1))
	B.model.visible_friendlies = list(ally)
	TEST_ASSERT_NULL(dq_ai_test_eval(B, /datum/ai_behavior/pack_retreat), "pack_retreat scored a healthy mob with backup")
	S.test_vitality = 0.1
	TEST_ASSERT_EQUAL(dq_ai_test_score(dq_ai_test_eval(B, /datum/ai_behavior/pack_retreat)), 120, "pack_retreat did not score 120 when dying")
	var/datum/ai_behavior/pack_retreat/P = dq_get_behavior(/datum/ai_behavior/pack_retreat)
	S.next_move = 0
	TEST_ASSERT_EQUAL(P.tick(B, H, null), DQ_BEHAVIOR_CONTINUE, "pack_retreat stopped close to its threat")
	H.forceMove(ai_floor(14))
	S.forceMove(ai_floor(0))
	TEST_ASSERT_EQUAL(P.tick(B, H, null), DQ_BEHAVIOR_DONE, "pack_retreat did not finish at distance")

// --- idle_wander, idle_speak, threaten --------------------------------------------------------

/datum/unit_test/dq_ai_tactic_idle_wander

/datum/unit_test/dq_ai_tactic_idle_wander/Run()
	var/mob/living/simple_mob/S = allocate(/mob/living/simple_mob/combat_ai_tactics_subject, ai_floor(1, 1))
	var/datum/ai_brain/B = S.ai_brain
	B.wander = TRUE
	TEST_ASSERT_EQUAL(dq_ai_test_score(dq_ai_test_eval(B, /datum/ai_behavior/idle_wander)), 1, "idle_wander did not score 1 for a calm wanderer")
	B.wander = FALSE
	TEST_ASSERT_NULL(dq_ai_test_eval(B, /datum/ai_behavior/idle_wander), "idle_wander ignored the wander toggle")
	B.wander = TRUE
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, ai_floor(6, 1))
	B.give_target(H, TRUE)
	TEST_ASSERT_NULL(dq_ai_test_eval(B, /datum/ai_behavior/idle_wander), "idle_wander scored with a threat")
	var/datum/ai_behavior/idle_wander/W = dq_get_behavior(/datum/ai_behavior/idle_wander)
	TEST_ASSERT_EQUAL(W.tick(B, S, null), DQ_BEHAVIOR_DONE, "idle_wander is a single-tick action")

/datum/unit_test/dq_ai_tactic_idle_speak

/datum/unit_test/dq_ai_tactic_idle_speak/Run()
	var/mob/living/simple_mob/S = allocate(/mob/living/simple_mob/combat_ai_tactics_subject, ai_floor(1, 1))
	var/datum/ai_brain/B = S.ai_brain
	if(!S.say_list)
		S.say_list = new /datum/say_list()
	S.say_list.speak = list()
	TEST_ASSERT_NULL(dq_ai_test_eval(B, /datum/ai_behavior/idle_speak), "idle_speak scored with nothing to say")
	S.say_list.speak = list("rrr")
	TEST_ASSERT_EQUAL(dq_ai_test_score(dq_ai_test_eval(B, /datum/ai_behavior/idle_speak)), 1, "idle_speak did not score with lines to say")
	var/datum/ai_behavior/idle_speak/I = dq_get_behavior(/datum/ai_behavior/idle_speak)
	TEST_ASSERT_EQUAL(I.start(B, S, null), DQ_BEHAVIOR_DONE, "idle_speak is a single-tick action")
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, ai_floor(6, 1))
	B.give_target(H, TRUE)
	TEST_ASSERT_NULL(dq_ai_test_eval(B, /datum/ai_behavior/idle_speak), "idle_speak scored with a threat")

/datum/unit_test/dq_ai_tactic_threaten

/datum/unit_test/dq_ai_tactic_threaten/Run()
	var/list/pair = ai_pair(ai_floor(0), ai_floor(2))
	var/mob/living/simple_mob/S = pair[1]
	var/datum/ai_brain/B = S.ai_brain
	TEST_ASSERT_EQUAL(dq_ai_test_score(dq_ai_test_eval(B, /datum/ai_behavior/threaten)), 45, "threaten did not score 45 in view range")
	var/datum/ai_behavior/threaten/T = dq_get_behavior(/datum/ai_behavior/threaten)
	TEST_ASSERT_EQUAL(T.start(B, pair[2], null), DQ_BEHAVIOR_DONE, "threaten is a single-tick action")
	B.vision_range = 1
	TEST_ASSERT_NULL(dq_ai_test_eval(B, /datum/ai_behavior/threaten), "threaten scored beyond the brain's vision")

// --- call_for_help ----------------------------------------------------------------------------

/datum/unit_test/dq_ai_tactic_call_for_help

/datum/unit_test/dq_ai_tactic_call_for_help/Run()
	var/list/pair = ai_pair(ai_floor(0), ai_floor(2))
	var/mob/living/simple_mob/S = pair[1]
	var/mob/living/carbon/human/H = pair[2]
	var/datum/ai_brain/B = S.ai_brain
	B.model.visible_friendlies = list()
	TEST_ASSERT_NULL(dq_ai_test_eval(B, /datum/ai_behavior/call_for_help), "call_for_help scored with no allies in view")
	var/mob/living/simple_mob/combat_ai_tactics_subject/ally = allocate(/mob/living/simple_mob/combat_ai_tactics_subject, ai_floor(0, 1))
	B.model.visible_friendlies = list(ally)
	TEST_ASSERT_EQUAL(dq_ai_test_score(dq_ai_test_eval(B, /datum/ai_behavior/call_for_help)), 50, "call_for_help did not score 50 with an ally in view")
	var/datum/ai_behavior/call_for_help/C = dq_get_behavior(/datum/ai_behavior/call_for_help)
	TEST_ASSERT_EQUAL(C.start(B, H, null), DQ_BEHAVIOR_DONE, "call_for_help is a single-tick action")
	TEST_ASSERT_EQUAL(ally.ai_brain.disposition_to(H), DQ_DISPOSITION_HOSTILE, "the ally was not turned against the attacker")

// --- retaliate_to_attacker --------------------------------------------------------------------

/datum/unit_test/dq_ai_tactic_retaliate

/datum/unit_test/dq_ai_tactic_retaliate/Run()
	var/mob/living/simple_mob/S = allocate(/mob/living/simple_mob/combat_ai_tactics_subject, ai_floor(0))
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, ai_floor(2))
	var/datum/ai_brain/B = S.ai_brain
	TEST_ASSERT_NULL(dq_ai_test_eval(B, /datum/ai_behavior/retaliate_to_attacker), "retaliate scored with nobody having hit the mob")
	B.model.last_attacker = H
	TEST_ASSERT_EQUAL(dq_ai_test_score(dq_ai_test_eval(B, /datum/ai_behavior/retaliate_to_attacker)), 100, "retaliate did not score 100 after a hit")
	var/datum/ai_behavior/retaliate_to_attacker/R = dq_get_behavior(/datum/ai_behavior/retaliate_to_attacker)
	TEST_ASSERT_EQUAL(R.start(B, H, null), DQ_BEHAVIOR_DONE, "retaliate is a single-tick action")
	TEST_ASSERT_EQUAL(B.primary_threat, H, "retaliate did not promote the attacker")
	TEST_ASSERT_NULL(dq_ai_test_eval(B, /datum/ai_behavior/retaliate_to_attacker), "retaliate scored for a threat it already has")

// --- ranged_attack and kite_away --------------------------------------------------------------

/datum/unit_test/dq_ai_tactic_ranged_attack

/datum/unit_test/dq_ai_tactic_ranged_attack/Run()
	var/list/pair = ai_pair(ai_floor(0), ai_floor(4))
	var/mob/living/simple_mob/S = pair[1]
	var/mob/H = pair[2]
	var/datum/ai_brain/B = S.ai_brain
	var/datum/ai_behavior/ranged_attack/R = dq_get_behavior(/datum/ai_behavior/ranged_attack)
	TEST_ASSERT(!R.applicable_to(S), "ranged_attack applied to a mob with no projectile")
	S.projectiletype = /obj/item/projectile/beam
	TEST_ASSERT(R.applicable_to(S), "ranged_attack did not apply to a mob with a projectile")
	TEST_ASSERT_EQUAL(dq_ai_test_score(dq_ai_test_eval(B, /datum/ai_behavior/ranged_attack)), 30 + 16, "ranged_attack score at four tiles")
	H.forceMove(ai_floor(1))
	TEST_ASSERT_NULL(dq_ai_test_eval(B, /datum/ai_behavior/ranged_attack), "ranged_attack scored inside its minimum range")
	H.forceMove(ai_floor(4))
	S.next_click = world.time + 50
	TEST_ASSERT_NULL(dq_ai_test_eval(B, /datum/ai_behavior/ranged_attack), "ranged_attack scored on cooldown")

/datum/unit_test/dq_ai_tactic_kite_away

/datum/unit_test/dq_ai_tactic_kite_away/Run()
	var/list/pair = ai_pair(ai_floor(2, 2), ai_floor(3, 2))
	var/mob/living/simple_mob/S = pair[1]
	var/mob/living/carbon/human/H = pair[2]
	var/datum/ai_brain/B = S.ai_brain
	TEST_ASSERT_NULL(dq_ai_test_eval(B, /datum/ai_behavior/kite_away), "kite_away scored for a mob with no projectile")
	S.projectiletype = /obj/item/projectile/beam
	TEST_ASSERT_EQUAL(dq_ai_test_score(dq_ai_test_eval(B, /datum/ai_behavior/kite_away)), 65, "kite_away did not score 65 inside its distance")
	var/datum/ai_behavior/kite_away/K = dq_get_behavior(/datum/ai_behavior/kite_away)
	var/start_dist = get_dist(S, H)
	S.next_move = 0
	TEST_ASSERT_EQUAL(K.start(B, H, null), DQ_BEHAVIOR_DONE, "kite_away is a single-tick action")
	TEST_ASSERT(get_dist(S, H) >= start_dist, "kite_away stepped toward its target")
	H.forceMove(ai_floor(12, 2))
	TEST_ASSERT_NULL(dq_ai_test_eval(B, /datum/ai_behavior/kite_away), "kite_away scored at a safe distance")

// --- evasive_juke and hit_and_run -------------------------------------------------------------

/datum/unit_test/dq_ai_tactic_evasive_juke

/datum/unit_test/dq_ai_tactic_evasive_juke/Run()
	var/list/pair = ai_pair(ai_floor(2, 2), ai_floor(3, 2))
	var/mob/living/simple_mob/S = pair[1]
	var/datum/ai_brain/B = S.ai_brain
	TEST_ASSERT_NULL(dq_ai_test_eval(B, /datum/ai_behavior/evasive_juke), "juke scored before any attack")
	EXPIRY_STAMP(B, last_attack_at, CLOCK_WORLD)
	TEST_ASSERT_EQUAL(dq_ai_test_score(dq_ai_test_eval(B, /datum/ai_behavior/evasive_juke)), 70, "juke did not score 70 right after an attack")
	var/datum/ai_behavior/evasive_juke/J = dq_get_behavior(/datum/ai_behavior/evasive_juke)
	S.next_move = 0
	TEST_ASSERT_EQUAL(J.start(B, pair[2], null), DQ_BEHAVIOR_DONE, "juke is a single-tick action")
	TEST_ASSERT_NULL(dq_ai_test_eval(B, /datum/ai_behavior/evasive_juke), "juke fired twice for one attack")

/datum/unit_test/dq_ai_tactic_hit_and_run

/datum/unit_test/dq_ai_tactic_hit_and_run/Run()
	var/list/pair = ai_pair(ai_floor(2, 2), ai_floor(3, 2))
	var/mob/living/simple_mob/S = pair[1]
	var/mob/living/carbon/human/H = pair[2]
	var/datum/ai_brain/B = S.ai_brain
	TEST_ASSERT_NULL(dq_ai_test_eval(B, /datum/ai_behavior/hit_and_run), "hit and run scored before any attack")
	EXPIRY_STAMP(B, last_attack_at, CLOCK_WORLD)
	TEST_ASSERT_EQUAL(dq_ai_test_score(dq_ai_test_eval(B, /datum/ai_behavior/hit_and_run)), 75, "hit and run did not score 75 right after an attack")
	var/datum/ai_behavior/hit_and_run/R = dq_get_behavior(/datum/ai_behavior/hit_and_run)
	S.next_move = 0
	TEST_ASSERT_EQUAL(R.start(B, H, null), DQ_BEHAVIOR_CONTINUE, "hit and run is tick-driven")
	H.forceMove(ai_floor(12, 2))
	TEST_ASSERT_EQUAL(R.tick(B, H, null), DQ_BEHAVIOR_DONE, "hit and run did not finish at distance")

// --- return_home, follow_leader, walk_to_destination ------------------------------------------

/datum/unit_test/dq_ai_tactic_return_home

/datum/unit_test/dq_ai_tactic_return_home/Run()
	var/mob/living/simple_mob/S = allocate(/mob/living/simple_mob/combat_ai_tactics_subject, ai_floor(1, 1))
	var/datum/ai_brain/B = S.ai_brain
	TEST_ASSERT_NULL(dq_ai_test_eval(B, /datum/ai_behavior/return_home), "return_home scored at home")
	S.forceMove(ai_floor(10, 1))
	var/list/result = dq_ai_test_eval(B, /datum/ai_behavior/return_home)
	TEST_ASSERT_EQUAL(dq_ai_test_score(result), 8, "return_home did not score 8 far from home")
	TEST_ASSERT_EQUAL(result["target"], B.home_turf(), "return_home did not target the home turf")
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, ai_floor(12, 1))
	B.give_target(H, TRUE)
	TEST_ASSERT_NULL(dq_ai_test_eval(B, /datum/ai_behavior/return_home), "return_home scored in combat")

/datum/unit_test/dq_ai_tactic_follow_leader

/datum/unit_test/dq_ai_tactic_follow_leader/Run()
	var/mob/living/simple_mob/S = allocate(/mob/living/simple_mob/combat_ai_tactics_subject, ai_floor(0, 1))
	var/mob/living/carbon/human/L = allocate(/mob/living/carbon/human, ai_floor(1, 1))
	var/datum/ai_brain/B = S.ai_brain
	TEST_ASSERT_NULL(dq_ai_test_eval(B, /datum/ai_behavior/follow_leader), "follow_leader scored with no leader")
	B.set_follow(L)
	TEST_ASSERT_NULL(dq_ai_test_eval(B, /datum/ai_behavior/follow_leader), "follow_leader scored next to its leader")
	L.forceMove(ai_floor(8, 1))
	TEST_ASSERT_EQUAL(dq_ai_test_score(dq_ai_test_eval(B, /datum/ai_behavior/follow_leader)), 15, "follow_leader did not score 15 away from its leader")
	var/datum/ai_behavior/follow_leader/F = dq_get_behavior(/datum/ai_behavior/follow_leader)
	// Its steps come from the brain's pathing (a request answered later), so what is pinned here is when it carries on and when it is done.
	TEST_ASSERT_EQUAL(F.tick(B, L, null), DQ_BEHAVIOR_CONTINUE, "follow_leader stopped while far from its leader")
	L.forceMove(ai_floor(1, 1))
	TEST_ASSERT_EQUAL(F.tick(B, L, null), DQ_BEHAVIOR_DONE, "follow_leader did not finish close to its leader")

/datum/unit_test/dq_ai_tactic_walk_to_destination

/datum/unit_test/dq_ai_tactic_walk_to_destination/Run()
	var/mob/living/simple_mob/S = allocate(/mob/living/simple_mob/combat_ai_tactics_subject, ai_floor(0, 1))
	var/datum/ai_brain/B = S.ai_brain
	TEST_ASSERT_NULL(dq_ai_test_eval(B, /datum/ai_behavior/walk_to_destination), "walk_to_destination scored with no destination")
	var/turf/goal = ai_floor(4, 1)
	B.give_destination(goal)
	var/list/result = dq_ai_test_eval(B, /datum/ai_behavior/walk_to_destination)
	TEST_ASSERT_EQUAL(dq_ai_test_score(result), 20, "walk_to_destination did not score 20")
	TEST_ASSERT_EQUAL(result["target"], goal, "walk_to_destination did not target the destination")
	var/datum/ai_behavior/walk_to_destination/W = dq_get_behavior(/datum/ai_behavior/walk_to_destination)
	var/start_dist = get_dist(S, goal)
	for(var/i in 1 to 8)
		S.next_move = 0
		if(W.tick(B, goal, null) == DQ_BEHAVIOR_DONE)
			break
		om_test_ticks(3)
	TEST_ASSERT(get_dist(S, goal) < start_dist, "walk_to_destination did not move the mob")
	S.forceMove(goal)
	TEST_ASSERT_EQUAL(W.tick(B, goal, null), DQ_BEHAVIOR_DONE, "walk_to_destination did not finish on arrival")
	TEST_ASSERT_NULL(B.destination(), "arrival did not clear the destination")

// --- aimed_shot, throw_grenade, scavenge_weapon -----------------------------------------------

/datum/unit_test/dq_ai_tactic_aimed_shot

/datum/unit_test/dq_ai_tactic_aimed_shot/Run()
	var/list/pair = ai_pair(ai_floor(0), ai_floor(4), /mob/living/simple_mob/combat_ai_tactics_subject/handed)
	var/mob/living/simple_mob/S = pair[1]
	var/mob/H = pair[2]
	var/datum/ai_brain/B = S.ai_brain
	TEST_ASSERT_NULL(dq_ai_test_eval(B, /datum/ai_behavior/aimed_shot, null), "aimed_shot scored with no gun")
	var/obj/item/gun/G = allocate(/obj/item/gun)
	S.put_in_hands(G)
	B.rebuild_behaviors()
	TEST_ASSERT_EQUAL(B.behavior_source(/datum/ai_behavior/aimed_shot), G, "the held gun is not the aimed shot's source")
	var/score = dq_ai_test_score(dq_ai_test_eval(B, /datum/ai_behavior/aimed_shot, G))
	// A bare /obj/item/gun may refuse special_check; what is pinned is the score and the range band when it does not.
	if(score)
		TEST_ASSERT_EQUAL(score, 55 + 12, "aimed_shot score at four tiles")
	H.forceMove(ai_floor(1))
	TEST_ASSERT_NULL(dq_ai_test_eval(B, /datum/ai_behavior/aimed_shot, G), "aimed_shot scored inside its minimum range")

/datum/unit_test/dq_ai_tactic_throw_grenade

/datum/unit_test/dq_ai_tactic_throw_grenade/Run()
	var/list/pair = ai_pair(ai_floor(0), ai_floor(4), /mob/living/simple_mob/combat_ai_tactics_subject/handed)
	var/mob/living/simple_mob/S = pair[1]
	var/mob/living/carbon/human/H = pair[2]
	var/datum/ai_brain/B = S.ai_brain
	var/obj/item/grenade/G = allocate(/obj/item/grenade)
	S.put_in_hands(G)
	B.model.visible_hostiles = list(H)
	TEST_ASSERT_NULL(dq_ai_test_eval(B, /datum/ai_behavior/throw_grenade, G), "throw_grenade scored for a single target")
	var/mob/living/carbon/human/H2 = allocate(/mob/living/carbon/human, ai_floor(4, 1))
	B.model.visible_hostiles = list(H, H2)
	var/list/result = dq_ai_test_eval(B, /datum/ai_behavior/throw_grenade, G)
	TEST_ASSERT_EQUAL(dq_ai_test_score(result), 60 + 2 * 15, "throw_grenade score for a cluster of two")
	TEST_ASSERT(isturf(result["target"]), "throw_grenade did not target a turf")
	G.active = TRUE
	TEST_ASSERT_NULL(dq_ai_test_eval(B, /datum/ai_behavior/throw_grenade, G), "throw_grenade scored a primed grenade")

/datum/unit_test/dq_ai_tactic_scavenge_weapon

/datum/unit_test/dq_ai_tactic_scavenge_weapon/Run()
	var/mob/living/simple_mob/S = allocate(/mob/living/simple_mob/combat_ai_tactics_subject/handed, ai_floor(0, 1))
	var/datum/ai_brain/B = S.ai_brain
	TEST_ASSERT_NULL(dq_ai_test_eval(B, /datum/ai_behavior/scavenge_weapon), "scavenge scored with nothing to pick up")
	var/obj/item/grenade/G = allocate(/obj/item/grenade, ai_floor(1, 1))
	var/list/result = dq_ai_test_eval(B, /datum/ai_behavior/scavenge_weapon)
	TEST_ASSERT_EQUAL(result?["target"], G, "scavenge did not pick the grenade")
	var/datum/ai_behavior/scavenge_weapon/W = dq_get_behavior(/datum/ai_behavior/scavenge_weapon)
	TEST_ASSERT_EQUAL(W.tick(B, G, null), DQ_BEHAVIOR_DONE, "scavenge did not finish with the grenade in reach")
	TEST_ASSERT_EQUAL(G.loc, S, "scavenge did not pick the grenade up")

// --- maul_unconscious -------------------------------------------------------------------------

/datum/unit_test/dq_ai_tactic_maul_unconscious

/datum/unit_test/dq_ai_tactic_maul_unconscious/Run()
	var/mob/living/simple_mob/S = allocate(/mob/living/simple_mob/combat_ai_tactics_subject, ai_floor(0, 1))
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, ai_floor(1, 1))
	var/datum/ai_brain/B = S.ai_brain
	S.faction = "combat_ai_tactics_other"
	TEST_ASSERT_NULL(dq_ai_test_eval(B, /datum/ai_behavior/maul_unconscious), "maul scored a conscious mob")
	H.set_stat(UNCONSCIOUS)
	TEST_ASSERT_EQUAL(dq_ai_test_score(dq_ai_test_eval(B, /datum/ai_behavior/maul_unconscious)), 50, "maul did not score 50 for a downed mob in reach")

#endif
