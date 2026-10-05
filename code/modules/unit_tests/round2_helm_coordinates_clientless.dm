/// Real mapped linked helm: clientless coordinate refusal/cancellation, no XY success claim.
/datum/unit_test/round2_helm_coordinates_clientless
	var/request_case = "xy_denied"

/datum/unit_test/round2_helm_coordinates_clientless/Run()
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
	exercise_coordinates(mapped_helm)
	test_driver_end()

/datum/unit_test/round2_helm_coordinates_clientless/proc/exercise_coordinates(obj/machinery/computer/ship/helm/mapped_helm)
	var/turf/surface = get_turf(mapped_helm)
	var/obj/machinery/computer/ship/helm/helm = allocate(/obj/machinery/computer/ship/helm, surface)
	helm.attempt_hook_up(mapped_helm.linked())
	TEST_ASSERT_EQUAL(helm.linked(), mapped_helm.linked(), "Actual public ship-population hook links the real allocated helm to the existing map ship")
	TEST_ASSERT(helm.linked() && !QDELETED(helm.linked()), "Allocated real helm has a live ship through normal ownership discovery")
	TEST_ASSERT(helm.operable(), "Real constructor on the actual ship area supplies an operable helm without power mutations")
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, surface)
	TEST_ASSERT_NULL(user.client, "Actual human is genuinely clientless for the production status gate")
	var/datum/ui_decl/decl = ui_decl_of(helm)
	var/datum/tgui/editor = allocate(/datum/tgui, user, helm, decl?.interface)
	TEST_ASSERT_EQUAL(editor.src_object(), helm, "Actual UI constructor binds the real mapped helm")
	TEST_ASSERT_EQUAL(editor.status, STATUS_INTERACTIVE, "Actual UI starts normally without a status mutation")
	TEST_ASSERT_EQUAL(editor.state(), GLOB.tgui_default_state, "Actual editor uses the production default state")
	TEST_ASSERT_EQUAL(helm.tgui_status(user, editor.state()), STATUS_CLOSE, "Actual default-state status rejects the genuinely clientless human")
	var/original_x = helm.dx
	var/original_y = helm.dy
	var/set_x = request_case != "y_denied"
	input_submit(new /datum/input_event/ui_act(user, editor, "setcoord", list("setx" = set_x, "sety" = TRUE), editor.state()))
	var/datum/prompt/number/helm_coordinates/question = SSrequests.open_for(user)
	TEST_ASSERT(istype(question) && question.owner == editor, "Actual public coordinate UI entry opens a native question on its original window")
	TEST_ASSERT_EQUAL(question.step_name, set_x ? "x" : "y", "Actual captured flags choose the correct first coordinate stage")
	TEST_ASSERT_EQUAL(question.default, set_x ? original_x : original_y, "Actual coordinate request reads current real coordinate state")
	TEST_ASSERT_EQUAL(question.captured["setx"], set_x, "Actual request captures original X-selection flag")
	TEST_ASSERT(question.captured["sety"], "Actual request retains original Y-selection flag")
	if(request_case == "cancelled")
		test_answer(user, null, REQ_CANCELLED)
	else
		var/original_axis = set_x ? original_x : original_y
		var/new_axis = original_axis == 1 ? 2 : 1
		test_answer(user, new_axis)
		TEST_ASSERT_EQUAL(question.captured["late_refusal"], "the helm window is not interactive", "Actual client-required status query refuses a valid different coordinate")
	TEST_ASSERT_NULL(SSrequests.open_for(user), "Actual denial or cancellation retires the request without opening another stage")
	TEST_ASSERT_EQUAL(helm.dx, original_x, "Actual denial/cancellation preserves exact original X coordinate")
	TEST_ASSERT_EQUAL(helm.dy, original_y, "Actual denial/cancellation preserves exact original Y coordinate")

/datum/unit_test/round2_helm_coordinates_clientless/y_denied
	request_case = "y_denied"

/datum/unit_test/round2_helm_coordinates_clientless/cancelled
	request_case = "cancelled"
