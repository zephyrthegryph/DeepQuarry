// I/O inside prompt flows (flow_io.dm), DX-exec (dx_exec.dm) and the prompts moved onto
// om_prompt in the e-io2 sweep. The fake I/O kind /datum/io_backend/test (dq_om_io_tests.dm)
// stands in for rust-g, so no database, network or client is needed.

/// A flow entry that makes two I/O reads and logs each run and the final answers.
/datum/om_test_entity/proc/flow_two_reads(tag)
	if(!GLOB.prompt_flow)
		return prompt_flow(src, PROC_REF(flow_two_reads), args)
	LAZYADD(log, "run:[tag]")
	var/list/first = flow_io_answer(/datum/io_backend/test, list("first"))
	var/list/second = flow_io_answer(/datum/io_backend/test, list(tag == "fail" ? "fail" : "second"))
	if(second["error"])
		LAZYADD(log, "error:[second["error"]]")
		return
	LAZYADD(log, "done:[first["value"]]:[second["value"]]")

/datum/unit_test/om/flow_io_reruns_on_each_answer

/datum/unit_test/om/flow_io_reruns_on_each_answer/run_om(list/made)
	var/datum/om_test_entity/E = entity(made)
	TEST_ASSERT_NULL(E.flow_two_reads("a"), "the flow unwinds at its first read")
	TEST_ASSERT_NULL(GLOB.prompt_flow, "and leaves no flow running")
	TEST_ASSERT_EQUAL(jointext(E.log || list(), ","), "run:a", "it ran once, up to the read")
	TEST_ASSERT_EQUAL(io_job_count(/datum/io_backend/test), 1, "one job is in flight")
	scheduler_advance(0.1) // one I/O pass: each pass answers the jobs started before it
	TEST_ASSERT_EQUAL(jointext(E.log || list(), ","), "run:a,run:a", "the first answer re-ran it, up to the second read")
	scheduler_advance(0.1)
	TEST_ASSERT_EQUAL(jointext(E.log || list(), ","), "run:a,run:a,run:a,done:first:second", "the second answer finished it with both stored answers")
	TEST_ASSERT(!io_job_count(), "no jobs left")
	TEST_ASSERT(!length(GLOB.rerun_answers), "the re-run's answers are cleared")

/datum/unit_test/om/flow_io_error_is_an_answer

/datum/unit_test/om/flow_io_error_is_an_answer/run_om(list/made)
	var/datum/om_test_entity/E = entity(made)
	E.flow_two_reads("fail")
	scheduler_advance(1)
	scheduler_advance(1)
	TEST_ASSERT_EQUAL(jointext(E.log || list(), ","), "run:fail,run:fail,run:fail,error:failed", "a failed job reaches the flow as its error")

/datum/unit_test/om/flow_io_dropped_when_asker_gone

/datum/unit_test/om/flow_io_dropped_when_asker_gone/run_om(list/made)
	var/datum/om_test_entity/E = entity(made)
	E.flow_two_reads("b")
	var/list/witness = E.log
	TEST_ASSERT(islist(witness), "the first flow entry creates the shared log list")
	qdel(E)
	scheduler_advance(1)
	scheduler_advance(1)
	TEST_ASSERT_EQUAL(witness.Join(","), "run:b", "a deleted asker's flow never runs again")

/// dx_exec callback for the tests.
/datum/om_test_entity/proc/dx_done(result, tag)
	LAZYADD(log, "[tag]:[result]")

/datum/unit_test/om/dx_exec_delivers_weakly

/datum/unit_test/om/dx_exec_delivers_weakly/run_om(list/made)
	var/datum/om_test_entity/E = entity(made)
	dx_exec_deliver(dx_exec_wrap(E), "winget", "800x600", /datum/om_test_entity/proc/dx_done, list("size"))
	TEST_ASSERT_EQUAL(jointext(E.log || list(), ","), "size:800x600", "the answer reaches the owner's callback with its context")
	var/datum/om_test_entity/gone = entity(made)
	var/list/wrapped_gone = dx_exec_wrap(gone)
	var/list/wrapped_ctx = list(dx_exec_wrap(E))
	qdel(gone)
	dx_exec_deliver(wrapped_gone, "winget", "x", /datum/om_test_entity/proc/dx_done, list("late"))
	dx_exec_deliver(dx_exec_wrap(E), "winget", "x", /datum/om_test_entity/proc/dx_done, list("ctx") + wrapped_ctx)
	TEST_ASSERT_EQUAL(jointext(E.log || list(), ","), "size:800x600,ctx:x", "a deleted owner drops the answer; a live context arg is resolved")
	TEST_ASSERT(!dx_winget(E, null, "mapwindow", "size", /datum/om_test_entity/proc/dx_done), "a round trip needs a client")

/// A picker ability whose one candidate is set by the test. No id: it stays out of the
/// ability and keybind registries.
/datum/interaction/ability/picker/test_flow
	name = "Test pick"
	var/datum/test_candidate

/datum/interaction/ability/picker/test_flow/candidates(mob/living/actor)
	return test_candidate ? list(test_candidate) : list()

/datum/unit_test/om/ability_picker_asks_without_waiting

/datum/unit_test/om/ability_picker_asks_without_waiting/Run()
	test_driver_begin()
	exercise_native_picker()
	test_driver_end()

/datum/unit_test/om/ability_picker_asks_without_waiting/proc/exercise_native_picker()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	actor.enable_godmode()
	var/mob/living/carbon/human/candidate = allocate(/mob/living/carbon/human, T)
	candidate.enable_godmode()
	var/datum/interaction/ability/picker/test_flow/A = allocate(/datum/interaction/ability/picker/test_flow)
	rel_set(A, nameof(A.test_candidate), candidate)
	TEST_ASSERT_NULL(A.pick_target(actor), "The real picker asks and returns without waiting")
	var/datum/prompt/choice/ability_target/P = SSrequests.open_for(actor)
	TEST_ASSERT(istype(P), "The real picker opened its native choice")
	TEST_ASSERT(candidate in P.choices, "The actual candidate identity is offered")
	test_answer(actor, null, REQ_CANCELLED)
	TEST_ASSERT_NULL(SSrequests.open_for(actor), "Explicit close retires the actual request without attempting the ability")

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
