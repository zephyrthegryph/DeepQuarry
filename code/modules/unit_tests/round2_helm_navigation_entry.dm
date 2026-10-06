/// Actual public Add navigation UI request; headless cancellation/denial must not register provisional records.
/datum/unit_test/round2_helm_navigation_entry
	var/navigation_case = "denied"

/datum/unit_test/round2_helm_navigation_entry/Run()
	test_driver_begin()
	var/obj/machinery/computer/ship/helm/mapped_helm
	for(var/obj/machinery/computer/ship/helm/candidate in world)
		if(candidate.linked() && candidate.operable())
			mapped_helm = candidate
			break
	if(!mapped_helm)
		Fail("Actual map must supply an operable mapped helm with a live ship link")
		test_driver_end()
		return
	exercise_navigation(mapped_helm)
	test_driver_end()

/datum/unit_test/round2_helm_navigation_entry/proc/exercise_navigation(obj/machinery/computer/ship/helm/mapped_helm)
	var/turf/surface = get_turf(mapped_helm)
	var/obj/machinery/computer/ship/helm/helm = allocate(/obj/machinery/computer/ship/helm, surface)
	TEST_ASSERT(helm.attempt_hook_up(mapped_helm.linked()), "Actual public hook-up API links the allocated console to the genuine mapped ship")
	TEST_ASSERT_EQUAL(helm.linked(), mapped_helm.linked(), "Real allocated helm retains the exact actual mapped ship through supported hook-up")
	TEST_ASSERT(helm.operable(), "Real allocated console is operable without power or link mutations")
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, surface)
	TEST_ASSERT_NULL(user.client, "Actual human is genuinely clientless")
	var/datum/tgui/editor = allocate(/datum/tgui, user, helm, helm.ui_interface(user))
	TEST_ASSERT_EQUAL(editor.status, STATUS_INTERACTIVE, "Actual UI constructor starts normally without a status write")
	TEST_ASSERT_EQUAL(editor.src_object(), helm, "Actual UI constructor binds the original real console")
	TEST_ASSERT_EQUAL(helm.tgui_status(user, editor.state()), STATUS_CLOSE, "Actual default state rejects the real clientless actor")
	var/original_waypoints = length(REGISTRY_MEMBERS(REGISTRY_WAYPOINTS))
	var/original_uid = GLOB.file_uid
	var/original_entries = length(helm.known_sectors)
	input_submit(new /datum/input_event/ui_act(user, editor, "add", list("add" = "new"), editor.state()))
	// The button is the add op: its first question is the entry's name.
	var/datum/prompt/text/question = SSrequests.open_for(user)
	TEST_ASSERT(istype(question) && question.answerer == user, "Actual public UI action opens the navigation name question")
	TEST_ASSERT_EQUAL(question.question, "Input navigation entry name", "The name is asked first")
	TEST_ASSERT_EQUAL(length(REGISTRY_MEMBERS(REGISTRY_WAYPOINTS)), original_waypoints, "Opening the real name question does not register an abandoned waypoint")
	TEST_ASSERT_EQUAL(GLOB.file_uid, original_uid, "Opening the real name question does not allocate an abandoned file identity")
	if(navigation_case == "cancelled")
		test_answer(user, null, REQ_CANCELLED)
	else if(navigation_case == "deleted_window")
		qdel(editor)
		TEST_ASSERT(QDELETED(editor), "Original actual window is genuinely destroyed")
		test_answer(user, "round2 uncommitted navigation")
	else
		test_answer(user, "round2 uncommitted navigation")
		if(SSrequests.open_for(user))
			test_answer(user, 5) // x, if the window still lets the op ask it
		if(SSrequests.open_for(user))
			test_answer(user, 5) // y
	TEST_ASSERT_NULL(SSrequests.open_for(user), "Actual cancel or denial retires without opening a coordinate question")
	TEST_ASSERT_EQUAL(length(helm.known_sectors), original_entries, "Actual cancel or denial preserves real navigation entries")
	TEST_ASSERT_EQUAL(length(REGISTRY_MEMBERS(REGISTRY_WAYPOINTS)), original_waypoints, "Actual cancel or denial leaves no provisional waypoint registered")
	TEST_ASSERT_EQUAL(GLOB.file_uid, original_uid, "Actual cancel or denial leaves no abandoned file identity")

/datum/unit_test/round2_helm_navigation_entry/cancelled
	navigation_case = "cancelled"

/datum/unit_test/round2_helm_navigation_entry/deleted_window
	navigation_case = "deleted_window"
