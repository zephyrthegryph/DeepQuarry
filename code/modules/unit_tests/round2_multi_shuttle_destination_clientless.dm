/// Genuine clientless refusal coverage; no accepted-setter claim or fake client.
/datum/unit_test/round2_multi_shuttle_destination_clientless
	var/request_case = "denied"

/datum/unit_test/round2_multi_shuttle_destination_clientless/Run()
	test_driver_begin()
	var/obj/machinery/computer/shuttle_control/multi/console
	var/datum/shuttle/autodock/multi/shuttle
	for(var/obj/machinery/computer/shuttle_control/multi/candidate in world)
		var/datum/shuttle/autodock/multi/linked = SSshuttles.shuttles[candidate.shuttle_tag]
		if(!istype(linked) || QDELETED(linked) || !candidate.operable() || linked.moving_status != SHUTTLE_IDLE)
			continue
		var/list/destinations = linked.get_destinations()
		var/has_other_destination = FALSE
		for(var/label in destinations)
			if(destinations[label] != linked.next_location())
				has_other_destination = TRUE
				break
		if(!has_other_destination)
			continue
		console = candidate
		shuttle = linked
		break
	if(!console || !shuttle)
		Fail("Actual map must supply an operable mapped multi console, idle registered shuttle and a different real destination")
		test_driver_end()
		return
	var/obj/effect/shuttle_landmark/original_destination = shuttle.next_location()
	exercise_request(console, shuttle)
	// Cleanup if the regression changed state incorrectly; no existing map atom is test-owned.
	rel_set(shuttle, nameof(shuttle.next_location), original_destination)
	test_driver_end()

/datum/unit_test/round2_multi_shuttle_destination_clientless/proc/exercise_request(obj/machinery/computer/shuttle_control/multi/console, datum/shuttle/autodock/multi/shuttle)
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, get_turf(console))
	TEST_ASSERT_NULL(user.client, "Actual allocated human is genuinely clientless")
	var/datum/tgui/editor = allocate(/datum/tgui, user, console, "ShuttleControl")
	TEST_ASSERT_EQUAL(editor.src_object(), console, "Actual UI constructor binds the real mapped multi console")
	TEST_ASSERT_EQUAL(editor.status, STATUS_INTERACTIVE, "Actual constructor starts interactive without a status mutation")
	TEST_ASSERT_EQUAL(SSshuttles.shuttles[console.shuttle_tag], shuttle, "Actual mapped tag resolves the existing concrete multi shuttle")
	var/obj/effect/shuttle_landmark/original_destination = shuttle.next_location()
	var/list/destinations = shuttle.get_destinations()
	var/selected_label
	for(var/label in destinations)
		if(destinations[label] != original_destination)
			selected_label = label
			break
	var/obj/effect/shuttle_landmark/selected_destination = destinations[selected_label]
	TEST_ASSERT(selected_label && selected_destination && !QDELETED(selected_destination), "Actual getter offers a distinct live destination whose selection would change state")
	input_submit(new /datum/input_event/ui_act(user, editor, "pick", list(), editor.state()))
	var/datum/prompt/choice/shuttle_destination/question = SSrequests.open_for(user)
	TEST_ASSERT(istype(question) && question.owner == editor, "Actual public multi-console UI entry opens its native destination request on the original window")
	TEST_ASSERT(selected_label in question.choices, "Actual registered destination appears in the real choice request")
	if(request_case == "cancelled")
		test_answer(user, null, REQ_CANCELLED)
	else
		if(request_case == "deleted_editor")
			qdel(editor)
			TEST_ASSERT(QDELETED(editor), "Original real UI actually disappears before answer")
		test_answer(user, selected_label)
	TEST_ASSERT_NULL(SSrequests.open_for(user), "Actual refusal, cancellation or owner deletion retires the native request")
	TEST_ASSERT_EQUAL(shuttle.next_location(), original_destination, "Actual registered shuttle destination remains unchanged")
	if(request_case == "denied")
		TEST_ASSERT_EQUAL(question.captured["late_refusal"], "the console cannot be used", "Actual connected-client guard really refuses a valid selected destination")

/datum/unit_test/round2_multi_shuttle_destination_clientless/cancelled
	request_case = "cancelled"

/datum/unit_test/round2_multi_shuttle_destination_clientless/deleted_editor
	request_case = "deleted_editor"
