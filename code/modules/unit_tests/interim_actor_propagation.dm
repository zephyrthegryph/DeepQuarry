/// UI actions must use their actor even when invoked outside a player's verb.
/datum/unit_test/interim_nuclear_auth_actor/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	var/obj/machinery/nuclearbomb/bomb = allocate(/obj/machinery/nuclearbomb, T)
	var/obj/item/disk/nuclear/disk = allocate(/obj/item/disk/nuclear, T)
	TEST_ASSERT(actor.put_in_active_hand(disk), "the explicit actor holds the disk")
	TEST_ASSERT(test_op_committed(op_ui_act(actor, bomb, "auth")), "the authentication action handles insertion")
	TEST_ASSERT_EQUAL(bomb.auth(), disk, "the action inserts the explicit actor's disk")
	TEST_ASSERT_EQUAL(disk.loc, bomb, "the disk moves into the bomb")
	TEST_ASSERT_NULL(actor.get_active_hand(), "insertion releases the actor's hand")
	bomb.yes_code = TRUE
	TEST_ASSERT(test_op_committed(op_ui_act(actor, bomb, "auth")), "the authentication action handles ejection")
	TEST_ASSERT_NULL(bomb.auth(), "ejection clears the authentication reference")
	TEST_ASSERT_EQUAL(disk.loc, T, "ejection returns the disk to the floor")
	TEST_ASSERT(!bomb.yes_code, "ejection invalidates the entered code")

/// Tool checks read the explicit actor's held item and actually change the wire.
/datum/unit_test/interim_nuclear_wire_actor/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	var/obj/machinery/nuclearbomb/bomb = allocate(/obj/machinery/nuclearbomb, T)
	var/obj/item/tool/wirecutters/cutters = allocate(/obj/item/tool/wirecutters, T)
	TEST_ASSERT(actor.put_in_active_hand(cutters), "the explicit actor holds wirecutters")
	var/wire = bomb.light_wire
	TEST_ASSERT_EQUAL(LAZYACCESS(bomb.wires_list, wire), FALSE, "the selected wire starts intact")
	TEST_ASSERT(test_op_committed(op_ui_act(actor, bomb, "wire", list("wire" = wire))), "the wire action handles the cut")
	TEST_ASSERT_EQUAL(LAZYACCESS(bomb.wires_list, wire), TRUE, "the explicit actor's cutters cut the selected wire")
	TEST_ASSERT(test_op_committed(op_ui_act(actor, bomb, "wire", list("wire" = wire))), "the wire action handles mending")
	TEST_ASSERT_EQUAL(LAZYACCESS(bomb.wires_list, wire), FALSE, "the second action mends the selected wire")

/// Pen insertion and removal both operate on the UI action's actor.
/datum/unit_test/interim_clipboard_pen_actor/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	var/obj/item/clipboard/board = allocate(/obj/item/clipboard, T)
	actor.put_in_inactive_hand(board) // the window works in the hand that holds it
	actor.put_in_inactive_hand(board) // the window works in the hand that holds it
	var/obj/item/pen/pen = allocate(/obj/item/pen, T)
	TEST_ASSERT(actor.put_in_active_hand(pen), "the explicit actor holds the pen")
	TEST_ASSERT(test_op_committed(op_ui_act(actor, board, "add_pen")), "the insertion action is handled")
	TEST_ASSERT_EQUAL(board.haspen(), pen, "the clipboard records the actor's pen")
	TEST_ASSERT_EQUAL(pen.loc, board, "insertion moves the pen into the clipboard")
	TEST_ASSERT_NULL(actor.get_active_hand(), "insertion releases the actor's hand")
	TEST_ASSERT(test_op_committed(op_ui_act(actor, board, "remove_pen")), "the removal action is handled")
	TEST_ASSERT_NULL(board.haspen(), "removal clears the stored pen reference")
	TEST_ASSERT_EQUAL(pen.loc, actor, "removal gives the pen to the explicit actor")
	TEST_ASSERT_EQUAL(actor.get_active_hand(), pen, "the removed pen occupies the actor's hand")

/// Retrieving from a safe checks and uses the explicit actor's position and hands.
/datum/unit_test/interim_safe_retrieve_actor/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/structure/safe/safe = allocate(/obj/structure/safe, T)
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	var/obj/item/pen/pen = allocate(/obj/item/pen, safe)
	safe.open = FALSE
	TEST_ASSERT(test_op_handler(safe, "ui_act_retrieve", actor, null, REF(pen)), "a closed-safe action is handled")
	TEST_ASSERT_EQUAL(pen.loc, safe, "a closed safe retains its item")
	safe.open = TRUE
	TEST_ASSERT(test_op_handler(safe, "ui_act_retrieve", actor, null, REF(pen)), "an open-safe action is handled")
	TEST_ASSERT_EQUAL(pen.loc, actor, "the open safe gives its item to the explicit actor")
	TEST_ASSERT_EQUAL(actor.get_active_hand(), pen, "the retrieved item occupies the actor's hand")

/// Both player routes admit living actors; an automated forced cycle needs none.
/datum/unit_test/interim_washing_machine_start_actor/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	var/mob/observer/dead/ghost = allocate(/mob/observer/dead, T)
	var/obj/machinery/washing_machine/washer = allocate(/obj/machinery/washing_machine, T)
	var/obj/item/clothing/gloves/white/gloves = allocate(/obj/item/clothing/gloves/white, T)
	TEST_ASSERT(actor.put_in_active_hand(gloves), "the actor holds the laundry")
	TEST_ASSERT(test_click(actor, washer, gloves), "loading the laundry is handled")
	TEST_ASSERT(gloves in washer.washing, "the washing machine records the laundry")
	TEST_ASSERT(test_click(actor, washer, null), "closing the loaded machine is handled")
	var/closed_state = washer.state
	test_click(ghost, washer, null, GESTURE_ALT)
	TEST_ASSERT_EQUAL(washer.state, closed_state, "a nonliving actor cannot start a cycle")
	test_click(actor, washer, null, GESTURE_ALT)
	TEST_ASSERT_NOTEQUAL(washer.state, closed_state, "the alternate interaction starts for its explicit living actor")
	washer.finish_wash(0.5)
	TEST_ASSERT_EQUAL(washer.state, closed_state, "finishing restores the closed loaded state")
	test_menu(actor, washer, "washing_machine_start_washing")
	TEST_ASSERT_NOTEQUAL(washer.state, closed_state, "the start-washing interaction also passes its actor")
	washer.finish_wash(0.5)
	washer.start(TRUE, 0.5)
	TEST_ASSERT_NOTEQUAL(washer.state, closed_state, "a forced automated cycle still works without a player actor")
