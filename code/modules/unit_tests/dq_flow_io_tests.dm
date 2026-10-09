// Native I/O continuations and DX-exec. The fake backend uses the real transport lane,
// so these tests need no database, network or connected client.

/datum/io/test_transport
	var/payload

/datum/io/test_transport/begin()
	io_job(src, /datum/io_backend/test, payload, PROC_REF(received))

/datum/io/test_transport/proc/received(value, error)
	if(!is_open())
		return
	if(error)
		last_error = error
		request_end(src, REQ_TRANSPORT_FAILED, null)
	else
		request_end(src, REQ_ANSWERED, value)

/datum/io_test_entity/proc/start_two_reads(tag)
	LAZYADD(log, "start:[tag]")
	return open_request(src, /datum/io/test_transport, PROC_REF(first_read), payload = "first", captured = list("tag" = tag))

/datum/io_test_entity/proc/first_read(datum/act/request/A)
	if(!A.answer)
		LAZYADD(log, "error:[A.request.last_error]")
		return
	var/tag = A.answer.captured["tag"]
	LAZYADD(log, "first:[A.answer.value]")
	open_request(src, /datum/io/test_transport, PROC_REF(second_read), payload = tag == "fail" ? "fail" : "second", captured = list("first" = A.answer.value))

/datum/io_test_entity/proc/second_read(datum/act/request/A)
	if(!A.answer)
		LAZYADD(log, "error:[A.request.last_error]")
		return
	LAZYADD(log, "done:[A.answer.captured["first"]]:[A.answer.value]")

/datum/unit_test/io_transport/two_reads_continue_once

/datum/unit_test/io_transport/two_reads_continue_once/run_io()
	var/datum/io_test_entity/E = allocate(/datum/io_test_entity)
	var/datum/io/test_transport/R = E.start_two_reads("a")
	TEST_ASSERT(R && R.is_open(), "the native first request opens without waiting")
	TEST_ASSERT_EQUAL(jointext(E.log || list(), ","), "start:a", "the effect prefix runs once before I/O")
	TEST_ASSERT_EQUAL(io_job_count(/datum/io_backend/test), 1, "one job is in flight")
	test_time(0.1 SECONDS)
	TEST_ASSERT_EQUAL(jointext(E.log || list(), ","), "start:a,first:first", "the first completion opens the second request without replaying the prefix")
	test_time(0.1 SECONDS)
	TEST_ASSERT_EQUAL(jointext(E.log || list(), ","), "start:a,first:first,done:first:second", "both real backend values reach the terminal continuation")
	TEST_ASSERT(!io_job_count(), "no jobs remain")

/datum/unit_test/io_transport/read_error_is_transport_failure

/datum/unit_test/io_transport/read_error_is_transport_failure/run_io()
	var/datum/io_test_entity/E = allocate(/datum/io_test_entity)
	E.start_two_reads("fail")
	test_time(0.1 SECONDS)
	test_time(0.1 SECONDS)
	TEST_ASSERT_EQUAL(jointext(E.log || list(), ","), "start:fail,first:first,error:failed", "the failed backend produces the original error without a success tail")
	TEST_ASSERT(!io_job_count(), "the failed job leaves the queue")

/datum/unit_test/io_transport/read_dropped_when_owner_gone

/datum/unit_test/io_transport/read_dropped_when_owner_gone/run_io()
	var/datum/io_test_entity/E = allocate(/datum/io_test_entity)
	E.start_two_reads("b")
	var/list/witness = E.log
	TEST_ASSERT(islist(witness), "the actual prefix creates its observable log")
	qdel(E)
	test_time(0.1 SECONDS)
	test_time(0.1 SECONDS)
	TEST_ASSERT_EQUAL(witness.Join(","), "start:b", "a deleted owner never starts the second request or a success tail")
	TEST_ASSERT(!io_job_count(), "the orphaned transport answer is drained")

/// dx_exec callback for the tests.
/datum/io_test_entity/proc/dx_done(result, tag, datum/io_test_entity/context)
	LAZYADD(log, "[tag]:[result]")
	if(context)
		LAZYADD(context.log, "[tag] via")

/datum/unit_test/io_transport/dx_exec_delivers_weakly

/datum/unit_test/io_transport/dx_exec_delivers_weakly/run_io()
	var/datum/io_test_entity/E = allocate(/datum/io_test_entity)
	dx_exec_deliver(dx_exec_wrap(E), "winget", "800x600", TYPE_PROC_REF(/datum/io_test_entity, dx_done), list("size"))
	TEST_ASSERT_EQUAL(jointext(E.log || list(), ","), "size:800x600", "the answer reaches the owner's callback with its context")
	var/datum/io_test_entity/gone = allocate(/datum/io_test_entity)
	var/list/wrapped_gone = dx_exec_wrap(gone)
	var/list/wrapped_ctx = list(dx_exec_wrap(E))
	qdel(gone)
	dx_exec_deliver(wrapped_gone, "winget", "x", TYPE_PROC_REF(/datum/io_test_entity, dx_done), list("late"))
	dx_exec_deliver(dx_exec_wrap(E), "winget", "x", TYPE_PROC_REF(/datum/io_test_entity, dx_done), list("ctx") + wrapped_ctx)
	TEST_ASSERT_EQUAL(jointext(E.log || list(), ","), "size:800x600,ctx:x,ctx via", "a deleted owner drops the answer; a live context arg resolves to its real datum")
	dx_exec_deliver(dx_exec_wrap(E), "winget", "late", TYPE_PROC_REF(/datum/io_test_entity, dx_done), list("gone-context", wrapped_gone))
	TEST_ASSERT_EQUAL(jointext(E.log || list(), ","), "size:800x600,ctx:x,ctx via", "a deleted context drops the answer without calling the live owner")
	TEST_ASSERT(!dx_winget(E, null, "mapwindow", "size", TYPE_PROC_REF(/datum/io_test_entity, dx_done)), "a round trip needs a client")

/datum/unit_test/om/rainbow_crayon_asks_colours

/datum/unit_test/om/rainbow_crayon_asks_colours/Run()
	test_driver_begin()
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	user.enable_godmode()
	var/obj/item/pen/crayon/rainbow/crayon = allocate(/obj/item/pen/crayon/rainbow, run_loc_floor_bottom_left)
	TEST_ASSERT(user.put_in_active_hand(crayon), "the real crayon enters the actor's hand")
	user.next_click = 0
	test_click(user, crayon, crayon)
	test_drain()
	var/datum/request/request = SSrequests.open_for(user)
	TEST_ASSERT(istype(request, /datum/prompt/color/crayon_colour), "real held use asks the main native color request")
	var/datum/prompt/color/crayon_colour/prompt = request
	TEST_ASSERT(!prompt.shade, "the first request selects main color")
	TEST_ASSERT_EQUAL(prompt.default, crayon.colour, "main request starts with the actual main color")
	test_answer(user, "#102030")
	TEST_ASSERT_EQUAL(crayon.colour, "#102030", "the accepted main answer commits its actual color")
	request = SSrequests.open_for(user)
	TEST_ASSERT_NOTNULL(request, "accepted main color opens the actual shade request")
	prompt = request
	TEST_ASSERT(prompt.shade, "the second request selects shade")
	TEST_ASSERT_EQUAL(prompt.default, crayon.shadeColour, "shade request starts with the current shade")
	test_answer(user, "#405060")
	TEST_ASSERT_EQUAL(crayon.shadeColour, "#405060", "the accepted shade answer commits its actual color")
	TEST_ASSERT_NULL(SSrequests.open_for(user), "the two accepted answers finish the chain")

	user.next_click = 0
	test_click(user, crayon, crayon)
	test_drain()
	request = SSrequests.open_for(user)
	TEST_ASSERT_NOTNULL(request, "main color opens for the invalid-answer cancellation control")
	test_answer(user, "not-a-color")
	TEST_ASSERT_EQUAL(SSrequests.open_for(user), request, "an invalid color leaves the same request open")
	TEST_ASSERT(request.last_error, "the invalid answer actually records its rejection")
	test_answer(user, null, REQ_CANCELLED)
	prompt = SSrequests.open_for(user)
	TEST_ASSERT_NOTNULL(prompt, "explicit cancel after an invalid answer still opens shade")
	TEST_ASSERT(prompt.shade, "the continuation after rejected input selects shade")
	test_answer(user, null, REQ_CANCELLED)
	TEST_ASSERT_EQUAL(crayon.colour, "#102030", "invalid answer and explicit cancel retain main color")
	TEST_ASSERT_EQUAL(crayon.shadeColour, "#405060", "shade cancellation retains shade color after rejected input")
	TEST_ASSERT_NULL(SSrequests.open_for(user), "the cancellation chain after rejected input finishes")

	user.next_click = 0
	test_click(user, crayon, crayon)
	test_drain()
	TEST_ASSERT_NOTNULL(SSrequests.open_for(user), "a new held use opens main color")
	user.drop_from_inventory(crayon, run_loc_floor_bottom_left)
	TEST_ASSERT_EQUAL(crayon.loc, run_loc_floor_bottom_left, "the crayon really leaves the actor before cancel")
	test_answer(user, null, REQ_CANCELLED)
	request = SSrequests.open_for(user)
	TEST_ASSERT_NOTNULL(request, "explicit main cancel still opens shade after dropping, as the old cancellation protocol did")
	prompt = request
	TEST_ASSERT(prompt.shade, "cancel continues specifically to shade")
	TEST_ASSERT_EQUAL(crayon.colour, "#102030", "main cancellation retains main color")
	test_answer(user, null, REQ_CANCELLED)
	TEST_ASSERT_EQUAL(crayon.shadeColour, "#405060", "shade cancellation retains shade color")
	TEST_ASSERT_NULL(SSrequests.open_for(user), "shade cancellation finishes without another prompt")

	TEST_ASSERT(user.put_in_active_hand(crayon), "the actor actually picks the crayon back up")
	user.next_click = 0
	test_click(user, crayon, crayon)
	test_drain()
	TEST_ASSERT_NOTNULL(SSrequests.open_for(user), "another main request opens for the carried recheck control")
	user.drop_from_inventory(crayon, run_loc_floor_bottom_left)
	TEST_ASSERT_EQUAL(crayon.loc, run_loc_floor_bottom_left, "the crayon really leaves before the attempted answer")
	test_answer(user, "#778899")
	TEST_ASSERT_EQUAL(crayon.colour, "#102030", "failed carried answer retains main color")
	TEST_ASSERT_EQUAL(crayon.shadeColour, "#405060", "failed carried answer retains shade color")
	TEST_ASSERT_NULL(SSrequests.open_for(user), "failed carried answer does not masquerade as explicit cancel and open shade")
