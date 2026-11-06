// Opening a tgui window never sleeps its caller, and a file is asked for like any other prompt (doc/rewrite/proposals/nonblocking_ui.md).

/// A window with a stand-in transport: the probes it would send are recorded (and answered by the test), the messages it would write are collected.
/datum/tgui_window/dq_stub
	var/list/probes = list()
	var/list/sent = list()

/datum/tgui_window/dq_stub/reachable()
	return TRUE

/datum/tgui_window/dq_stub/open_probe(control_id, handler)
	probes += list(list(control_id, handler))

/datum/tgui_window/dq_stub/deliver(message)
	sent += message

/datum/unit_test/tgui_window_open_does_not_sleep
/datum/unit_test/tgui_window_open_does_not_sleep/Run()
	test_driver_begin()
	var/datum/tgui_window/dq_stub/W = allocate(/datum/tgui_window/dq_stub, null, TGUI_WINDOW_ID(1), TRUE)
	W.initialize(strict_mode = TRUE)
	// initialize() has returned with the open still waiting on the client.
	TEST_ASSERT(W.opening, "the open is in progress after initialize() returns")
	TEST_ASSERT_EQUAL(W.status, TGUI_WINDOW_LOADING, "the window is loading")
	TEST_ASSERT_EQUAL(length(W.probes), 1, "one probe is out: does the pooled window exist")
	TEST_ASSERT_EQUAL(W.probes[1][1], TGUI_WINDOW_ID(1), "it asks about the window's own id")
	var/document = W.document_id
	W.send_message("update", list("hello" = "world"))
	TEST_ASSERT_EQUAL(length(W.message_queue), 1, "an update sent meanwhile waits in the queue")
	TEST_ASSERT_EQUAL(length(W.sent), 0, "and nothing is written to the page")
	W.open_probe_exists("MAIN", document)
	TEST_ASSERT_EQUAL(length(W.probes), 2, "the window existing leads to the shell probe")
	W.open_probe_shell("", document)
	TEST_ASSERT_EQUAL(length(W.probes), 3, "the page is browsed and the last probe goes out")
	// The page reports in before the last probe answered: it is READY but the output control is not known yet, so nothing is flushed.
	W.became_ready()
	TEST_ASSERT_EQUAL(W.status, TGUI_WINDOW_READY, "the page's ready is taken")
	TEST_ASSERT_EQUAL(length(W.sent), 0, "the queue is still held while the last probe is out")
	W.send_message("update", list("second" = 1))
	TEST_ASSERT_EQUAL(length(W.sent), 0, "a message sent in that gap is held too")
	W.open_probe_browser("BROWSER", document)
	TEST_ASSERT(!W.opening, "the last probe ends the open")
	TEST_ASSERT(W.is_browser, "and decides the output control")
	TEST_ASSERT_EQUAL(length(W.sent), 2, "both held messages are delivered")
	TEST_ASSERT_NULL(W.message_queue, "and the queue is empty")
	TEST_ASSERT(findtext(W.sent[1], "hello"), "in the order they were sent")
	W.send_message("update", list("third" = 1))
	TEST_ASSERT_EQUAL(length(W.sent), 3, "afterwards a message goes straight through")
	test_time(TGUI_OPEN_PROBE_TIMEOUT + 1 SECOND)
	TEST_ASSERT_EQUAL(W.status, TGUI_WINDOW_READY, "the finished open's timeout was cancelled")
	test_driver_end()

/datum/unit_test/tgui_window_open_stale_and_timeout
/datum/unit_test/tgui_window_open_stale_and_timeout/Run()
	test_driver_begin()
	// A late answer of a superseded page is ignored.
	var/datum/tgui_window/dq_stub/W = allocate(/datum/tgui_window/dq_stub, null, TGUI_WINDOW_ID(2), TRUE)
	W.initialize()
	var/old_document = W.document_id
	W.initialize()
	TEST_ASSERT(W.document_id != old_document, "a second initialize() is a new page")
	W.open_probe_exists("MAIN", old_document)
	TEST_ASSERT_EQUAL(length(W.probes), 2, "the old page's answer starts nothing")
	// A probe that never answers: the open is abandoned and the shell is free again.
	W.send_message("update", list("lost" = 1))
	test_time(TGUI_OPEN_PROBE_TIMEOUT + 1 SECOND)
	TEST_ASSERT(!W.opening, "the open timed out")
	TEST_ASSERT_EQUAL(W.status, TGUI_WINDOW_CLOSED, "the shell is closed and can be handed out again")
	TEST_ASSERT_NULL(W.message_queue, "its held messages are dropped")
	var/new_document = W.document_id
	W.open_probe_exists("MAIN", new_document)
	TEST_ASSERT_EQUAL(length(W.probes), 2, "an answer after the timeout starts nothing")
	// Closing while the open is waiting ends it the same way.
	var/datum/tgui_window/dq_stub/C = allocate(/datum/tgui_window/dq_stub, null, TGUI_WINDOW_ID(3), TRUE)
	C.initialize()
	var/closed_document = C.document_id
	C.close(can_be_suspended = FALSE)
	TEST_ASSERT(!C.opening, "close() ends an open in progress")
	TEST_ASSERT_EQUAL(C.status, TGUI_WINDOW_CLOSED, "the window is closed")
	C.open_probe_exists("MAIN", closed_document)
	TEST_ASSERT_EQUAL(length(C.probes), 1, "and a late answer starts nothing")
	test_driver_end()

/// The owner of a file prompt: records what its handler saw.
/datum/dq_file_prompt_owner
	var/list/outcomes = list()
	var/list/values = list()

/datum/dq_file_prompt_owner/proc/done(datum/act/request/A)
	outcomes += A.request.outcome
	values += list(A.request.value)

/datum/unit_test/prompt_file_answers_and_refuses
/datum/unit_test/prompt_file_answers_and_refuses/Run()
	test_driver_begin()
	var/datum/dq_file_prompt_owner/owner = allocate(/datum/dq_file_prompt_owner)
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human)
	var/datum/request/R = open_request(owner, /datum/prompt/file, TYPE_PROC_REF(/datum/dq_file_prompt_owner, done), answerer = actor, extensions = list("js"), max_bytes = 100000)
	TEST_ASSERT_NOTNULL(R, "a file prompt opens")
	test_answer(actor, 5)
	TEST_ASSERT(R.is_open(), "something that is not a file is refused and the question stays open")
	test_answer(actor, 'html/shock.js')
	TEST_ASSERT(!R.is_open(), "a file of an accepted extension answers it")
	TEST_ASSERT_EQUAL(R.outcome, REQ_ANSWERED, "as answered")
	TEST_ASSERT(isfile(R.value), "the answer is the file")
	TEST_ASSERT_EQUAL(length(owner.outcomes), 1, "the handler ran once")
	// An extension the prompt does not accept, and a file over the size cap, are refused.
	var/datum/request/picky = open_request(owner, /datum/prompt/file, TYPE_PROC_REF(/datum/dq_file_prompt_owner, done), answerer = actor, extensions = list("png"))
	test_answer(actor, 'html/shock.js')
	TEST_ASSERT(picky.is_open(), "a file of another extension is refused")
	test_answer(actor, null, REQ_CANCELLED)
	TEST_ASSERT_EQUAL(picky.outcome, REQ_CANCELLED, "a dismissed dialog cancels it")
	var/datum/request/tiny = open_request(owner, /datum/prompt/file, TYPE_PROC_REF(/datum/dq_file_prompt_owner, done), answerer = actor, max_bytes = 1)
	test_answer(actor, 'html/shock.js')
	TEST_ASSERT(tiny.is_open(), "a file over the size cap is refused")
	test_answer(actor, null, REQ_CANCELLED)
	test_driver_end()
