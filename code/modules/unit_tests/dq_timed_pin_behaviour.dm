// Behaviour pins for timed actions (task_timed / task_start), recorded on the legacy forms before they become ops with wait().
// Each pin drives the real click path and records: the duration, the start message, what a move or a dropped item does,
// what completion does and says. A conversion keeps every assertion; a difference is a documented class in
// doc/rewrite/intended_changes.md (the start message, for one: an op's wait() says nothing when it starts).

/datum/unit_test/dq_timed_pin
	abstract_type = /datum/unit_test/dq_timed_pin

/datum/unit_test/dq_timed_pin/Run()
	test_driver_begin()
	run_pin()
	test_driver_end()

/datum/unit_test/dq_timed_pin/proc/run_pin()
	return

/datum/unit_test/dq_timed_pin/proc/person(turf/T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T || run_loc_floor_bottom_left)
	H.enable_godmode()
	return H

/// TRUE when any line `user` was sent contains `needle`.
/datum/unit_test/dq_timed_pin/proc/said(mob/user, needle)
	for(var/line in test_chat_of(user))
		if(findtext(line, needle))
			return TRUE
	return FALSE

/// The one running timed task of `user`, or null.
/datum/unit_test/dq_timed_pin/proc/running(mob/user)
	var/list/L = timed_tasks_of(user)
	return length(L) ? L[1] : null

// ---- A tool-less item used on an item: whetstone refined with five sheets ----

/datum/unit_test/dq_timed_pin/whetstone_refine

/datum/unit_test/dq_timed_pin/whetstone_refine/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/item/whetstone/W = allocate(/obj/item/whetstone, run_loc_floor_bottom_left)
	var/obj/item/stack/material/steel/S = allocate(/obj/item/stack/material/steel, run_loc_floor_bottom_left, 10)
	user.put_in_active_hand(S)
	test_chat_clear()
	test_click(user, W, S)
	var/datum/task/timed/T = running(user)
	TEST_ASSERT(istype(T), "the click starts a timed action")
	TEST_ASSERT_EQUAL(T.duration, 7 SECONDS, "it lasts seven seconds")
	TEST_ASSERT(said(user, "You begin to refine"), "it says it began")
	test_time(6 SECONDS)
	TEST_ASSERT(!QDELETED(W) && S.get_amount() == 10, "nothing is spent before the end")
	test_time(2 SECONDS)
	TEST_ASSERT(QDELETED(W), "the whetstone is consumed at the end")
	TEST_ASSERT_EQUAL(S.get_amount(), 5, "five sheets are used")
	TEST_ASSERT(said(user, "You sharpen and refine"), "it says it finished")
	var/found = FALSE
	for(var/obj/item/material/sharpeningkit/K in user.get_all_held_items() + view(0, user))
		found = TRUE
	TEST_ASSERT(found, "a sharpening kit is made")

/datum/unit_test/dq_timed_pin/whetstone_cancel_on_move

/datum/unit_test/dq_timed_pin/whetstone_cancel_on_move/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/item/whetstone/W = allocate(/obj/item/whetstone, run_loc_floor_bottom_left)
	var/obj/item/stack/material/steel/S = allocate(/obj/item/stack/material/steel, run_loc_floor_bottom_left, 10)
	user.put_in_active_hand(S)
	test_click(user, W, S)
	var/datum/task/timed/T = running(user)
	TEST_ASSERT(istype(T), "the click starts a timed action")
	test_time(2 SECONDS)
	user.forceMove(get_step(user, EAST))
	test_time(8 SECONDS)
	TEST_ASSERT(!QDELETED(W) && S.get_amount() == 10, "moving cancels: nothing is spent")
	TEST_ASSERT_EQUAL(T.state, TASK_CANCELLED, "the action ends cancelled")

/datum/unit_test/dq_timed_pin/whetstone_cancel_on_drop

/datum/unit_test/dq_timed_pin/whetstone_cancel_on_drop/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/item/whetstone/W = allocate(/obj/item/whetstone, run_loc_floor_bottom_left)
	var/obj/item/stack/material/steel/S = allocate(/obj/item/stack/material/steel, run_loc_floor_bottom_left, 10)
	user.put_in_active_hand(S)
	test_click(user, W, S)
	var/datum/task/timed/T = running(user)
	TEST_ASSERT(istype(T), "the click starts a timed action")
	user.drop_from_inventory(S)
	test_time(8 SECONDS)
	TEST_ASSERT(!QDELETED(W) && S.get_amount() == 10, "dropping the held item cancels: nothing is spent")
	TEST_ASSERT_EQUAL(T.state, TASK_CANCELLED, "the action ends cancelled")

/datum/unit_test/dq_timed_pin/whetstone_cancel_on_target_loss

/datum/unit_test/dq_timed_pin/whetstone_cancel_on_target_loss/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/item/whetstone/W = allocate(/obj/item/whetstone, run_loc_floor_bottom_left)
	var/obj/item/stack/material/steel/S = allocate(/obj/item/stack/material/steel, run_loc_floor_bottom_left, 10)
	user.put_in_active_hand(S)
	test_click(user, W, S)
	var/datum/task/timed/T = running(user)
	TEST_ASSERT(istype(T), "the click starts a timed action")
	qdel(W)
	test_time(8 SECONDS)
	TEST_ASSERT_EQUAL(S.get_amount(), 10, "deleting the target cancels: nothing is spent")
	TEST_ASSERT_EQUAL(T.state, TASK_CANCELLED, "the action ends cancelled")

/datum/unit_test/dq_timed_pin/whetstone_short_of_sheets

/datum/unit_test/dq_timed_pin/whetstone_short_of_sheets/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/item/whetstone/W = allocate(/obj/item/whetstone, run_loc_floor_bottom_left)
	var/obj/item/stack/material/steel/S = allocate(/obj/item/stack/material/steel, run_loc_floor_bottom_left, 3)
	user.put_in_active_hand(S)
	test_click(user, W, S)
	TEST_ASSERT_NULL(running(user), "too few sheets starts nothing")
	TEST_ASSERT(said(user, "You need 5"), "and says so")

// ---- An item in hand with a pre-check, a start message and a delayed effect: the bear trap ----

/datum/unit_test/dq_timed_pin/beartrap_deploy

/datum/unit_test/dq_timed_pin/beartrap_deploy/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/item/beartrap/B = allocate(/obj/item/beartrap, run_loc_floor_bottom_left)
	user.put_in_active_hand(B)
	test_chat_clear()
	test_click(user, B, B)
	var/datum/task/timed/T = running(user)
	TEST_ASSERT(istype(T), "using it in hand starts a timed action")
	TEST_ASSERT_EQUAL(T.duration, 6 SECONDS, "it lasts six seconds")
	TEST_ASSERT(said(user, "You begin deploying"), "it says it began")
	test_time(5 SECONDS)
	TEST_ASSERT(!B.deployed, "not deployed before the end")
	test_time(2 SECONDS)
	TEST_ASSERT(B.deployed, "deployed at the end")
	TEST_ASSERT(B.anchored, "and anchored")
	TEST_ASSERT(said(user, "You have deployed"), "it says it finished")
	TEST_ASSERT(!(B in user.get_all_held_items()), "and it left the hand")

/datum/unit_test/dq_timed_pin/beartrap_deploy_cancel_on_move

/datum/unit_test/dq_timed_pin/beartrap_deploy_cancel_on_move/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/item/beartrap/B = allocate(/obj/item/beartrap, run_loc_floor_bottom_left)
	user.put_in_active_hand(B)
	test_click(user, B, B)
	var/datum/task/timed/T = running(user)
	TEST_ASSERT(istype(T), "using it in hand starts a timed action")
	user.forceMove(get_step(user, EAST))
	test_time(8 SECONDS)
	TEST_ASSERT(!B.deployed, "moving cancels the deploy")
	TEST_ASSERT_EQUAL(T.state, TASK_CANCELLED, "the action ends cancelled")

/datum/unit_test/dq_timed_pin/beartrap_disarm

/datum/unit_test/dq_timed_pin/beartrap_disarm/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/item/beartrap/start_active/B = allocate(/obj/item/beartrap/start_active, run_loc_floor_bottom_left)
	test_click(user, B, null)
	var/datum/task/timed/T = running(user)
	TEST_ASSERT(istype(T), "a bare hand on a deployed trap starts a timed action")
	TEST_ASSERT_EQUAL(T.duration, 6 SECONDS, "it lasts six seconds")
	TEST_ASSERT(said(user, "You begin disarming"), "it says it began")
	test_time(5 SECONDS)
	TEST_ASSERT(B.deployed, "still deployed before the end")
	test_time(2 SECONDS)
	TEST_ASSERT(!B.deployed, "disarmed at the end")
	TEST_ASSERT(said(user, "You have disarmed"), "it says it finished")

/datum/unit_test/dq_timed_pin/beartrap_disarm_cancel_on_move

/datum/unit_test/dq_timed_pin/beartrap_disarm_cancel_on_move/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/item/beartrap/start_active/B = allocate(/obj/item/beartrap/start_active, run_loc_floor_bottom_left)
	test_click(user, B, null)
	var/datum/task/timed/T = running(user)
	TEST_ASSERT(istype(T), "a bare hand on a deployed trap starts a timed action")
	user.forceMove(get_step(user, EAST))
	test_time(8 SECONDS)
	TEST_ASSERT(B.deployed, "moving cancels: it stays deployed")
	TEST_ASSERT_EQUAL(T.state, TASK_CANCELLED, "the action ends cancelled")

/// Two people may work on the same trap: the legacy action has no claim on its target.
/datum/unit_test/dq_timed_pin/beartrap_two_workers

/datum/unit_test/dq_timed_pin/beartrap_two_workers/run_pin()
	var/mob/living/carbon/human/one = person()
	var/mob/living/carbon/human/two = person()
	var/obj/item/beartrap/start_active/B = allocate(/obj/item/beartrap/start_active, run_loc_floor_bottom_left)
	test_click(one, B, null)
	test_click(two, B, null)
	TEST_ASSERT(!isnull(running(one)), "the first worker is running")
	TEST_ASSERT(!isnull(running(two)), "the second worker is running too (no claim)")
	test_time(8 SECONDS)
	TEST_ASSERT(!B.deployed, "the trap is disarmed")

// ---- The same actor starting twice ----

/datum/unit_test/dq_timed_pin/same_actor_twice

/datum/unit_test/dq_timed_pin/same_actor_twice/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/item/beartrap/start_active/B = allocate(/obj/item/beartrap/start_active, run_loc_floor_bottom_left)
	test_click(user, B, null)
	var/datum/task/timed/first = running(user)
	TEST_ASSERT(istype(first), "the first click starts")
	test_click(user, B, null)
	TEST_ASSERT_EQUAL(length(timed_tasks_of(user)), 1, "a second click on the same target starts nothing more")
	TEST_ASSERT_EQUAL(running(user), first, "the first is still the one running")
