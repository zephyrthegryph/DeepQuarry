/// Actual cyborg camera capture and public copier UI resume the selected image.
/datum/unit_test/round2_photocopier_ai_photo
	var/copy_case = "accepted"

/datum/unit_test/round2_photocopier_ai_photo/Run()
	test_driver_begin()
	exercise_copy()
	own_turf_contents(test_floor())
	test_driver_end()

/datum/unit_test/round2_photocopier_ai_photo/proc/photo_count(turf/surface)
	var/count = 0
	for(var/obj/item/photo/photo in surface)
		count++
	return count

/datum/unit_test/round2_photocopier_ai_photo/proc/exercise_copy()
	var/turf/surface = test_floor()
	var/mob/living/silicon/robot/user = allocate(/mob/living/silicon/robot, surface)
	user.disconnect_from_ai(TRUE)
	var/obj/item/camera/siliconcam/camera = user.aiCamera
	TEST_ASSERT(istype(camera, /obj/item/camera/siliconcam/robot_camera) && camera.loc == user, "Actual cyborg constructor installs its owned photo camera")
	TEST_ASSERT_EQUAL(camera.getsource(user), camera, "Actual supported disconnect selects the genuine local album")
	TEST_ASSERT_EQUAL(length(camera.aipictures), 0, "Fresh real camera starts with no images")
	camera.captureimage(surface, user, FALSE)
	TEST_ASSERT_EQUAL(length(camera.aipictures), 1, "Actual camera capture constructs and adopts one real image")
	var/obj/item/photo/source_photo = camera.aipictures[1]
	TEST_ASSERT(source_photo.img && source_photo.tiny, "Real capture supplies actual full and thumbnail icons used by the physical copier")
	TEST_ASSERT_EQUAL(source_photo.loc, camera, "Actual camera capture retains its real photograph in the album")
	var/original_desc = source_photo.desc
	var/obj/machinery/photocopier/copier = allocate(/obj/machinery/photocopier, surface)
	TEST_ASSERT(copier.operable(), "Actual fresh copier must be operable without a gate mutation")
	var/original_toner = copier.toner
	TEST_ASSERT_EQUAL(original_toner, 30, "Actual declared copier supply exercises the existing double toner debit")
	var/datum/tgui/editor = allocate(/datum/tgui, user, copier, "Photocopier")
	TEST_ASSERT_EQUAL(editor.status, STATUS_INTERACTIVE, "Actual UI constructor is interactive without a status mutation")
	var/before_count = photo_count(surface)
	TEST_ASSERT_EQUAL(before_count, 0, "Actual fixture starts with no loose printed photographs")
	input_submit(new /datum/input_event/ui_act(user, editor, "ai_photo", list(), editor.state()))
	// The button is the ai_photo op: it asks which picture (asks()), the handler prints the answer.
	var/datum/prompt/choice/question = SSrequests.open_for(user)
	TEST_ASSERT(istype(question) && question.answerer == user, "Actual public copier button asks the cyborg which picture")
	TEST_ASSERT(source_photo.name in question.choices, "Actual captured photograph label is offered")
	TEST_ASSERT_EQUAL(photo_count(surface), before_count, "Pending selection has not printed a photo")
	TEST_ASSERT_EQUAL(copier.toner, original_toner, "Pending selection consumes no toner")
	if(copy_case == "cancelled")
		test_answer(user, null, REQ_CANCELLED)
		TEST_ASSERT_EQUAL(copier.toner, original_toner, "Actual cancellation consumes no toner")
		TEST_ASSERT_EQUAL(photo_count(surface), before_count, "Actual cancellation prints no photo")
	else if(copy_case == "toner_depleted")
		// Real concurrent copying consumes ink; no private toner or operability write.
		for(var/i in 1 to 6)
			var/obj/item/photo/other_output = copier.photocopy(source_photo)
			TEST_ASSERT(istype(other_output) && other_output.loc == surface, "Actual existing copier operation produces the concurrent print")
		TEST_ASSERT_EQUAL(copier.toner, 0, "Six actual copy operations exhaust the declared toner supply")
		var/depleted_count = photo_count(surface)
		test_answer(user, source_photo.name)
		TEST_ASSERT_EQUAL(copier.toner, 0, "Refused delayed selection consumes no additional ink")
		TEST_ASSERT_EQUAL(photo_count(surface), depleted_count, "Refused delayed selection prints no extra photo")
	else
		test_answer(user, source_photo.name)
		TEST_ASSERT_EQUAL(photo_count(surface), before_count + 1, "Actual accepted selection resumes and prints exactly one photograph")
		TEST_ASSERT_EQUAL(copier.toner, original_toner - 10, "Restored existing helper and caller each retain their original five-toner debit")
		var/obj/item/photo/output
		for(var/obj/item/photo/printed in surface)
			output = printed
		TEST_ASSERT(output && output != source_photo && output.img && output.tiny, "Actual output is a distinct copied photograph with real image data")
		TEST_ASSERT(findtext(output.desc, "Copied by [user.name]"), "Actual resumed tail attributes the print to its original cyborg")
	TEST_ASSERT_NULL(SSrequests.open_for(user), "Actual native selection is retired after the answer")
	TEST_ASSERT(!QDELETED(source_photo) && source_photo.loc == camera && (source_photo in camera.aipictures), "All answer outcomes preserve the original album photograph")
	TEST_ASSERT_EQUAL(source_photo.desc, original_desc, "Copy attribution does not alter the original image description")

/datum/unit_test/round2_photocopier_ai_photo/cancelled
	copy_case = "cancelled"

/datum/unit_test/round2_photocopier_ai_photo/toner_depleted
	copy_case = "toner_depleted"
