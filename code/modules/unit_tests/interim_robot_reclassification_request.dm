/// Real held-item input and native request answers; no client UI-delivery claim.
/datum/unit_test/interim_robot_reclassification_request

/datum/unit_test/interim_robot_reclassification_request/Run()
	test_driver_begin()
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	actor.enable_godmode()
	var/obj/item/borg/upgrade/utility/rename/board = allocate(/obj/item/borg/upgrade/utility/rename, run_loc_floor_bottom_left)
	TEST_ASSERT(actor.put_in_active_hand(board), "the real board enters the actor's hand")
	TEST_ASSERT_EQUAL(actor.get_active_hand(), board, "the board is actually active-held")
	var/original_name = board.heldname
	actor.next_click = 0
	test_click(actor, board, board)
	test_drain()
	var/datum/request/request = SSrequests.open_for(actor)
	TEST_ASSERT(istype(request, /datum/prompt/text), "native held use opens the actual text request")
	var/datum/prompt/text/prompt = request
	TEST_ASSERT_EQUAL(prompt.default, original_name, "the request starts with the board's current name")
	TEST_ASSERT_EQUAL(prompt.max_len, MAX_NAME_LEN, "the name length limit is retained")
	TEST_ASSERT(prompt.name_text, "robot names retain name token normalization")
	TEST_ASSERT_EQUAL(request.ask_flags, ASK_CARRIED | ASK_CAPABLE, "carried and capable rechecks are retained")
	TEST_ASSERT_EQUAL(request.timeout, REQUEST_NO_TIMEOUT, "the prompt retains its indefinite lifetime")
	TEST_ASSERT(test_op_committed(test_answer(actor, "Surveyor")), "the accepted answer commits the op")
	TEST_ASSERT_EQUAL(board.heldname, "Surveyor", "an actual accepted answer changes the board's name")
	TEST_ASSERT_NULL(SSrequests.open_for(actor), "the accepted request closes")
	TEST_ASSERT_EQUAL(actor.get_active_hand(), board, "answering does not move the board")

	actor.next_click = 0
	test_click(actor, board, board)
	test_drain()
	request = SSrequests.open_for(actor)
	TEST_ASSERT_NOTNULL(request, "a second real use opens another request")
	prompt = request
	TEST_ASSERT_EQUAL(prompt.default, "Surveyor", "the next default follows the accepted name")
	test_answer(actor, null, REQ_CANCELLED)
	TEST_ASSERT_EQUAL(board.heldname, "Surveyor", "actual cancellation preserves the existing name")
	TEST_ASSERT_NULL(SSrequests.open_for(actor), "cancellation closes the request")

	actor.next_click = 0
	test_click(actor, board, board)
	test_drain()
	TEST_ASSERT_NOTNULL(SSrequests.open_for(actor), "a third real use opens the recheck control")
	actor.drop_from_inventory(board, run_loc_floor_bottom_left)
	TEST_ASSERT_EQUAL(board.loc, run_loc_floor_bottom_left, "the board is actually released to the floor")
	TEST_ASSERT_NULL(actor.get_active_hand(), "the actor no longer holds the board")
	test_answer(actor, "Stale Name")
	TEST_ASSERT_EQUAL(board.heldname, "Surveyor", "a late answer fails the real carried recheck and preserves the name")
	TEST_ASSERT_NULL(SSrequests.open_for(actor), "the refused late answer closes the stale request")
