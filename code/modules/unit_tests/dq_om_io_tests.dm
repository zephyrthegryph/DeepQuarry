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

/// A plain callback owner; these tests do not depend on an OM record or scheduler.
/datum/io_test_entity
	var/list/log

/// Isolate transport queues and backend globals, then restore them even on assertion failure.
/datum/unit_test/io_transport
	abstract_type = /datum/unit_test/io_transport
	var/datum/io_lane/saved_lane
	var/list/saved_ready
	var/saved_seq

/datum/unit_test/io_transport/Run()
	test_driver_begin()
	saved_lane = GLOB.io_lane
	saved_ready = GLOB.om_io_test_ready
	saved_seq = GLOB.om_io_test_seq
	set_global("io_lane", new /datum/io_lane)
	set_global("om_io_test_ready", list())
	set_global("om_io_test_seq", 0)
	set_global("dx_exec_stats", list())
	set_global("dview_mob", GLOB.dview_mob)
	defer_cleanup(src, PROC_REF(finish_io_test))
	run_io()

/datum/unit_test/io_transport/proc/finish_io_test()
	cancel_after(GLOB.io_lane, "io_poll")
	for(var/datum/io_job/J as anything in GLOB.io_lane.jobs)
		qdel(J)
	qdel(GLOB.io_lane)
	set_global("io_lane", saved_lane)
	set_global("om_io_test_ready", saved_ready)
	set_global("om_io_test_seq", saved_seq)
	saved_lane = null
	saved_ready = null
	test_driver_end()

/datum/unit_test/io_transport/proc/run_io()
	return

/datum/io_test_entity/proc/io_done(result, error, tag, datum/io_test_entity/other)
	LAZYADD(log, "[tag]:[result]:[error]")
	if(other)
		LAZYADD(other.log, "[tag] via")

/datum/unit_test/io_transport/io_job_delivers_and_parks

/datum/unit_test/io_transport/io_job_delivers_and_parks/run_io()
	var/datum/io_test_entity/E = allocate(/datum/io_test_entity)
	var/id = io_job(E, /datum/io_backend/test, "hello", TYPE_PROC_REF(/datum/io_test_entity, io_done), "a")
	TEST_ASSERT(id, "io_job returns a job id at once")
	TEST_ASSERT(!length(E.log), "the callback does not run inline")
	TEST_ASSERT(io_job_pending(id), "the job is pending")
	test_time(0.1 SECONDS)
	TEST_ASSERT("a:hello:" in E.log, "the callback runs on E with the result")
	TEST_ASSERT(!io_job_count(), "no jobs left")
	TEST_ASSERT(!after_pending(GLOB.io_lane, "io_poll"), "the I/O lane parks when no jobs are pending")
	io_job(E, /datum/io_backend/test, "fail", TYPE_PROC_REF(/datum/io_test_entity, io_done), "b")
	io_job(E, /datum/io_backend/test, "refuse", TYPE_PROC_REF(/datum/io_test_entity, io_done), "c")
	test_time(0.1 SECONDS)
	TEST_ASSERT("b::failed" in E.log, "a failed job delivers its error")
	TEST_ASSERT("c::refused" in E.log, "a job that fails to start delivers its error on the lane")
	var/list/diag = io_diagnostics()
	TEST_ASSERT(diag["test"]?["completed"] == 3, "io_diagnostics counts completed jobs per kind")
	TEST_ASSERT(diag["test"]?["errors"] == 2, "io_diagnostics counts errors per kind")

/datum/unit_test/io_transport/io_job_owned_and_weak

/datum/unit_test/io_transport/io_job_owned_and_weak/run_io()
	var/datum/io_test_entity/E = allocate(/datum/io_test_entity)
	var/datum/io_test_entity/witness = allocate(/datum/io_test_entity)
	var/datum/io_test_entity/other = allocate(/datum/io_test_entity)
	io_job(E, /datum/io_backend/test, "x", TYPE_PROC_REF(/datum/io_test_entity, io_done), "gone", witness)
	qdel(E)
	var/datum/io_test_entity/live = allocate(/datum/io_test_entity)
	io_job(live, /datum/io_backend/test, "y", TYPE_PROC_REF(/datum/io_test_entity, io_done), "ctx", other)
	qdel(other)
	var/cancel_id = io_job(live, /datum/io_backend/test, "z", TYPE_PROC_REF(/datum/io_test_entity, io_done), "cancelled")
	TEST_ASSERT(io_job_cancel(cancel_id), "cancel finds the job")
	test_time(0.1 SECONDS)
	TEST_ASSERT(!("gone via" in witness.log), "a deleted owner's job result is dropped")
	TEST_ASSERT(!length(live.log), "a job whose context arg was deleted, or that was cancelled, is dropped")
	TEST_ASSERT(!io_job_count(), "dropped jobs still leave the list once answered")

/datum/unit_test/io_transport/io_job_queue_limit

/datum/unit_test/io_transport/io_job_queue_limit/run_io()
	var/datum/io_test_entity/E = allocate(/datum/io_test_entity)
	var/first = io_job(E, /datum/io_backend/test, "wait", TYPE_PROC_REF(/datum/io_test_entity, io_done), "1")
	io_job(E, /datum/io_backend/test, "wait", TYPE_PROC_REF(/datum/io_test_entity, io_done), "2")
	io_job(E, /datum/io_backend/test, "three", TYPE_PROC_REF(/datum/io_test_entity, io_done), "3")
	var/list/diag = io_diagnostics()
	TEST_ASSERT(diag["test"]?["pending"] == 2 && diag["test"]?["queued"] == 1, "jobs over the kind's limit queue")
	test_time(0.1 SECONDS)
	TEST_ASSERT(!length(E.log), "queued jobs wait while the in-flight ones are unanswered")
	for(var/id in GLOB.om_io_test_ready)
		GLOB.om_io_test_ready[id] = "done"
	test_time(0.1 SECONDS)
	TEST_ASSERT(("1:done:" in E.log) && ("2:done:" in E.log), "in-flight jobs deliver")
	test_time(0.1 SECONDS)
	TEST_ASSERT("3:three:" in E.log, "the queued job starts once a slot frees and delivers")
	TEST_ASSERT(!io_job_pending(first), "a delivered job is no longer pending")
