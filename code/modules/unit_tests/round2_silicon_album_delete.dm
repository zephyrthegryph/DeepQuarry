/// Real cyborg photo album entry, native answers and declared photo custody.
/datum/unit_test/round2_silicon_album_delete
	var/album_case = "delete"

/datum/unit_test/round2_silicon_album_delete/Run()
	test_driver_begin()
	exercise_album()
	test_driver_end()

/datum/unit_test/round2_silicon_album_delete/proc/exercise_album()
	var/turf/surface = test_floor()
	var/mob/living/silicon/robot/user = allocate(/mob/living/silicon/robot, surface)
	user.disconnect_from_ai(TRUE)
	var/obj/item/camera/siliconcam/camera = user.aiCamera
	TEST_ASSERT(istype(camera, /obj/item/camera/siliconcam/robot_camera), "Actual cyborg constructor installs its real photo camera")
	TEST_ASSERT_EQUAL(camera.loc, user, "Actual constructor camera is physically held by its cyborg")
	TEST_ASSERT_NULL(user.connected_ai, "Actual supported disconnect API selects the local album without an invented AI link")
	TEST_ASSERT_EQUAL(camera.getsource(user), camera, "Actual supported robot source lookup resolves the local camera")
	TEST_ASSERT_EQUAL(length(camera.aipictures), 0, "Actual fresh camera starts with an empty album")
	var/obj/item/photo/local_photo = allocate(/obj/item/photo, surface)
	camera.injectaialbum(local_photo)
	TEST_ASSERT(local_photo in camera.aipictures, "Real album API adopts the actual photograph")
	TEST_ASSERT_EQUAL(local_photo.loc, camera, "Real move_into establishes physical photo custody in the camera")
	var/obj/item/photo/offered_photo = local_photo
	var/obj/item/camera/siliconcam/source_camera = camera
	if(album_case == "remote")
		var/mob/living/silicon/robot/other_robot = allocate(/mob/living/silicon/robot, surface)
		source_camera = other_robot.aiCamera
		TEST_ASSERT(istype(source_camera, /obj/item/camera/siliconcam/robot_camera) && source_camera != camera, "Second actual cyborg owns a distinct real camera")
		offered_photo = allocate(/obj/item/photo, surface)
		source_camera.injectaialbum(offered_photo)
		TEST_ASSERT((offered_photo in source_camera.aipictures) && offered_photo.loc == source_camera, "Actual other album API adopts its remote photograph")
		TEST_ASSERT_EQUAL(offered_photo.name, local_photo.name, "Real independently numbered albums have a matching label, exercising local-owner rejection before accidental local retarget")
		camera.deletepicture(user, source_camera)
	else
		user.delete_images()
	var/datum/prompt/choice/silicon_album/question = SSrequests.open_for(user)
	TEST_ASSERT(istype(question) && question.owner == camera && question.answerer == user, "Actual public deletion entry opens the native camera request")
	TEST_ASSERT(offered_photo.name in question.choices, "Actual album request offers the real current photograph label")
	TEST_ASSERT_EQUAL(question.album_action, "delete", "Actual public entry requests deletion rather than rendering")
	if(album_case == "cancelled")
		test_answer(user, null, REQ_CANCELLED)
		TEST_ASSERT(!QDELETED(local_photo) && (local_photo in camera.aipictures) && local_photo.loc == camera, "Actual cancellation retains the live owned photograph and its physical custody")
	else if(album_case == "remote")
		TEST_ASSERT_EQUAL(question.subject, source_camera, "Existing explicit-camera public parameter captures the real remote source")
		test_answer(user, offered_photo.name)
		TEST_ASSERT_EQUAL(question.last_error, "not local", "Actual current ownership requirement refuses deleting another camera's photograph")
		TEST_ASSERT_EQUAL(question.outcome, REQ_CANCELLED, "Actual late ownership recheck cancels the answered request before the deletion callback")
		TEST_ASSERT(!QDELETED(offered_photo) && (offered_photo in source_camera.aipictures) && offered_photo.loc == source_camera, "Refusal preserves the remote photograph and its genuine custody")
		TEST_ASSERT(!QDELETED(local_photo) && (local_photo in camera.aipictures) && local_photo.loc == camera, "Matching local label is not accidentally deleted or moved")
	else
		test_answer(user, local_photo.name)
		TEST_ASSERT(QDELETED(local_photo), "Actual accepted native answer consumes the selected real photograph")
		TEST_ASSERT(!(local_photo in camera.aipictures), "Actual consumption unlinks the camera's declared owned album")
		TEST_ASSERT_EQUAL(length(camera.aipictures), 0, "Actual album is empty after its only photo is consumed")
	TEST_ASSERT_NULL(SSrequests.open_for(user), "Accepted deletion or explicit cancellation retires the native request")

/datum/unit_test/round2_silicon_album_delete/cancelled
	album_case = "cancelled"

/datum/unit_test/round2_silicon_album_delete/remote_owner
	album_case = "remote"
