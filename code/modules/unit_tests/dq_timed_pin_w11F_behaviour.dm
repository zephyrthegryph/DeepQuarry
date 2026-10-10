// Behaviour pins for the timed actions of mob/living/carbon/human converted in round 3, group F (rewrite/timed3-F).
// The scenes are written from the task_start()/task_timed() form they replaced and run against the ops that did: the two hand games and the
// bloodsuck bite are started by the proc the prompt answers reach, as the real caller does. Parent /datum/unit_test/dq_timed_pin and its helpers
// (person, said, running, was_cancelled). Not pinned: the lleill, protean and shapeshifter abilities (the abilities start from a prompt answer that
// the test driver cannot answer), the modular limb verbs and the self repair system (they need a prosthetic and a damaged cyborg scene).

/datum/unit_test/dq_timed_pin_w11F
	abstract_type = /datum/unit_test/dq_timed_pin_w11F
	parent_type = /datum/unit_test/dq_timed_pin

/// Two people side by side.
/datum/unit_test/dq_timed_pin_w11F/proc/pair()
	var/mob/living/carbon/human/one = person()
	var/mob/living/carbon/human/two = person(get_step(run_loc_floor_bottom_left, EAST))
	return list(one, two)

// ---- Thumb wars: five seconds, then one of the two wins ----

/datum/unit_test/dq_timed_pin_w11F/thumbwars_resolves

/datum/unit_test/dq_timed_pin_w11F/thumbwars_resolves/run_pin()
	var/list/players = pair()
	var/mob/living/carbon/human/one = players[1]
	var/mob/living/carbon/human/two = players[2]
	test_chat_clear()
	one.hand_game_invite_answered(two, "Thumb Wars")
	TEST_ASSERT(!isnull(running(one)), "the war starts a timed action")
	test_time(4 SECONDS)
	TEST_ASSERT(!isnull(running(one)), "it is still going before five seconds")
	TEST_ASSERT(!said(one, "gruelling battle"), "nobody has won yet")
	test_time(2 SECONDS)
	TEST_ASSERT(said(one, "gruelling battle") || said(two, "gruelling battle"), "one of them subdues the other's thumb")

// ---- Thumb wars: walking away cancels it and the room is told ----

/datum/unit_test/dq_timed_pin_w11F/thumbwars_walk_away

/datum/unit_test/dq_timed_pin_w11F/thumbwars_walk_away/run_pin()
	var/list/players = pair()
	var/mob/living/carbon/human/one = players[1]
	var/mob/living/carbon/human/two = players[2]
	test_chat_clear()
	one.hand_game_invite_answered(two, "Thumb Wars")
	var/datum/T = running(one)
	TEST_ASSERT(!isnull(T), "the war starts a timed action")
	one.forceMove(get_step(one, SOUTH))
	test_time(6 SECONDS)
	TEST_ASSERT(was_cancelled(T, one), "moving ends the war")
	TEST_ASSERT(!said(one, "gruelling battle") && !said(two, "gruelling battle"), "no winner is told")
	TEST_ASSERT(said(two, "cancelled their thumb war"), "the players are told the war was cancelled")

// ---- Slap hands: one second ----

/datum/unit_test/dq_timed_pin_w11F/slaphands_resolves

/datum/unit_test/dq_timed_pin_w11F/slaphands_resolves/run_pin()
	var/list/players = pair()
	var/mob/living/carbon/human/one = players[1]
	var/mob/living/carbon/human/two = players[2]
	test_chat_clear()
	one.hand_game_second_choice(two, "Slap Hands", 5, 5)
	TEST_ASSERT(!isnull(running(one)), "the game starts a timed action")
	test_time(0.5 SECONDS)
	TEST_ASSERT(!said(one, "slap") && !said(two, "slap"), "nothing is decided before a second")
	test_time(1 SECONDS)
	TEST_ASSERT(said(one, "slap") || said(two, "slap"), "a hand is slapped at the end")

// ---- Bloodsuck: thirty seconds next to the target, then the bite ----

/datum/unit_test/dq_timed_pin_w11F/bloodsuck_bite

/datum/unit_test/dq_timed_pin_w11F/bloodsuck_bite/run_pin()
	var/list/players = pair()
	var/mob/living/carbon/human/biter = players[1]
	var/mob/living/carbon/human/prey = players[2]
	test_chat_clear()
	biter.bloodsuck_begin(prey, TRUE, FALSE)
	TEST_ASSERT(!isnull(running(biter)), "the bite starts a timed action")
	test_time(29 SECONDS)
	TEST_ASSERT(!said(prey, "plunges them down"), "nothing is bitten before thirty seconds")
	test_time(2 SECONDS)
	TEST_ASSERT(said(prey, "plunges them down") || said(biter, "plunges them down"), "the fangs go in at the end")
	for(var/turf/T in block(run_loc_floor_bottom_left, run_loc_floor_top_right)) // the bite bleeds
		own_turf_contents(T)

// ---- Bloodsuck: the prey stepping away cancels the bite ----

/datum/unit_test/dq_timed_pin_w11F/bloodsuck_prey_leaves

/datum/unit_test/dq_timed_pin_w11F/bloodsuck_prey_leaves/run_pin()
	var/list/players = pair()
	var/mob/living/carbon/human/biter = players[1]
	var/mob/living/carbon/human/prey = players[2]
	biter.bloodsuck_begin(prey, TRUE, FALSE)
	var/datum/T = running(biter)
	TEST_ASSERT(!isnull(T), "the bite starts a timed action")
	prey.forceMove(get_step(prey, EAST))
	test_time(31 SECONDS)
	TEST_ASSERT(was_cancelled(T, biter), "the prey leaving ends the bite")
	TEST_ASSERT(!said(prey, "plunges them down") && !said(biter, "plunges them down"), "nothing is bitten")
