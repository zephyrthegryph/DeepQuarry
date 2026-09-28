// I/O inside prompt flows (flow_io.dm), DX-exec (dx_exec.dm) and the prompts moved onto
// om_prompt in the e-io2 sweep. The fake I/O kind /datum/om/io/test (dq_om_io_tests.dm)
// stands in for rust-g, so no database, network or client is needed.

/// A flow entry that makes two I/O reads and logs each run and the final answers.
/datum/om_test_entity/proc/flow_two_reads(tag)
	if(!GLOB.prompt_flow)
		return prompt_flow(src, PROC_REF(flow_two_reads), args)
	log += "run:[tag]"
	var/list/first = flow_io_answer(/datum/om/io/test, list("first"))
	var/list/second = flow_io_answer(/datum/om/io/test, list(tag == "fail" ? "fail" : "second"))
	if(second["error"])
		log += "error:[second["error"]]"
		return
	log += "done:[first["value"]]:[second["value"]]"

/datum/unit_test/om/flow_io_reruns_on_each_answer

/datum/unit_test/om/flow_io_reruns_on_each_answer/run_om(list/made)
	var/datum/om_test_entity/E = entity(made)
	TEST_ASSERT_NULL(E.flow_two_reads("a"), "the flow unwinds at its first read")
	TEST_ASSERT_NULL(GLOB.prompt_flow, "and leaves no flow running")
	TEST_ASSERT_EQUAL(E.log.Join(","), "run:a", "it ran once, up to the read")
	TEST_ASSERT_EQUAL(om_io_count(/datum/om/io/test), 1, "one job is in flight")
	scheduler_advance(1)
	TEST_ASSERT_EQUAL(E.log.Join(","), "run:a,run:a", "the first answer re-ran it, up to the second read")
	scheduler_advance(1)
	TEST_ASSERT_EQUAL(E.log.Join(","), "run:a,run:a,done:first:second", "the second answer finished it with both stored answers")
	TEST_ASSERT(!om_io_count(), "no jobs left")
	TEST_ASSERT(!length(GLOB.om_rerun_answers), "the re-run's answers are cleared")

/datum/unit_test/om/flow_io_error_is_an_answer

/datum/unit_test/om/flow_io_error_is_an_answer/run_om(list/made)
	var/datum/om_test_entity/E = entity(made)
	E.flow_two_reads("fail")
	scheduler_advance(1)
	scheduler_advance(1)
	TEST_ASSERT_EQUAL(E.log.Join(","), "run:fail,run:fail,error:failed", "a failed job reaches the flow as its error")

/datum/unit_test/om/flow_io_dropped_when_asker_gone

/datum/unit_test/om/flow_io_dropped_when_asker_gone/run_om(list/made)
	var/datum/om_test_entity/E = entity(made)
	var/list/witness = E.log
	E.flow_two_reads("b")
	qdel(E)
	scheduler_advance(1)
	scheduler_advance(1)
	TEST_ASSERT_EQUAL(witness.Join(","), "run:b", "a deleted asker's flow never runs again")

/// dx_exec callback for the tests.
/datum/om_test_entity/proc/dx_done(result, tag)
	log += "[tag]:[result]"

/datum/unit_test/om/dx_exec_delivers_weakly

/datum/unit_test/om/dx_exec_delivers_weakly/run_om(list/made)
	var/datum/om_test_entity/E = entity(made)
	dx_exec_deliver(dx_exec_wrap(E), "winget", "800x600", /datum/om_test_entity/proc/dx_done, list("size"))
	TEST_ASSERT_EQUAL(E.log.Join(","), "size:800x600", "the answer reaches the owner's callback with its context")
	var/datum/om_test_entity/gone = entity(made)
	var/list/wrapped_gone = dx_exec_wrap(gone)
	var/list/wrapped_ctx = list(dx_exec_wrap(E))
	qdel(gone)
	dx_exec_deliver(wrapped_gone, "winget", "x", /datum/om_test_entity/proc/dx_done, list("late"))
	dx_exec_deliver(dx_exec_wrap(E), "winget", "x", /datum/om_test_entity/proc/dx_done, list("ctx") + wrapped_ctx)
	TEST_ASSERT_EQUAL(E.log.Join(","), "size:800x600,ctx:x", "a deleted owner drops the answer; a live context arg is resolved")
	TEST_ASSERT(!dx_winget(E, null, "mapwindow", "size", /datum/om_test_entity/proc/dx_done), "a round trip needs a client")

/// A picker ability whose one candidate is set by the test. No id: it stays out of the
/// ability and keybind registries.
/datum/interaction/ability/picker/test_flow
	name = "Test pick"
	var/datum/test_candidate

/datum/interaction/ability/picker/test_flow/candidates(mob/living/actor)
	return test_candidate ? list(test_candidate) : list()

/datum/unit_test/om/ability_picker_asks_without_waiting

/datum/unit_test/om/ability_picker_asks_without_waiting/run_om(list/made)
	sched.test_prompts = list()
	var/datum/om_test_entity/actor = entity(made)
	var/datum/om_test_entity/candidate = entity(made)
	var/datum/interaction/ability/picker/test_flow/A = new
	made += A
	A.test_candidate = candidate
	TEST_ASSERT_NULL(A.pick_target(actor), "pick_target() asks and returns at once")
	TEST_ASSERT_EQUAL(length(sched.test_prompts), 1, "the pick is an om_prompt")
	var/datum/om/prompt/choice/P = sched.test_prompts[1]
	TEST_ASSERT(istype(P, /datum/om/prompt/choice), "a list of the candidates")
	TEST_ASSERT(candidate in P.choices, "offering the candidates")

/datum/unit_test/om/rainbow_crayon_asks_colours

/datum/unit_test/om/rainbow_crayon_asks_colours/run_om(list/made)
	sched.test_prompts = list()
	var/datum/om_test_entity/user = entity(made)
	var/obj/item/pen/crayon/rainbow/crayon = new
	made += crayon
	crayon.ask_rainbow_colour(user, "Crayon colour", "Crayon shade colour")
	TEST_ASSERT_EQUAL(length(sched.test_prompts), 1, "the colours are asked with om_prompt, not a blocking picker")
	var/datum/om/prompt/P = sched.test_prompts[1]
	TEST_ASSERT(istype(P, /datum/om/prompt/color/crayon_colour), "a colour prompt for the main colour first")
