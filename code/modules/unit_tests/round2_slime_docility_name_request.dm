/// Real slime, human and held potion; public click inbox and native answer driver.
/datum/unit_test/round2_slime_docility_name_request
	var/name_case = "named"

/datum/unit_test/round2_slime_docility_name_request/Run()
	test_driver_begin()
	exercise_docility()
	own_turf_contents(test_floor())
	test_driver_end()

/datum/unit_test/round2_slime_docility_name_request/proc/exercise_docility()
	var/turf/surface = test_floor()
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, surface)
	var/mob/living/simple_mob/slime/xenobio/slime = allocate(/mob/living/simple_mob/slime/xenobio, surface)
	var/obj/item/slimepotion/docility/potion = allocate(/obj/item/slimepotion/docility, surface)
	TEST_ASSERT(slime.ai_brain && slime.slime_state, "Actual slime constructor supplies its real brain and slime state")
	TEST_ASSERT(!slime.harmless && slime.nutrition != 700, "Actual untreated slime starts without potion pacification or full treatment nutrition")
	TEST_ASSERT(!potion.currently_using, "Actual new potion starts unused")
	var/original_name = slime.name
	var/original_real_name = slime.real_name
	TEST_ASSERT(user.put_in_active_hand(potion), "Actual inventory equips the original potion")
	slime.ai_brain.give_target(user, TRUE)
	TEST_ASSERT_EQUAL(slime.ai_brain.primary_threat, user, "Actual public brain API establishes a real threat before treatment")
	input_submit(new /datum/input_event/click(user, slime, null, "mapwindow.map", "left=1"))
	var/datum/prompt/text/slime_docility_name/question = SSrequests.open_for(user)
	TEST_ASSERT(istype(question), "Actual public click and held-item attack open the native naming request")
	TEST_ASSERT_EQUAL(question.owner, potion, "Original actual potion owns the naming continuation")
	TEST_ASSERT_EQUAL(question.subject, slime, "Naming request keeps the actual treated slime as its subject")
	TEST_ASSERT_EQUAL(question.answerer, user, "Original real human receives the naming question")
	TEST_ASSERT(potion.currently_using && slime.harmless, "Actual attack locks potion use and really pacifies the slime before naming")
	TEST_ASSERT_EQUAL(slime.nutrition, 700, "Actual potion attack fills treated slime nutrition to seven hundred")
	TEST_ASSERT_NULL(slime.ai_brain.primary_threat, "Actual pacification removes the real brain threat")
	TEST_ASSERT(!QDELETED(potion) && user.get_active_hand() == potion, "Potion remains in real inventory while its naming request is pending")
	if(name_case == "closed")
		test_answer(user, null, REQ_CANCELLED)
		TEST_ASSERT_NULL(SSrequests.open_for(user), "Closing the actual question retires its request")
		TEST_ASSERT(!QDELETED(potion) && potion.currently_using, "Close preserves the already-used unconsumed potion as intended")
		TEST_ASSERT_EQUAL(user.get_active_hand(), potion, "Close retains actual potion custody")
		TEST_ASSERT_EQUAL(slime.name, original_name, "Close does not rename the already treated slime")
		TEST_ASSERT(slime.harmless, "Close leaves actual pacification intact")
		return
	test_answer(user, name_case == "empty" ? "" : "Round2 Pet")
	TEST_ASSERT_NULL(SSrequests.open_for(user), "Actual accepted naming answer retires its request")
	TEST_ASSERT(QDELETED(potion), "Actual accepted answer consumes the original held potion instead of replaying its already-used guard")
	TEST_ASSERT_NULL(user.get_active_hand(), "Real consume clears the inventory slot of the deleted potion")
	TEST_ASSERT(slime.harmless && slime.nutrition == 700, "Accepted naming preserves the already applied real treatment")
	if(name_case == "empty")
		TEST_ASSERT_EQUAL(slime.name, original_name, "Empty accepted answer preserves actual displayed slime name")
		TEST_ASSERT_EQUAL(slime.real_name, original_real_name, "Empty accepted answer preserves actual real name")
	else
		TEST_ASSERT_EQUAL(slime.name, "Round2 Pet", "Actual accepted request renames the treated slime")
		TEST_ASSERT_EQUAL(slime.real_name, "Round2 Pet", "Actual accepted request also updates the real name")

/datum/unit_test/round2_slime_docility_name_request/empty
	name_case = "empty"

/datum/unit_test/round2_slime_docility_name_request/closed
	name_case = "closed"
