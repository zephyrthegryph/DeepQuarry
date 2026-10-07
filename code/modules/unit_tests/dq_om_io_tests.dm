// I/O jobs (code/engine/io/jobs.dm). A fake backend stands in for rust-g: its jobs answer when the test says so, so the lane,
// ownership, weak capture, queueing and diagnostics are tested without a database or network.

/// Fake I/O kind: one request arg (the answer). Jobs finish when GLOB.om_io_test_ready says.
/datum/io_backend/test
	name = "test"
	arg_count = 1
	max_active = 2

GLOBAL_LIST_EMPTY(om_io_test_ready)
GLOBAL_VAR_INIT(om_io_test_seq, 0)

/datum/io_backend/test/start(datum/io_job/J)
	if(J.request[1] == "refuse")
		J.preset_error = "refused"
		return null
	var/id = "[++GLOB.om_io_test_seq]"
	GLOB.om_io_test_ready[id] = J.request[1]
	return id

/datum/io_backend/test/check(job_id)
	var/answer = GLOB.om_io_test_ready[job_id]
	if(answer == "wait")
		return RUSTG_JOB_NO_RESULTS_YET
	GLOB.om_io_test_ready -= job_id
	return answer

/datum/io_backend/test/decode(raw)
	if(raw == "fail")
		return list(null, "failed")
	return list(raw, null)

/datum/om_test_entity/proc/io_done(result, error, tag, datum/om_test_entity/other)
	LAZYADD(log, "[tag]:[result]:[error]")
	if(other)
		LAZYADD(other.log, "[tag] via")

/datum/unit_test/om/io_job_delivers_and_parks

/datum/unit_test/om/io_job_delivers_and_parks/run_om(list/made)
	var/datum/om_test_entity/E = entity(made)
	// The diagnostics are shared by every test of this kind: count from where this test starts.
	var/list/before_diag = io_diagnostics()
	var/completed_before = before_diag["test"]?["completed"] || 0
	var/errors_before = before_diag["test"]?["errors"] || 0
	var/id = io_job(E, /datum/io_backend/test, "hello", /datum/om_test_entity/proc/io_done, "a")
	TEST_ASSERT(id, "io_job returns a job id at once")
	TEST_ASSERT(!length(E.log), "the callback does not run inline")
	TEST_ASSERT(io_job_pending(id), "the job is pending")
	scheduler_advance(1)
	TEST_ASSERT("a:hello:" in E.log, "the callback runs on E with the result")
	TEST_ASSERT(!io_job_count(), "no jobs left")
	TEST_ASSERT(!after_pending(GLOB.io_lane, "io_poll"), "the I/O lane parks when no jobs are pending")
	io_job(E, /datum/io_backend/test, "fail", /datum/om_test_entity/proc/io_done, "b")
	io_job(E, /datum/io_backend/test, "refuse", /datum/om_test_entity/proc/io_done, "c")
	scheduler_advance(1)
	TEST_ASSERT("b::failed" in E.log, "a failed job delivers its error")
	TEST_ASSERT("c::refused" in E.log, "a job that fails to start delivers its error on the lane")
	var/list/diag = io_diagnostics()
	TEST_ASSERT((diag["test"]?["completed"] || 0) - completed_before == 3, "io_diagnostics counts completed jobs per kind")
	TEST_ASSERT((diag["test"]?["errors"] || 0) - errors_before == 2, "io_diagnostics counts errors per kind")

/datum/unit_test/om/io_job_owned_and_weak

/datum/unit_test/om/io_job_owned_and_weak/run_om(list/made)
	var/datum/om_test_entity/E = entity(made)
	var/datum/om_test_entity/witness = entity(made)
	var/datum/om_test_entity/other = entity(made)
	io_job(E, /datum/io_backend/test, "x", /datum/om_test_entity/proc/io_done, "gone", witness)
	qdel(E)
	var/datum/om_test_entity/live = entity(made)
	io_job(live, /datum/io_backend/test, "y", /datum/om_test_entity/proc/io_done, "ctx", other)
	qdel(other)
	var/cancel_id = io_job(live, /datum/io_backend/test, "z", /datum/om_test_entity/proc/io_done, "cancelled")
	TEST_ASSERT(io_job_cancel(cancel_id), "cancel finds the job")
	scheduler_advance(1)
	TEST_ASSERT(!("gone via" in witness.log), "a deleted owner's job result is dropped")
	TEST_ASSERT(!length(live.log), "a job whose context arg was deleted, or that was cancelled, is dropped")
	TEST_ASSERT(!io_job_count(), "dropped jobs still leave the list once answered")

/datum/unit_test/om/io_job_queue_limit

/datum/unit_test/om/io_job_queue_limit/run_om(list/made)
	var/datum/om_test_entity/E = entity(made)
	var/first = io_job(E, /datum/io_backend/test, "wait", /datum/om_test_entity/proc/io_done, "1")
	io_job(E, /datum/io_backend/test, "wait", /datum/om_test_entity/proc/io_done, "2")
	io_job(E, /datum/io_backend/test, "three", /datum/om_test_entity/proc/io_done, "3")
	var/list/diag = io_diagnostics()
	TEST_ASSERT(diag["test"]?["pending"] == 2 && diag["test"]?["queued"] == 1, "jobs over the kind's limit queue")
	scheduler_advance(1)
	TEST_ASSERT(!length(E.log), "queued jobs wait while the in-flight ones are unanswered")
	for(var/id in GLOB.om_io_test_ready)
		GLOB.om_io_test_ready[id] = "done"
	scheduler_advance(1)
	TEST_ASSERT(("1:done:" in E.log) && ("2:done:" in E.log), "in-flight jobs deliver")
	scheduler_advance(1)
	TEST_ASSERT("3:three:" in E.log, "the queued job starts once a slot frees and delivers")
	TEST_ASSERT(!io_job_pending(first), "a delivered job is no longer pending")
