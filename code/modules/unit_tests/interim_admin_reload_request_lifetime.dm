/// Actual native request lifetime/completion; no SQL or global configuration mutation.
/datum/interim_admin_reload_observer
	var/completions = 0
	var/endings = 0
	var/seen_outcome
	var/mob/seen_user
	var/list/seen_rows
	var/seen_no_update

/datum/interim_admin_reload_observer/proc/done(datum/act/request/A)
	var/datum/request/admin_reload/request = A.request
	endings++
	seen_outcome = request.outcome
	if(!A.answer)
		return
	completions++
	seen_user = request.initiator()
	seen_rows = request.answer_value
	seen_no_update = request.no_update

/datum/unit_test/interim_admin_reload_request_lifetime

/datum/unit_test/interim_admin_reload_request_lifetime/Run()
	test_driver_begin()
	for(var/delete_initiator in list(FALSE, TRUE))
		var/datum/interim_admin_reload_observer/owner = allocate(/datum/interim_admin_reload_observer)
		var/mob/living/carbon/human/initiator = allocate(/mob/living/carbon/human)
		var/mob/living/carbon/human/independent = allocate(/mob/living/carbon/human)
		var/datum/request/admin_reload/request = open_request(owner, /datum/request/admin_reload, TYPE_PROC_REF(/datum/interim_admin_reload_observer, done), asker = initiator, no_update = TRUE)
		TEST_ASSERT(request.is_open(), "The actual reload context must open")
		TEST_ASSERT_EQUAL(request.timeout, 10 MINUTES, "The default deadline covers both five-minute backend budgets")
		TEST_ASSERT((request in SSrequests.open), "The actual request registry must retain the context")
		TEST_ASSERT_EQUAL(request.initiator(), initiator, "The request initially identifies its exact initiating mob")
		if(delete_initiator)
			qdel(initiator)
			TEST_ASSERT(QDELETED(initiator), "The initiating mob is genuinely deleted")
		test_time(2 SECONDS)
		TEST_ASSERT(request.is_open(), "The registry sweep must keep reload runnable with its live owner")
		TEST_ASSERT((request in SSrequests.open), "An initiating mob's deletion cannot unregister the global reload")
		TEST_ASSERT_EQUAL(owner.completions, 0, "No completion occurred during the sweep")
		TEST_ASSERT_EQUAL(request.initiator(), delete_initiator ? null : initiator, "Recipient resolution keeps the live original or clears the deleted original")
		TEST_ASSERT(request.initiator() != independent, "The unrelated live mob cannot become the notice recipient")
		var/list/rank_rows = list(list("test-rank", R_ADMIN, 0, 0))
		var/list/admin_rows = list(list("test-admin", "test-rank", "test-feedback"))
		request.rank_rows = rank_rows
		// Deliver the existing final SQL callback's real shape, exercising its actual request_end path.
		request.admins_arrived(list("rows" = admin_rows), null)
		TEST_ASSERT_EQUAL(owner.completions, 1, "The actual completion callback must run exactly once")
		TEST_ASSERT_EQUAL(owner.seen_user, delete_initiator ? null : initiator, "Completion preserves the original requester identity without redirection")
		TEST_ASSERT_EQUAL(owner.seen_no_update, TRUE, "The original reload option survives completion")
		TEST_ASSERT_EQUAL(owner.seen_rows["ranks"], rank_rows, "The original rank-row list reaches completion intact")
		TEST_ASSERT_EQUAL(owner.seen_rows["admins"], admin_rows, "The original admin-row list reaches completion intact")
		TEST_ASSERT(!(request in SSrequests.open), "Completion unregisters the actual reload request")
		TEST_ASSERT(QDELETED(request), "Completion disposes the retained context")
		TEST_ASSERT(!QDELETED(owner) && !QDELETED(independent), "The live owner and unrelated mob survive completion")

	var/datum/interim_admin_reload_observer/timeout_owner = allocate(/datum/interim_admin_reload_observer)
	var/datum/request/admin_reload/expiring = open_request(timeout_owner, /datum/request/admin_reload, TYPE_PROC_REF(/datum/interim_admin_reload_observer, done), timeout = 2 SECONDS)
	TEST_ASSERT(expiring.is_open() && (expiring in SSrequests.open), "A configured native timeout starts with a registered live context")
	test_time(1 SECOND)
	TEST_ASSERT(expiring.is_open(), "The actual context survives before its configured deadline")
	TEST_ASSERT_EQUAL(timeout_owner.endings, 0, "No early timeout callback occurred")
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(timeout_owner.endings, 1, "The actual deadline calls the owner exactly once")
	TEST_ASSERT_EQUAL(timeout_owner.seen_outcome, REQ_TIMED_OUT, "The deadline ends with the native timeout outcome")
	TEST_ASSERT_EQUAL(timeout_owner.completions, 0, "A timeout supplies no answer and does not complete a reload")
	TEST_ASSERT(!(expiring in SSrequests.open), "Timeout unregisters the abandoned context")
	TEST_ASSERT(QDELETED(expiring), "Timeout disposes the abandoned context")
	TEST_ASSERT(!QDELETED(timeout_owner), "Timeout preserves its actual live owner")
