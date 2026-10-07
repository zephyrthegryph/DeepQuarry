/// Real pen input and native answers; no client-window delivery assertion.
/datum/unit_test/interim_implantcase_native_label_request

/datum/unit_test/interim_implantcase_native_label_request/Run()
	test_driver_begin()
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	actor.enable_godmode()
	var/obj/item/pen/pen = allocate(/obj/item/pen, T)
	var/obj/item/implantcase/case = allocate(/obj/item/implantcase, T)
	TEST_ASSERT(actor.put_in_active_hand(pen), "the real pen enters the actor's active hand")
	TEST_ASSERT_EQUAL(actor.get_active_hand(), pen, "the native click uses the actual held pen")
	TEST_ASSERT(in_range(case, actor), "the actual case is initially in reach")
	actor.next_click = 0
	test_click(actor, case, pen)
	test_drain()
	var/datum/request/request = SSrequests.open_for(actor)
	TEST_ASSERT(istype(request, /datum/prompt/text), "a real pen click opens the native label request")
	TEST_ASSERT_EQUAL(request.subject, pen, "the request rechecks the actual original pen")
	TEST_ASSERT_EQUAL(request.owner, case, "the request belongs to the actual case")
	TEST_ASSERT_EQUAL(request.ask_flags, ASK_HELD | ASK_CAPABLE, "both original actor gates remain")
	TEST_ASSERT_EQUAL(request.timeout, REQUEST_DEFAULT_TIMEOUT, "the label question retains its indefinite timeout (a request given no timeout gets the default, framework_gaps.md E2)")
	var/datum/prompt/text/prompt = request
	TEST_ASSERT_EQUAL(prompt.max_len, MAX_NAME_LEN, "label length remains capped")
	TEST_ASSERT(prompt.name_text, "label names retain original name-token normalization")
	test_answer(actor, "Surveyor")
	TEST_ASSERT_EQUAL(case.name, "Glass Case - 'Surveyor'", "the actual answer writes the exact label")
	TEST_ASSERT_NULL(SSrequests.open_for(actor), "the accepted label request ends")

	actor.next_click = 0
	test_click(actor, case, pen)
	test_drain()
	TEST_ASSERT_NOTNULL(SSrequests.open_for(actor), "the next actual pen click opens the blank-label control")
	test_answer(actor, "")
	TEST_ASSERT_EQUAL(case.name, "Glass Case", "an accepted empty string resets the actual case label")

	actor.next_click = 0
	test_click(actor, case, pen)
	test_drain()
	TEST_ASSERT_NOTNULL(SSrequests.open_for(actor), "the next actual pen click opens the cancellation control")
	test_answer(actor, null, REQ_CANCELLED)
	TEST_ASSERT_EQUAL(case.name, "Glass Case", "explicit cancellation preserves the current label")
	TEST_ASSERT_NULL(SSrequests.open_for(actor), "the cancelled label request ends")

	actor.next_click = 0
	test_click(actor, case, pen)
	test_drain()
	TEST_ASSERT_NOTNULL(SSrequests.open_for(actor), "the final actual pen click opens the held-pen recheck control")
	actor.drop_from_inventory(pen, T)
	TEST_ASSERT_EQUAL(pen.loc, T, "the actual pen is dropped onto the floor")
	TEST_ASSERT_NULL(actor.get_active_hand(), "the original actor no longer holds the pen")
	test_answer(actor, "Stale Label")
	TEST_ASSERT_EQUAL(case.name, "Glass Case", "the late answer fails the actual held-pen gate without renaming")
	TEST_ASSERT_NULL(SSrequests.open_for(actor), "the failed held-pen answer ends the stale request")
	TEST_ASSERT_EQUAL(case.loc, T, "all request outcomes preserve the exact original case location")
