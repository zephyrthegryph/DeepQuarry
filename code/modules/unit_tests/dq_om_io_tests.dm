// Object-model core: I/O jobs (doc/rewrite/object_model_core.md §4.12). A fake kind stands in
// for rust-g: its jobs answer when the test says so, so the lane, ownership, weak capture,
// queueing and diagnostics are tested without a database or network.

/// Fake I/O kind: one request arg (the answer). Jobs finish when GLOB.om_io_test_ready says.
/datum/om/io/test
	name = "test"
	arg_count = 1
	max_active = 2

GLOBAL_LIST_EMPTY(om_io_test_ready)
GLOBAL_VAR_INIT(om_io_test_seq, 0)

/datum/om/io/test/start(datum/om/io_job/J)
	if(J.request[1] == "refuse")
		J.preset_error = "refused"
		return null
	var/id = "[++GLOB.om_io_test_seq]"
	GLOB.om_io_test_ready[id] = J.request[1]
	return id

/datum/om/io/test/check(job_id)
	var/answer = GLOB.om_io_test_ready[job_id]
	if(answer == "wait")
		return RUSTG_JOB_NO_RESULTS_YET
	GLOB.om_io_test_ready -= job_id
	return answer

/datum/om/io/test/decode(raw)
	if(raw == "fail")
		return list(null, "failed")
	return list(raw, null)

/datum/om_test_entity/proc/io_done(result, error, tag, datum/om_test_entity/other)
	log += "[tag]:[result]:[error]"
	other?.log += "[tag] via"

/datum/unit_test/om/io_job_delivers_and_parks

/datum/unit_test/om/io_job_delivers_and_parks/run_om(list/made)
	var/datum/om_test_entity/E = entity(made)
	var/id = om_io(E, /datum/om/io/test, "hello", /datum/om_test_entity/proc/io_done, "a")
	TEST_ASSERT(id, "om_io returns a job id at once")
	TEST_ASSERT(!length(E.log), "the callback does not run inline")
	TEST_ASSERT(om_io_pending(id), "the job is pending")
	scheduler_advance(1)
	TEST_ASSERT("a:hello:" in E.log, "the callback runs on E with the result")
	TEST_ASSERT(!om_io_count(), "no jobs left")
	var/datum/om/scheduler/sched = om_scheduler()
	TEST_ASSERT(!om_deadline_pending(sched.global_owner, om_registry().io_behaviour), "the I/O lane parks when no jobs are pending")
	om_io(E, /datum/om/io/test, "fail", /datum/om_test_entity/proc/io_done, "b")
	om_io(E, /datum/om/io/test, "refuse", /datum/om_test_entity/proc/io_done, "c")
	scheduler_advance(1)
	TEST_ASSERT("b::failed" in E.log, "a failed job delivers its error")
	TEST_ASSERT("c::refused" in E.log, "a job that fails to start delivers its error on the lane")
	var/list/diag = om_diagnostics(sched)["io"]
	TEST_ASSERT(diag["test"]?["completed"] == 3, "om_diagnostics counts completed jobs per kind")
	TEST_ASSERT(diag["test"]?["errors"] == 2, "om_diagnostics counts errors per kind")

/datum/unit_test/om/io_job_owned_and_weak

/datum/unit_test/om/io_job_owned_and_weak/run_om(list/made)
	var/datum/om_test_entity/E = entity(made)
	var/datum/om_test_entity/witness = entity(made)
	var/datum/om_test_entity/other = entity(made)
	om_io(E, /datum/om/io/test, "x", /datum/om_test_entity/proc/io_done, "gone", witness)
	qdel(E)
	var/datum/om_test_entity/live = entity(made)
	om_io(live, /datum/om/io/test, "y", /datum/om_test_entity/proc/io_done, "ctx", other)
	qdel(other)
	var/cancel_id = om_io(live, /datum/om/io/test, "z", /datum/om_test_entity/proc/io_done, "cancelled")
	TEST_ASSERT(om_io_cancel(cancel_id), "cancel finds the job")
	scheduler_advance(1)
	TEST_ASSERT(!("gone via" in witness.log), "a deleted owner's job result is dropped")
	TEST_ASSERT(!length(live.log), "a job whose context arg was deleted, or that was cancelled, is dropped")
	TEST_ASSERT(!om_io_count(), "dropped jobs still leave the list once answered")

/datum/unit_test/om/io_job_queue_limit

/datum/unit_test/om/io_job_queue_limit/run_om(list/made)
	var/datum/om_test_entity/E = entity(made)
	var/first = om_io(E, /datum/om/io/test, "wait", /datum/om_test_entity/proc/io_done, "1")
	om_io(E, /datum/om/io/test, "wait", /datum/om_test_entity/proc/io_done, "2")
	om_io(E, /datum/om/io/test, "three", /datum/om_test_entity/proc/io_done, "3")
	var/list/diag = om_diagnostics(om_scheduler())["io"]
	TEST_ASSERT(diag["test"]?["pending"] == 2 && diag["test"]?["queued"] == 1, "jobs over the kind's limit queue")
	scheduler_advance(1)
	TEST_ASSERT(!length(E.log), "queued jobs wait while the in-flight ones are unanswered")
	for(var/id in GLOB.om_io_test_ready)
		GLOB.om_io_test_ready[id] = "done"
	scheduler_advance(1)
	TEST_ASSERT(("1:done:" in E.log) && ("2:done:" in E.log), "in-flight jobs deliver")
	scheduler_advance(1)
	TEST_ASSERT("3:three:" in E.log, "the queued job starts once a slot frees and delivers")
	TEST_ASSERT(!om_io_pending(first), "a delivered job is no longer pending")
