/// Actual registered shuttle, actual console/UI, public legacy UI inbox and request driver.
/datum/unit_test/round2_shuttle_docking_codes_request
	var/delete_editor = FALSE

/datum/unit_test/round2_shuttle_docking_codes_request/Run()
	test_driver_begin()
	var/datum/shuttle/autodock/shuttle
	for(var/tag in SSshuttles.shuttles)
		var/datum/shuttle/autodock/candidate = SSshuttles.shuttles[tag]
		if(!istype(candidate) || QDELETED(candidate))
			continue
		if(candidate.shuttle_docking_controller && candidate.shuttle_docking_controller.docking_codes != candidate.docking_codes)
			continue
		shuttle = candidate
		break
	if(!shuttle)
		Fail("Actual map must supply a registered autodock shuttle whose controller codes agree with its public setter state")
		test_driver_end()
		return
	var/original_codes = shuttle.docking_codes
	exercise_codes(shuttle)
	shuttle.set_docking_codes(original_codes)
	own_turf_contents(test_floor())
	test_driver_end()

/datum/unit_test/round2_shuttle_docking_codes_request/proc/exercise_codes(datum/shuttle/autodock/shuttle)
	var/turf/surface = test_floor()
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, surface)
	var/obj/machinery/computer/shuttle_control/console = allocate(/obj/machinery/computer/shuttle_control, surface)
	console.set_shuttle_tag(shuttle.name)
	TEST_ASSERT_EQUAL(SSshuttles.shuttles[console.shuttle_tag], shuttle, "Actual console tag resolves the existing registered shuttle")
	var/datum/tgui/editor = allocate(/datum/tgui, user, console, "ShuttleControl")
	TEST_ASSERT_EQUAL(editor.src_object(), console, "Actual UI constructor binds the real shuttle console")
	TEST_ASSERT_EQUAL(editor.status, STATUS_INTERACTIVE, "Actual UI starts interactive without a status mutation")
	var/original_codes = shuttle.docking_codes
	input_submit(new /datum/input_event/ui_act(user, editor, "set_codes", list(), editor.state()))
	var/datum/prompt/text/shuttle_docking_codes/question = SSrequests.open_for(user)
	TEST_ASSERT(istype(question) && question.owner == editor, "Public legacy UI entry opens the real docking-code request on the original editor")
	TEST_ASSERT_EQUAL(question.default, original_codes, "Actual request reads the registered shuttle's current docking-code default")
	if(delete_editor)
		qdel(editor)
		TEST_ASSERT(QDELETED(editor), "Original actual UI really disappears before answer")
		test_answer(user, "should-not-apply")
		TEST_ASSERT_NULL(SSrequests.open_for(user), "Deleted real owner cannot leave an active docking-code question")
		TEST_ASSERT_EQUAL(shuttle.docking_codes, original_codes, "An answer after original UI deletion cannot change registered shuttle codes")
		return
	test_answer(user, null, REQ_CANCELLED)
	TEST_ASSERT_NULL(SSrequests.open_for(user), "Actual cancellation retires the request")
	TEST_ASSERT_EQUAL(shuttle.docking_codes, original_codes, "Cancellation preserves actual registered codes")
	input_submit(new /datum/input_event/ui_act(user, editor, "set_codes", list(), editor.state()))
	TEST_ASSERT(istype(SSrequests.open_for(user), /datum/prompt/text/shuttle_docking_codes), "Empty-code case opens through actual public UI dispatch")
	test_answer(user, "")
	TEST_ASSERT_NULL(SSrequests.open_for(user), "Accepted empty text completes the actual request")
	TEST_ASSERT_EQUAL(shuttle.docking_codes, original_codes, "Actual empty answer preserves existing docking codes")
	input_submit(new /datum/input_event/ui_act(user, editor, "set_codes", list(), editor.state()))
	TEST_ASSERT(istype(SSrequests.open_for(user), /datum/prompt/text/shuttle_docking_codes), "Accepted-code case opens through actual public UI dispatch")
	var/newcode = original_codes == "ROUND2-CODE" ? "round2-alt" : "round2-code"
	test_answer(user, newcode)
	TEST_ASSERT_NULL(SSrequests.open_for(user), "Real accepted code retires its request")
	TEST_ASSERT_EQUAL(shuttle.docking_codes, uppertext(newcode), "Actual public answer calls the shuttle setter with uppercase codes")
	if(shuttle.shuttle_docking_controller)
		TEST_ASSERT_EQUAL(shuttle.shuttle_docking_controller.docking_codes, uppertext(newcode), "Actual setter also updates the existing docking controller")

/datum/unit_test/round2_shuttle_docking_codes_request/deleted_editor
	delete_editor = TRUE
