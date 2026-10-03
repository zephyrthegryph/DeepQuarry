/// The remote button's emag removes both access modes, making its previously refused press usable without changing wiring or pressing it.
/datum/unit_test/interim_remote_button_emag_access
	parent_type = /datum/unit_test/dq_p2_door

/datum/unit_test/interim_remote_button_emag_access/run_gate()
	var/obj/machinery/button/remote/button = allocate(/obj/machinery/button/remote, tile(4, 2))
	p2_door_set_power(button, TRUE)
	button.req_access = list(ACCESS_ENGINE_EQUIP)
	button.req_one_access = list(ACCESS_SECURITY, ACCESS_RESEARCH)
	var/mob/living/carbon/human/user = make_person(null, tile(4, 3))
	var/wiring_before = button.wires_num
	TEST_ASSERT(button.operable(), "the button is operable")
	TEST_ASSERT(!button.allowed(user), "the actor lacks both configured access modes")
	TEST_ASSERT_EQUAL(button.desiredstate, 0, "the button begins with its default requested state")
	click(user, button, null)
	TEST_ASSERT_EQUAL(button.desiredstate, 0, "an unauthorized press preserves the requested state")
	TEST_ASSERT_EQUAL(emag_target(button, 1, user), 1, "the declared emag consumes one use to remove authentication")
	TEST_ASSERT_NULL(button.req_access, "the emag clears the required-all access list")
	TEST_ASSERT_NULL(button.req_one_access, "the emag clears the required-any access list")
	TEST_ASSERT(button.allowed(user), "the same actor is allowed after authentication is removed")
	TEST_ASSERT_EQUAL(button.wires_num, wiring_before, "emagging preserves the wiring flags")
	TEST_ASSERT_EQUAL(button.desiredstate, 0, "emagging does not itself press the button")
	click(user, button, null)
	TEST_ASSERT_EQUAL(button.desiredstate, 1, "the now-authorized press changes the requested state")
	TEST_ASSERT_EQUAL(emag_target(button, 1, user), EMAG_DECLINED, "a repeat without access lists is declined and consumes no additional emag use")
	TEST_ASSERT_EQUAL(button.desiredstate, 1, "the repeat emag does not press the button")
	TEST_ASSERT_NULL(button.req_access, "repeat refusal preserves the cleared required-all list")
	TEST_ASSERT_NULL(button.req_one_access, "repeat refusal preserves the cleared required-any list")
	TEST_ASSERT_EQUAL(button.wires_num, wiring_before, "the full sequence preserves wiring flags")
