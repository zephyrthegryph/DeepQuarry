/// Real mapped linked helm and real UI inbox; restores through the public numeric request path.
/datum/unit_test/round2_helm_limit_requests
	var/limit_action = "speedlimit"

/datum/unit_test/round2_helm_limit_requests/Run()
	test_driver_begin()
	var/obj/machinery/computer/ship/helm/helm
	for(var/obj/machinery/computer/ship/helm/candidate in world)
		if(candidate.linked() && candidate.speedlimit > 0 && candidate.speedlimit <= 100 && candidate.accellimit > 0)
			helm = candidate
			break
	if(!helm)
		Fail("Actual map must supply a linked helm with positive original limits restorable through public answers")
		test_driver_end()
		return
	var/original_limit = limit_action == "speedlimit" ? helm.speedlimit : helm.accellimit
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, get_turf(helm))
	var/datum/tgui/editor = allocate(/datum/tgui, user, helm, helm.ui_interface(user))
	exercise_limit(user, helm, editor, original_limit)
	// Restore via the same actual UI request, not a direct field/gate write.
	input_submit(new /datum/input_event/ui_act(user, editor, limit_action, list(), editor.state()))
	test_answer(user, original_limit * 1000)
	var/restored = limit_action == "speedlimit" ? helm.speedlimit : helm.accellimit
	if(abs(restored - original_limit) > 0.000001)
		Fail("Public request restoration failed to restore the original actual helm limit")
	test_driver_end()

/datum/unit_test/round2_helm_limit_requests/proc/exercise_limit(mob/living/carbon/human/user, obj/machinery/computer/ship/helm/helm, datum/tgui/editor, original_limit)
	TEST_ASSERT(helm.linked() && !QDELETED(helm.linked()), "Actual mapped helm has its live ship relation")
	TEST_ASSERT_EQUAL(editor.src_object(), helm, "Actual UI constructor binds the real mapped helm")
	TEST_ASSERT_EQUAL(editor.status, STATUS_INTERACTIVE, "Actual UI starts interactive without a gate mutation")
	input_submit(new /datum/input_event/ui_act(user, editor, limit_action, list(), editor.state()))
	var/datum/prompt/number/helm_limit/question = SSrequests.open_for(user)
	TEST_ASSERT(istype(question, limit_action == "speedlimit" ? /datum/prompt/number/helm_limit/speed : /datum/prompt/number/helm_limit/acceleration), "Actual public helm action asks its own limit")
	TEST_ASSERT_EQUAL(question.default, original_limit * 1000, "Actual request reads the live original limit in displayed units")
	test_answer(user, 0)
	TEST_ASSERT_NULL(SSrequests.open_for(user), "Actual zero answer retires the request")
	var/after_zero = limit_action == "speedlimit" ? helm.speedlimit : helm.accellimit
	TEST_ASSERT_EQUAL(after_zero, original_limit, "Actual zero answer preserves the previous real limit as current behavior requires")
	input_submit(new /datum/input_event/ui_act(user, editor, limit_action, list(), editor.state()))
	TEST_ASSERT(istype(SSrequests.open_for(user), /datum/prompt/number/helm_limit), "Positive-limit case opens through actual public UI again")
	var/new_display_limit = abs(original_limit - 0.0125) < 0.000001 ? 25.25 : 12.5
	test_answer(user, new_display_limit)
	TEST_ASSERT_NULL(SSrequests.open_for(user), "Actual positive answer retires the request")
	var/updated = limit_action == "speedlimit" ? helm.speedlimit : helm.accellimit
	TEST_ASSERT(abs(updated - new_display_limit / 1000) < 0.000001, "Actual native answer writes the real fractional limit in internal units")
	TEST_ASSERT(abs(updated - original_limit) > 0.000001, "Accepted positive answer must genuinely change actual limit state")
	input_submit(new /datum/input_event/ui_act(user, editor, limit_action, list(), editor.state()))
	TEST_ASSERT(istype(SSrequests.open_for(user), /datum/prompt/number/helm_limit), "Cancellation opens through the actual public handler")
	test_answer(user, null, REQ_CANCELLED)
	TEST_ASSERT_NULL(SSrequests.open_for(user), "Actual cancellation retires the numeric request")
	var/after_cancel = limit_action == "speedlimit" ? helm.speedlimit : helm.accellimit
	TEST_ASSERT_EQUAL(after_cancel, updated, "Cancellation preserves the actual most recently accepted limit")

/datum/unit_test/round2_helm_limit_requests/acceleration
	limit_action = "accellimit"
