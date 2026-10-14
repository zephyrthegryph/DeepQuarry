/// Prompt-boundary fixture only: avoid all real player savefile reads.
/// The inherited actual bank request code and handler remain unmodified.
/obj/machinery/item_bank/unit_test_no_savefile/persist_item_savefile_load(mob/user, thing)
	return 0

/datum/unit_test/round2_item_bank_retrieval_null_submit

/datum/unit_test/round2_item_bank_retrieval_null_submit/Run()
	test_driver_begin()
	exercise_null_submit()
	test_driver_end()

/datum/unit_test/round2_item_bank_retrieval_null_submit/proc/exercise_null_submit()
	var/turf/surface = test_floor()
	TEST_ASSERT(surface, "Actual test map supplies a floor")
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, surface)
	var/obj/machinery/item_bank/bank = allocate(/obj/machinery/item_bank/unit_test_no_savefile, surface)
	TEST_ASSERT_NULL(user.client, "Real test human has no synthetic client")
	TEST_ASSERT(!bank.busy_bank, "Actual allocated bank initially has no retrieval in progress")
	bank.start_using(user)
	var/datum/prompt/choice/item_bank_retrieval/question = SSrequests.open_for(user)
	TEST_ASSERT(istype(question), "Actual public start_using opens the retrieval choice request")
	TEST_ASSERT(question.owner == bank && question.answerer == user, "Actual request retains original bank and real human")
	TEST_ASSERT_EQUAL(question.step_name, "choice", "Public entry opens the first retrieval stage")
	TEST_ASSERT(("Retrieve item" in question.choices) && ("Cancel" in question.choices), "Actual retrieval options are present before answering")
	test_answer(user, null)
	TEST_ASSERT_EQUAL(question.outcome, REQ_ANSWERED, "Native null submission genuinely reaches the answered-handler route rather than explicit cancellation")
	TEST_ASSERT(!question.is_open(), "Original native request is retired")
	TEST_ASSERT_NULL(SSrequests.open_for(user), "Null submission ends quietly without reopening a follow-up retrieval question")
	TEST_ASSERT(!bank.busy_bank, "Null submission leaves actual bank retrieval state unchanged")
