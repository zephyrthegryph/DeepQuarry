/// Observe explicit actor forwarding while exercising the actual native confirmation.
/obj/machinery/photocopier/faxmachine/interim_request_actor
	var/request_actor_ref
	var/request_count = 0

/obj/machinery/photocopier/faxmachine/interim_request_actor/request_roles(mob/living/L, list/answers)
	request_actor_ref = L ? REF(L) : null
	request_count++
	return ..(L, answers)

/datum/unit_test/interim_fax_request_actor_cancel/Run()
	test_driver_begin()
	check_native_confirmation()
	test_driver_end()

/datum/unit_test/interim_fax_request_actor_cancel/proc/check_native_confirmation()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	var/obj/machinery/photocopier/faxmachine/interim_request_actor/fax = allocate(/obj/machinery/photocopier/faxmachine/interim_request_actor, T)
	set_global("last_fax_role_request", null)
	TEST_ASSERT_NULL(SSrequests.open_for(actor), "the real actor starts without an unrelated question")
	fax.interaction_request_roles(actor, null, null)
	TEST_ASSERT_EQUAL(fax.request_count, 1, "the public interaction reaches the real request helper")
	TEST_ASSERT_EQUAL(fax.request_actor_ref, REF(actor), "the helper receives the actual actor without ambient usr")
	var/datum/prompt/choice/fax_role_request/asked = SSrequests.open_for(actor)
	TEST_ASSERT(istype(asked), "the real parent helper opens the native initial confirmation")
	TEST_ASSERT_EQUAL(asked.owner, fax, "the actual fax owns its continuation")
	TEST_ASSERT_EQUAL(asked.answerer, actor, "the original actor answers its confirmation")
	TEST_ASSERT_EQUAL(asked.title, "Confirmation", "the original confirmation title is retained")
	TEST_ASSERT(asked.buttons, "the confirmation uses the original alert buttons")
	test_answer(actor, "No")
	TEST_ASSERT_EQUAL(fax.request_count, 2, "a real No replays the production helper with its current guards")
	TEST_ASSERT_NULL(SSrequests.open_for(actor), "No retires the initial request without asking a job")
	TEST_ASSERT_NULL(GLOB.last_fax_role_request, "No cannot update the transmission timestamp")
	TEST_ASSERT(!fax.sendcooldown, "No does not begin a fax-send cooldown")
	fax.interaction_request_roles(actor, null, null)
	asked = SSrequests.open_for(actor)
	TEST_ASSERT(istype(asked), "the public entry can open a fresh confirmation")
	var/count_before_close = fax.request_count
	test_answer(actor, null, REQ_CANCELLED)
	TEST_ASSERT_EQUAL(fax.request_count, count_before_close, "closing the actual request never replays its helper")
	TEST_ASSERT_NULL(SSrequests.open_for(actor), "closing retires the actual confirmation")
	TEST_ASSERT_NULL(GLOB.last_fax_role_request, "closing cannot transmit a staffing request")
