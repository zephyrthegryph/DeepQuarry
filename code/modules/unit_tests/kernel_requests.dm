/// Requests, chunked jobs and safe_call (code/engine/kernel/requests.dm, jobs.dm, safe.dm; doc/rewrite/final_api.html section 2).

/// A prompt kind with one typed field.
/datum/prompt/e6_probe
	var/role

/// The owner of a request or a job: records what its handlers saw.
/datum/e6_probe_owner
	var/list/outcomes = list()
	var/list/answers = list()
	var/still_open = TRUE
	var/steps = 0
	var/steps_wanted = 5
	var/finished = 0
	var/list/dts = list()

/datum/e6_probe_owner/proc/done(datum/act/request/A)
	outcomes += A.request.outcome
	answers += A.request.value
	if(A.answer)
		answers += "answer:[A.answer.type]"
	return

/datum/e6_probe_owner/proc/is_open(datum/request/R)
	return still_open

/datum/e6_probe_owner/proc/chunk(datum/act/timer/A)
	steps++
	dts += A.dt
	return steps >= steps_wanted ? JOB_DONE : JOB_MORE

/datum/e6_probe_owner/proc/forgetful_step(datum/act/timer/A)
	steps++
	return

/datum/e6_probe_owner/proc/job_done(datum/act/timer/A)
	finished++

/datum/e6_probe_owner/proc/explode(arg)
	CRASH("deliberate safe_call fault")

/datum/e6_probe_owner/proc/echo(arg)
	return "echo:[arg]"

/datum/e6_probe_owner/proc/call_safely(proc_ref, arg)
	return safe_call(proc_ref, arg)

/datum/unit_test/kernel_request_answered

/datum/unit_test/kernel_request_answered/Run()
	test_driver_begin()
	var/datum/e6_probe_owner/owner = allocate(/datum/e6_probe_owner)
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human)
	var/datum/request/R = open_request(owner, /datum/prompt/e6_probe, TYPE_PROC_REF(/datum/e6_probe_owner, done), valid = TYPE_PROC_REF(/datum/e6_probe_owner, is_open), answerer = actor, role = "tester")
	TEST_ASSERT_NOTNULL(R, "request() opens a request")
	var/datum/prompt/e6_probe/P = R
	TEST_ASSERT_EQUAL(P.role, "tester", "named arguments set the request's typed fields")
	TEST_ASSERT(R.is_open(), "it is open")
	TEST_ASSERT_NULL(R.outcome, "with no outcome yet")
	test_answer(actor, 42)
	TEST_ASSERT(!R.is_open(), "an answer closes it")
	TEST_ASSERT_EQUAL(R.outcome, REQ_ANSWERED, "as answered")
	TEST_ASSERT_EQUAL(R.value, 42, "carrying the answer")
	TEST_ASSERT_EQUAL(length(owner.outcomes), 1, "the handler ran once")
	TEST_ASSERT_EQUAL(owner.outcomes[1], REQ_ANSWERED, "and saw the outcome")
	TEST_ASSERT_EQUAL(owner.answers[1], 42, "and the answer")
	TEST_ASSERT_EQUAL(owner.answers[2], "answer:/datum/prompt/e6_probe", "A.answer is the answered request")
	TEST_ASSERT_NULL(test_answer(actor, 7), "a second answer finds nothing open")
	TEST_ASSERT_EQUAL(length(owner.outcomes), 1, "and the handler does not run again")

	// valid() is asked when the answer arrives: a request that is no longer wanted ends cancelled.
	owner.still_open = FALSE
	var/datum/request/stale = open_request(owner, /datum/prompt/e6_probe, TYPE_PROC_REF(/datum/e6_probe_owner, done), valid = TYPE_PROC_REF(/datum/e6_probe_owner, is_open), answerer = actor)
	test_answer(actor, 1)
	TEST_ASSERT_EQUAL(stale.outcome, REQ_CANCELLED, "an answer that fails valid() ends as REQ_CANCELLED")

	// An outcome of its own: test_answer(outcome =) ends the request without an answer.
	owner.still_open = TRUE
	var/datum/request/ended = open_request(owner, /datum/prompt/e6_probe, TYPE_PROC_REF(/datum/e6_probe_owner, done), answerer = actor)
	test_answer(actor, null, REQ_CANCELLED)
	TEST_ASSERT_EQUAL(ended.outcome, REQ_CANCELLED, "REQ_CANCELLED ends it as cancelled")
	TEST_ASSERT_NULL(owner.answers[length(owner.answers)], "with no answer")
	test_driver_end()

/datum/unit_test/kernel_request_ends

/datum/unit_test/kernel_request_ends/Run()
	test_driver_begin()
	var/datum/e6_probe_owner/owner = allocate(/datum/e6_probe_owner)
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human)
	// A timeout fires under test_time.
	var/datum/request/slow = open_request(owner, /datum/prompt/e6_probe, TYPE_PROC_REF(/datum/e6_probe_owner, done), answerer = actor, timeout = 5 SECONDS)
	test_time(4 SECONDS)
	TEST_ASSERT(slow.is_open(), "it is still open inside its timeout")
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(slow.outcome, REQ_TIMED_OUT, "and ends REQ_TIMED_OUT when the timeout passes")
	TEST_ASSERT_EQUAL(owner.outcomes[length(owner.outcomes)], REQ_TIMED_OUT, "its handler saw it")
	// An answer before the timeout cancels the timer: no second end.
	var/before = length(owner.outcomes)
	var/datum/request/quick = open_request(owner, /datum/prompt/e6_probe, TYPE_PROC_REF(/datum/e6_probe_owner, done), answerer = actor, timeout = 5 SECONDS)
	test_answer(actor, "yes")
	test_time(10 SECONDS)
	TEST_ASSERT_EQUAL(length(owner.outcomes) - before, 1, "an answered request does not time out afterwards")
	TEST_ASSERT_EQUAL(quick.outcome, REQ_ANSWERED, "and stays answered")
	// A dead owner ends the request cancelled (the system's sweep: here at its own cadence under the test clock).
	var/datum/e6_probe_owner/doomed = new
	var/datum/request/orphan = open_request(doomed, /datum/prompt/e6_probe, TYPE_PROC_REF(/datum/e6_probe_owner, done), answerer = actor)
	qdel(doomed)
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(orphan.outcome, REQ_CANCELLED, "a request whose owner died ends cancelled")
	// An unknown field is a programming error, caught where it is written.
	var/crashed
	try
		open_request(owner, /datum/prompt/e6_probe, TYPE_PROC_REF(/datum/e6_probe_owner, done), nonsense = 1)
	catch(var/exception/e)
		crashed = "[e.name]"
	TEST_ASSERT(crashed, "a field the kind does not have is refused")
	test_driver_end()

/datum/unit_test/kernel_job_chunks

/datum/unit_test/kernel_job_chunks/Run()
	test_driver_begin()
	var/datum/e6_probe_owner/owner = allocate(/datum/e6_probe_owner)
	var/datum/kernel_job/J = job(owner, TYPE_PROC_REF(/datum/e6_probe_owner, chunk), budget = 100, then = TYPE_PROC_REF(/datum/e6_probe_owner, job_done))
	TEST_ASSERT_NOTNULL(J, "job() starts a job")
	TEST_ASSERT_EQUAL(owner.steps, 0, "nothing runs before the kernel's pass")
	test_time(1)
	TEST_ASSERT_EQUAL(owner.steps, 5, "steps return JOB_MORE until JOB_DONE, inside the budget of one pass")
	TEST_ASSERT_EQUAL(owner.finished, 1, "then() ran once when the job was done")
	test_time(3)
	TEST_ASSERT_EQUAL(owner.steps, 5, "a finished job runs no more")
	TEST_ASSERT(!(J in SSkernel_jobs.jobs), "and leaves the system")

	// A job dies with its owner.
	var/datum/e6_probe_owner/doomed = new
	doomed.steps_wanted = 100
	var/datum/kernel_job/orphan = job(doomed, TYPE_PROC_REF(/datum/e6_probe_owner, chunk), budget = 100)
	qdel(doomed)
	test_time(2)
	TEST_ASSERT(!(orphan in SSkernel_jobs.jobs), "a job whose owner died is dropped")
	test_driver_end()

/// A step that returns nothing is a bug the system reports and drops, rather than runs for ever.
/datum/unit_test/kernel_job_forgetful_step

/datum/unit_test/kernel_job_forgetful_step/Run()
	test_driver_begin()
	var/datum/e6_probe_owner/owner = allocate(/datum/e6_probe_owner)
	var/datum/controller/kernel/K = kernel()
	set_var(K, "expect_errors", TRUE)
	var/faults_before = length(K.fault_log)
	var/datum/kernel_job/J = job(owner, TYPE_PROC_REF(/datum/e6_probe_owner, forgetful_step), budget = 100)
	test_time(2)
	TEST_ASSERT_EQUAL(length(K.fault_log) - faults_before, 1, "the mistake is reported once")
	TEST_ASSERT_EQUAL(owner.steps, 1, "the step ran once")
	TEST_ASSERT(!(J in SSkernel_jobs.jobs), "and the job was dropped")
	test_driver_end()

/datum/unit_test/kernel_safe_call

/datum/unit_test/kernel_safe_call/Run()
	var/datum/e6_probe_owner/owner = allocate(/datum/e6_probe_owner)
	var/datum/result/fine = owner.call_safely(TYPE_PROC_REF(/datum/e6_probe_owner, echo), "x")
	TEST_ASSERT(fine.ok, "a call that returns is ok")
	TEST_ASSERT_EQUAL(fine.value, "echo:x", "with its value")
	var/datum/result/broke = owner.call_safely(TYPE_PROC_REF(/datum/e6_probe_owner, explode), "x")
	TEST_ASSERT(!broke.ok, "a call that runtimes is not ok")
	TEST_ASSERT_NULL(broke.value, "and has no value")
	TEST_ASSERT(findtext(broke.error, "deliberate safe_call fault"), "its error names the fault: [broke.error]")
	TEST_ASSERT_EQUAL(try_parse_json("{\"a\": 1}")["a"], 1, "try_parse_json parses well-formed text")
	TEST_ASSERT_NULL(try_parse_json("{not json"), "and returns null for malformed text")
	TEST_ASSERT_NULL(try_parse_json(""), "and for nothing")
