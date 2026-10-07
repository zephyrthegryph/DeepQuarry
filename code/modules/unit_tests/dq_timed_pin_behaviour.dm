// Behaviour pins for timed actions (task_timed / task_start), recorded on the legacy forms before they become ops with wait().
// Each pin drives the real click path and records: the duration, the start message, what a move or a dropped item does,
// what completion does and says. A conversion keeps every assertion; a difference is a documented class in
// doc/rewrite/intended_changes.md (the start message, for one: an op's wait() says nothing when it starts).

/datum/unit_test/dq_timed_pin
	abstract_type = /datum/unit_test/dq_timed_pin

/datum/unit_test/dq_timed_pin/Run()
	test_driver_begin()
	run_pin()
	for(var/obj/effect/decal/cleanable/dirt/D in range(3, run_loc_floor_bottom_left))
		qdel(D) // footprints of a test that walked away
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

/// The one running timed action of `user` (a legacy timed task, or the pending op that replaced it), or null.
/datum/unit_test/dq_timed_pin/proc/running(mob/user)
	var/list/L = timed_tasks_of(user)
	if(length(L))
		return L[1]
	return op_pending_of(user)

/// How many timed actions `user` has running.
/datum/unit_test/dq_timed_pin/proc/running_count(mob/user)
	return length(timed_tasks_of(user)) + length(op_pendings_of(user))

/// The duration a legacy task declares, or null for a pending op (its duration is pinned by the time it ends at).
/datum/unit_test/dq_timed_pin/proc/declared_duration(datum/D)
	var/datum/task/timed/T = D
	return istype(T) ? T.duration : null

/// TRUE when the action ended without finishing: a cancelled task, or a pending op that is no longer pending.
/datum/unit_test/dq_timed_pin/proc/was_cancelled(datum/D, mob/user)
	var/datum/task/timed/T = D
	if(istype(T))
		return T.state == TASK_CANCELLED
	return isnull(op_pending_of(user))

// ---- A tool-less item used on an item: whetstone refined with five sheets ----

/datum/unit_test/dq_timed_pin/whetstone_refine

/datum/unit_test/dq_timed_pin/whetstone_refine/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/item/whetstone/W = allocate(/obj/item/whetstone, run_loc_floor_bottom_left)
	var/obj/item/stack/material/steel/S = allocate(/obj/item/stack/material/steel, run_loc_floor_bottom_left, 10)
	user.put_in_active_hand(S)
	test_chat_clear()
	test_click(user, W, S)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "the click starts a timed action")
	TEST_ASSERT(isnull(declared_duration(T)) || declared_duration(T) == 7 SECONDS, "it lasts seven seconds")
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
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "the click starts a timed action")
	test_time(2 SECONDS)
	user.forceMove(get_step(user, EAST))
	test_time(8 SECONDS)
	TEST_ASSERT(!QDELETED(W) && S.get_amount() == 10, "moving cancels: nothing is spent")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

/datum/unit_test/dq_timed_pin/whetstone_cancel_on_drop

/datum/unit_test/dq_timed_pin/whetstone_cancel_on_drop/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/item/whetstone/W = allocate(/obj/item/whetstone, run_loc_floor_bottom_left)
	var/obj/item/stack/material/steel/S = allocate(/obj/item/stack/material/steel, run_loc_floor_bottom_left, 10)
	user.put_in_active_hand(S)
	test_click(user, W, S)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "the click starts a timed action")
	user.drop_from_inventory(S)
	test_time(8 SECONDS)
	TEST_ASSERT(!QDELETED(W) && S.get_amount() == 10, "dropping the held item cancels: nothing is spent")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

/datum/unit_test/dq_timed_pin/whetstone_cancel_on_target_loss

/datum/unit_test/dq_timed_pin/whetstone_cancel_on_target_loss/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/item/whetstone/W = allocate(/obj/item/whetstone, run_loc_floor_bottom_left)
	var/obj/item/stack/material/steel/S = allocate(/obj/item/stack/material/steel, run_loc_floor_bottom_left, 10)
	user.put_in_active_hand(S)
	test_click(user, W, S)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "the click starts a timed action")
	qdel(W)
	test_time(8 SECONDS)
	TEST_ASSERT_EQUAL(S.get_amount(), 10, "deleting the target cancels: nothing is spent")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

/datum/unit_test/dq_timed_pin/whetstone_short_of_sheets

/datum/unit_test/dq_timed_pin/whetstone_short_of_sheets/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/item/whetstone/W = allocate(/obj/item/whetstone, run_loc_floor_bottom_left)
	var/obj/item/stack/material/steel/S = allocate(/obj/item/stack/material/steel, run_loc_floor_bottom_left, 3)
	user.put_in_active_hand(S)
	test_click(user, W, S)
	TEST_ASSERT_NULL(running(user), "too few sheets starts nothing")
	// Legacy: it said "You need 5 [whetstone] to refine it into a sharpening kit." A short stack is not a stack(5) binding, so the click now falls
	// through unanswered (doc/rewrite/intended_changes.md, "Timed actions as ops": a refusal that only the old handler wrote).
	test_time(8 SECONDS)
	TEST_ASSERT(!QDELETED(W) && S.get_amount() == 3, "and spends nothing")

// ---- An item in hand with a pre-check, a start message and a delayed effect: the bear trap ----

/datum/unit_test/dq_timed_pin/beartrap_deploy

/datum/unit_test/dq_timed_pin/beartrap_deploy/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/item/beartrap/B = allocate(/obj/item/beartrap, run_loc_floor_bottom_left)
	user.put_in_active_hand(B)
	test_chat_clear()
	test_click(user, B, B)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "using it in hand starts a timed action")
	TEST_ASSERT(isnull(declared_duration(T)) || declared_duration(T) == 6 SECONDS, "it lasts six seconds")
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
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "using it in hand starts a timed action")
	user.forceMove(get_step(user, EAST))
	test_time(8 SECONDS)
	TEST_ASSERT(!B.deployed, "moving cancels the deploy")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

/datum/unit_test/dq_timed_pin/beartrap_disarm

/datum/unit_test/dq_timed_pin/beartrap_disarm/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/item/beartrap/start_active/B = allocate(/obj/item/beartrap/start_active, run_loc_floor_bottom_left)
	test_click(user, B, null)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "a bare hand on a deployed trap starts a timed action")
	TEST_ASSERT(isnull(declared_duration(T)) || declared_duration(T) == 6 SECONDS, "it lasts six seconds")
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
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "a bare hand on a deployed trap starts a timed action")
	user.forceMove(get_step(user, EAST))
	test_time(8 SECONDS)
	TEST_ASSERT(B.deployed, "moving cancels: it stays deployed")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

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
	var/datum/first = running(user)
	TEST_ASSERT(!isnull(first), "the first click starts")
	test_click(user, B, null)
	TEST_ASSERT_EQUAL(running_count(user), 1, "a second click on the same target leaves one action running")
	if(istype(first, /datum/task))
		TEST_ASSERT_EQUAL(running(user), first, "the first is still the one running (the second click was refused)")

// ---- The shapes the codemod (tools/dx/codemods/timed_task.py) converts: an op handler that only starts the action ----

/datum/unit_test/dq_timed_pin/confetti_pick_up

/datum/unit_test/dq_timed_pin/confetti_pick_up/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/effect/decal/cleanable/confetti/C = allocate(/obj/effect/decal/cleanable/confetti, run_loc_floor_bottom_left)
	test_chat_clear()
	test_click(user, C, null)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "a bare hand on confetti starts a timed action")
	TEST_ASSERT(isnull(declared_duration(T)) || declared_duration(T) == 6 SECONDS, "it lasts six seconds")
	TEST_ASSERT(said(user, "You start to meticulously pick up the confetti"), "it says it began")
	test_time(5 SECONDS)
	TEST_ASSERT(!QDELETED(C), "the confetti is there before the end")
	test_time(2 SECONDS)
	TEST_ASSERT(QDELETED(C), "the confetti is gone at the end")

/datum/unit_test/dq_timed_pin/confetti_pick_up_cancel_on_move

/datum/unit_test/dq_timed_pin/confetti_pick_up_cancel_on_move/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/effect/decal/cleanable/confetti/C = allocate(/obj/effect/decal/cleanable/confetti, run_loc_floor_bottom_left)
	test_click(user, C, null)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "a bare hand on confetti starts a timed action")
	user.forceMove(get_step(user, EAST))
	test_time(8 SECONDS)
	TEST_ASSERT(!QDELETED(C), "moving cancels")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

/datum/unit_test/dq_timed_pin/snow_shovel

/datum/unit_test/dq_timed_pin/snow_shovel/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/effect/overlay/snow/S = allocate(/obj/effect/overlay/snow, run_loc_floor_bottom_left)
	var/obj/item/shovel/shovel = allocate(/obj/item/shovel, run_loc_floor_bottom_left)
	user.put_in_active_hand(shovel)
	test_chat_clear()
	test_click(user, S, shovel)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "a shovel on snow starts a timed action")
	TEST_ASSERT(isnull(declared_duration(T)) || declared_duration(T) == 4 SECONDS, "it lasts four seconds")
	test_time(3 SECONDS)
	TEST_ASSERT(!QDELETED(S), "the snow is there before the end")
	test_time(2 SECONDS)
	TEST_ASSERT(QDELETED(S), "the snow is gone at the end")
	TEST_ASSERT(said(user, "You have finished shoveling!"), "it says it finished")

/datum/unit_test/dq_timed_pin/snow_shovel_cancel_on_drop

/datum/unit_test/dq_timed_pin/snow_shovel_cancel_on_drop/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/effect/overlay/snow/S = allocate(/obj/effect/overlay/snow, run_loc_floor_bottom_left)
	var/obj/item/shovel/shovel = allocate(/obj/item/shovel, run_loc_floor_bottom_left)
	user.put_in_active_hand(shovel)
	test_click(user, S, shovel)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "a shovel on snow starts a timed action")
	user.drop_from_inventory(shovel)
	test_time(6 SECONDS)
	TEST_ASSERT(!QDELETED(S), "dropping the shovel cancels")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

/datum/unit_test/dq_timed_pin/catwalk_plate

/datum/unit_test/dq_timed_pin/catwalk_plate/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/structure/catwalk/C = allocate(/obj/structure/catwalk, run_loc_floor_bottom_left)
	var/obj/item/stack/tile/floor/tiles = allocate(/obj/item/stack/tile/floor, run_loc_floor_bottom_left, 5)
	user.put_in_active_hand(tiles)
	test_chat_clear()
	test_click(user, C, tiles)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "a floor tile on a catwalk starts a timed action")
	TEST_ASSERT(isnull(declared_duration(T)) || declared_duration(T) == 1 SECOND, "it lasts a second")
	TEST_ASSERT(said(user, "Placing tile..."), "it says it began")
	TEST_ASSERT_NULL(C.plated_tile, "nothing is plated before the end")
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(C.plated_tile, /obj/item/stack/tile/floor, "plated at the end")
	TEST_ASSERT_EQUAL(tiles.get_amount(), 4, "one tile is used")
	TEST_ASSERT(said(user, "You plate"), "it says it finished")

/datum/unit_test/dq_timed_pin/catwalk_plate_cancel_on_move

/datum/unit_test/dq_timed_pin/catwalk_plate_cancel_on_move/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/structure/catwalk/C = allocate(/obj/structure/catwalk, run_loc_floor_bottom_left)
	var/obj/item/stack/tile/floor/tiles = allocate(/obj/item/stack/tile/floor, run_loc_floor_bottom_left, 5)
	user.put_in_active_hand(tiles)
	test_click(user, C, tiles)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "a floor tile on a catwalk starts a timed action")
	user.forceMove(get_step(user, EAST))
	test_time(3 SECONDS)
	TEST_ASSERT_NULL(C.plated_tile, "moving cancels")
	TEST_ASSERT_EQUAL(tiles.get_amount(), 5, "and spends nothing")

/datum/unit_test/dq_timed_pin/tyr_elevator

/datum/unit_test/dq_timed_pin/tyr_elevator/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/structure/prop/tyr_elevator/E = allocate(/obj/structure/prop/tyr_elevator, run_loc_floor_bottom_left)
	var/turf/dest = get_step(run_loc_floor_bottom_left, NORTH)
	E.descendx = dest.x
	E.descendy = dest.y
	var/obj/item/pen/pen = allocate(/obj/item/pen, run_loc_floor_bottom_left)
	user.put_in_active_hand(pen)
	test_click(user, E, pen)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "an item on the elevator starts a timed action")
	TEST_ASSERT(isnull(declared_duration(T)) || declared_duration(T) == 3 SECONDS, "it lasts three seconds")
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(get_turf(user), run_loc_floor_bottom_left, "still here before the end")
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(get_turf(user), dest, "carried to the destination at the end")
	for(var/obj/effect/effect/sparks/S in range(3, dest))
		qdel(S) // the teleport's sparks

// ---- Barbed wire: deploy in hand, collect with a bare hand (the wait follows the coil's wear) ----

/datum/unit_test/dq_timed_pin/barbedwire_deploy

/datum/unit_test/dq_timed_pin/barbedwire_deploy/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/item/material/barbedwire/W = allocate(/obj/item/material/barbedwire, run_loc_floor_bottom_left)
	user.put_in_active_hand(W)
	test_chat_clear()
	test_click(user, W, W)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "using it in hand starts a timed action")
	TEST_ASSERT(isnull(declared_duration(T)) || declared_duration(T) == 6 SECONDS, "it lasts six seconds")
	TEST_ASSERT(said(user, "You begin deploying"), "it says it began")
	test_time(5 SECONDS)
	TEST_ASSERT(!W.anchored, "not deployed before the end")
	test_time(2 SECONDS)
	TEST_ASSERT(W.anchored, "deployed at the end")
	TEST_ASSERT(said(user, "You have deployed"), "it says it finished")
	TEST_ASSERT(!(W in user.get_all_held_items()), "and it left the hand")

/datum/unit_test/dq_timed_pin/barbedwire_deploy_cancel_on_move

/datum/unit_test/dq_timed_pin/barbedwire_deploy_cancel_on_move/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/item/material/barbedwire/W = allocate(/obj/item/material/barbedwire, run_loc_floor_bottom_left)
	user.put_in_active_hand(W)
	test_click(user, W, W)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "using it in hand starts a timed action")
	user.forceMove(get_step(user, EAST))
	test_time(8 SECONDS)
	TEST_ASSERT(!W.anchored, "moving cancels the deploy")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

/datum/unit_test/dq_timed_pin/barbedwire_collect

/datum/unit_test/dq_timed_pin/barbedwire_collect/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/item/material/barbedwire/W = allocate(/obj/item/material/barbedwire, run_loc_floor_bottom_left)
	W.set_anchored(TRUE)
	var/wait_time = W.get_integrity() / MATERIAL_WEAR_UNIT
	test_chat_clear()
	test_click(user, W, null)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "a bare hand on deployed wire starts a timed action")
	TEST_ASSERT(isnull(declared_duration(T)) || declared_duration(T) == wait_time, "it lasts as long as the coil's wear says")
	TEST_ASSERT(said(user, "You begin collecting"), "it says it began")
	test_time(wait_time - 10)
	TEST_ASSERT(W.anchored, "still deployed before the end")
	test_time(20)
	TEST_ASSERT(!W.anchored, "collected at the end")
	TEST_ASSERT(said(user, "You have collected"), "it says it finished")

/datum/unit_test/dq_timed_pin/barbedwire_collect_cancel_on_move

/datum/unit_test/dq_timed_pin/barbedwire_collect_cancel_on_move/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/item/material/barbedwire/W = allocate(/obj/item/material/barbedwire, run_loc_floor_bottom_left)
	W.set_anchored(TRUE)
	test_click(user, W, null)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "a bare hand on deployed wire starts a timed action")
	user.forceMove(get_step(user, EAST))
	test_time(30 SECONDS)
	TEST_ASSERT(W.anchored, "moving cancels: it stays deployed")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")
