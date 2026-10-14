// Behaviour pins for the timed actions under code/game/objects/items, recorded on the legacy forms (task_timed) before they become ops
// with wait(). The helpers are those of dq_timed_pin_behaviour.dm.

// ---- Desk bell: a wrench takes it apart after half a second ----

/datum/unit_test/dq_timed_pin_w1
	abstract_type = /datum/unit_test/dq_timed_pin_w1
	parent_type = /datum/unit_test/dq_timed_pin

/datum/unit_test/dq_timed_pin_w1/deskbell_wrench

/datum/unit_test/dq_timed_pin_w1/deskbell_wrench/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/item/deskbell/B = allocate(/obj/item/deskbell, run_loc_floor_bottom_left)
	var/obj/item/tool/wrench/W = allocate(/obj/item/tool/wrench, run_loc_floor_bottom_left)
	user.put_in_active_hand(W)
	test_chat_clear()
	test_click(user, B, W)
	TEST_ASSERT(!isnull(running(user)), "the wrench starts a timed action")
	test_time(3)
	TEST_ASSERT(!QDELETED(B), "the bell stands before the end")
	test_time(4)
	TEST_ASSERT(QDELETED(B), "the bell is taken apart at the end")
	TEST_ASSERT(said(user, "You disassemble the desk bell"), "it says it finished")
	for(var/obj/item/stack/material/steel/left in user.loc)
		qdel(left)

/datum/unit_test/dq_timed_pin_w1/deskbell_wrench_cancel_on_move

/datum/unit_test/dq_timed_pin_w1/deskbell_wrench_cancel_on_move/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/item/deskbell/B = allocate(/obj/item/deskbell, run_loc_floor_bottom_left)
	var/obj/item/tool/wrench/W = allocate(/obj/item/tool/wrench, run_loc_floor_bottom_left)
	user.put_in_active_hand(W)
	test_click(user, B, W)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "the wrench starts a timed action")
	user.forceMove(get_step(user, EAST))
	test_time(2 SECONDS)
	TEST_ASSERT(!QDELETED(B), "moving cancels: the bell stands")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

/datum/unit_test/dq_timed_pin_w1/deskbell_wrench_cancel_on_drop

/datum/unit_test/dq_timed_pin_w1/deskbell_wrench_cancel_on_drop/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/item/deskbell/B = allocate(/obj/item/deskbell, run_loc_floor_bottom_left)
	var/obj/item/tool/wrench/W = allocate(/obj/item/tool/wrench, run_loc_floor_bottom_left)
	user.put_in_active_hand(W)
	test_click(user, B, W)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "the wrench starts a timed action")
	user.drop_from_inventory(W)
	test_time(2 SECONDS)
	TEST_ASSERT(!QDELETED(B), "dropping the wrench cancels: the bell stands")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

// ---- UAV: a screwdriver takes the cell out after three seconds ----

/datum/unit_test/dq_timed_pin_w1/uav_cell_out

/datum/unit_test/dq_timed_pin_w1/uav_cell_out/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/item/uav/loaded/U = allocate(/obj/item/uav/loaded, run_loc_floor_bottom_left)
	var/obj/item/tool/screwdriver/S = allocate(/obj/item/tool/screwdriver, run_loc_floor_bottom_left)
	user.put_in_active_hand(S)
	var/obj/item/cell/C = U.cell
	TEST_ASSERT(!isnull(C), "the loaded drone has a cell")
	test_chat_clear()
	test_click(user, U, S)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "the screwdriver starts a timed action")
	test_time(2 SECONDS)
	TEST_ASSERT(U.cell == C, "the cell is in before the end")
	test_time(2 SECONDS)
	TEST_ASSERT(isnull(U.cell), "the cell is out at the end")
	TEST_ASSERT_EQUAL(C.loc, get_turf(U), "and on the floor")
	TEST_ASSERT(said(user, "You remove"), "it says it finished")
	qdel(C)

/datum/unit_test/dq_timed_pin_w1/uav_cell_out_cancel_on_move

/datum/unit_test/dq_timed_pin_w1/uav_cell_out_cancel_on_move/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/item/uav/loaded/U = allocate(/obj/item/uav/loaded, run_loc_floor_bottom_left)
	var/obj/item/tool/screwdriver/S = allocate(/obj/item/tool/screwdriver, run_loc_floor_bottom_left)
	user.put_in_active_hand(S)
	var/obj/item/cell/C = U.cell
	test_click(user, U, S)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "the screwdriver starts a timed action")
	user.forceMove(get_step(user, EAST))
	test_time(5 SECONDS)
	TEST_ASSERT(U.cell == C, "moving cancels: the cell stays")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

/datum/unit_test/dq_timed_pin_w1/uav_cell_out_cancel_on_target_loss

/datum/unit_test/dq_timed_pin_w1/uav_cell_out_cancel_on_target_loss/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/item/uav/loaded/U = allocate(/obj/item/uav/loaded, run_loc_floor_bottom_left)
	var/obj/item/tool/screwdriver/S = allocate(/obj/item/tool/screwdriver, run_loc_floor_bottom_left)
	user.put_in_active_hand(S)
	test_click(user, U, S)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "the screwdriver starts a timed action")
	qdel(U)
	test_time(5 SECONDS)
	TEST_ASSERT(was_cancelled(T, user), "deleting the drone ends the action cancelled")

// ---- Grave marker: placed after a second where the user stands ----

/datum/unit_test/dq_timed_pin_w1/gravemarker_place

/datum/unit_test/dq_timed_pin_w1/gravemarker_place/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/item/material/gravemarker/G = allocate(/obj/item/material/gravemarker, run_loc_floor_bottom_left)
	user.put_in_active_hand(G)
	test_chat_clear()
	test_click(user, G, G)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "using it in hand starts a timed action")
	TEST_ASSERT(said(user, "You begin to place"), "it says it began")
	test_time(8)
	TEST_ASSERT(!(locate(/obj/structure/gravemarker) in user.loc), "nothing is placed before the end")
	test_time(4)
	TEST_ASSERT(!isnull(locate(/obj/structure/gravemarker) in user.loc), "the marker stands where the user is at the end")
	TEST_ASSERT(QDELETED(G), "and the item is used up")
	TEST_ASSERT(said(user, "You place"), "it says it finished")
	qdel(locate(/obj/structure/gravemarker) in user.loc)

/datum/unit_test/dq_timed_pin_w1/gravemarker_place_cancel_on_move

/datum/unit_test/dq_timed_pin_w1/gravemarker_place_cancel_on_move/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/item/material/gravemarker/G = allocate(/obj/item/material/gravemarker, run_loc_floor_bottom_left)
	user.put_in_active_hand(G)
	test_click(user, G, G)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "using it in hand starts a timed action")
	user.forceMove(get_step(user, EAST))
	test_time(3 SECONDS)
	TEST_ASSERT(!QDELETED(G), "moving cancels: the item is kept")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

/datum/unit_test/dq_timed_pin_w1/gravemarker_place_refused_where_one_stands

/datum/unit_test/dq_timed_pin_w1/gravemarker_place_refused_where_one_stands/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/item/material/gravemarker/G = allocate(/obj/item/material/gravemarker, run_loc_floor_bottom_left)
	allocate(/obj/structure/gravemarker, user.loc)
	user.put_in_active_hand(G)
	test_chat_clear()
	test_click(user, G, G)
	TEST_ASSERT_NULL(running(user), "a second marker on the same tile starts nothing")
	TEST_ASSERT(said(user, "There's already something there"), "it says so")
	test_time(3 SECONDS)
	TEST_ASSERT(!QDELETED(G), "and the item is kept")

// ---- Marker beacon: picked up by hand, or into a stack, after a wait ----

/datum/unit_test/dq_timed_pin_w1/marker_beacon_pick_up

/datum/unit_test/dq_timed_pin_w1/marker_beacon_pick_up/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/structure/marker_beacon/B = allocate(/obj/structure/marker_beacon, run_loc_floor_bottom_left)
	test_chat_clear()
	test_click(user, B, null)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "a bare hand starts a timed action")
	TEST_ASSERT(isnull(declared_duration(T)) || declared_duration(T) == 15, "it lasts a second and a half")
	TEST_ASSERT(said(user, "You start picking"), "it says it began")
	test_time(1 SECONDS)
	TEST_ASSERT(!QDELETED(B), "the beacon stands before the end")
	test_time(1 SECONDS)
	TEST_ASSERT(QDELETED(B), "the beacon is picked up at the end")
	var/found = FALSE
	for(var/obj/item/stack/marker_beacon/M in user.get_all_held_items())
		found = TRUE
	TEST_ASSERT(found, "a beacon stack is in the hand")

/datum/unit_test/dq_timed_pin_w1/marker_beacon_pick_up_cancel_on_move

/datum/unit_test/dq_timed_pin_w1/marker_beacon_pick_up_cancel_on_move/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/structure/marker_beacon/B = allocate(/obj/structure/marker_beacon, run_loc_floor_bottom_left)
	test_click(user, B, null)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "a bare hand starts a timed action")
	user.forceMove(get_step(user, EAST))
	test_time(3 SECONDS)
	TEST_ASSERT(!QDELETED(B), "moving cancels: the beacon stands")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

/datum/unit_test/dq_timed_pin_w1/marker_beacon_permanent_stays

/datum/unit_test/dq_timed_pin_w1/marker_beacon_permanent_stays/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/structure/marker_beacon/B = allocate(/obj/structure/marker_beacon, run_loc_floor_bottom_left)
	B.perma = TRUE
	test_click(user, B, null)
	TEST_ASSERT_NULL(running(user), "a permanent beacon starts nothing")
	test_time(3 SECONDS)
	TEST_ASSERT(!QDELETED(B), "and stays")

/datum/unit_test/dq_timed_pin_w1/marker_beacon_into_stack

/datum/unit_test/dq_timed_pin_w1/marker_beacon_into_stack/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/structure/marker_beacon/B = allocate(/obj/structure/marker_beacon, run_loc_floor_bottom_left)
	var/obj/item/stack/marker_beacon/S = allocate(/obj/item/stack/marker_beacon, run_loc_floor_bottom_left, 5)
	user.put_in_active_hand(S)
	test_chat_clear()
	test_click(user, B, S)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "a stack against a beacon starts a timed action")
	TEST_ASSERT(said(user, "You start picking"), "it says it began")
	test_time(1 SECONDS)
	TEST_ASSERT(!QDELETED(B) && S.get_amount() == 5, "nothing happens before the end")
	test_time(1 SECONDS)
	TEST_ASSERT(QDELETED(B), "the beacon is taken at the end")
	TEST_ASSERT_EQUAL(S.get_amount(), 6, "into the stack")

/datum/unit_test/dq_timed_pin_w1/marker_beacon_into_stack_cancel_on_drop

/datum/unit_test/dq_timed_pin_w1/marker_beacon_into_stack_cancel_on_drop/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/structure/marker_beacon/B = allocate(/obj/structure/marker_beacon, run_loc_floor_bottom_left)
	var/obj/item/stack/marker_beacon/S = allocate(/obj/item/stack/marker_beacon, run_loc_floor_bottom_left, 5)
	user.put_in_active_hand(S)
	test_click(user, B, S)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "a stack against a beacon starts a timed action")
	user.drop_from_inventory(S)
	test_time(3 SECONDS)
	TEST_ASSERT(!QDELETED(B) && S.get_amount() == 5, "dropping the stack cancels: nothing happens")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

// ---- Personal emergency beacon: activated after a yes and three seconds ----

/datum/unit_test/dq_timed_pin_w1/e_beacon_activate

/datum/unit_test/dq_timed_pin_w1/e_beacon_activate/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/item/emergency_beacon/B = allocate(/obj/item/emergency_beacon, run_loc_floor_bottom_left)
	user.put_in_active_hand(B)
	test_chat_clear()
	test_click(user, B, B)
	test_answer(user, TRUE)
	TEST_ASSERT(!isnull(running(user)), "a yes starts a timed action")
	test_time(2 SECONDS)
	TEST_ASSERT(!B.beacon_active, "not active before the end")
	test_time(2 SECONDS)
	TEST_ASSERT(B.beacon_active, "active at the end")
	TEST_ASSERT(B.anchored, "and spiked in")
	TEST_ASSERT(said(user, "You activate"), "it says it finished")

/datum/unit_test/dq_timed_pin_w1/e_beacon_activate_cancel_on_move

/datum/unit_test/dq_timed_pin_w1/e_beacon_activate_cancel_on_move/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/item/emergency_beacon/B = allocate(/obj/item/emergency_beacon, run_loc_floor_bottom_left)
	user.put_in_active_hand(B)
	test_click(user, B, B)
	test_answer(user, TRUE)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "a yes starts a timed action")
	user.forceMove(get_step(user, EAST))
	test_time(5 SECONDS)
	TEST_ASSERT(!B.beacon_active, "moving cancels: not active")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

/datum/unit_test/dq_timed_pin_w1/e_beacon_activate_no

/datum/unit_test/dq_timed_pin_w1/e_beacon_activate_no/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/item/emergency_beacon/B = allocate(/obj/item/emergency_beacon, run_loc_floor_bottom_left)
	user.put_in_active_hand(B)
	test_click(user, B, B)
	test_answer(user, FALSE)
	TEST_ASSERT_NULL(running(user), "a no starts nothing")
	test_time(5 SECONDS)
	TEST_ASSERT(!B.beacon_active, "and nothing is activated")
