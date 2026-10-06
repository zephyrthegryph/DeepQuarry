// Object-model core: I/O jobs (doc/rewrite/object_model_core.md §4.12).
//
// Gameplay never waits on I/O. A job is started with
//
//     om_io(E, /datum/om/io/<kind>, request args..., on_done, context args...)
//
// which returns at once (a job id, or 0 if E is already gone). The kind consumes exactly
// its `arg_count` request args; the next arg is the callback, and anything after it is
// passed to the callback after the result:
//
//     on_done(result, error, context args...)
//
//   - owned by E: cancelled when E is deleted (like om_after). E null: the global owner.
//   - weak: E and every datum context arg are held as OM handles and resolved when the job
//     completes. If any is gone the result is dropped (counted per kind).
//   - on the I/O lane: the scheduler's global owner polls every pending job's rust-g check
//     call within the scheduler budget each pass and parks (no deadline) when none are
//     pending. Jobs queued before the live scheduler runs wait until it does.
//   - visible in om_diagnostics()["io"]: per kind started/completed/errors/dropped,
//     pending, queued, and latency (average and max, ms).
//
// Kinds: /datum/om/io/sql (rustg_sql_query_async / rustg_sql_check_query),
// /datum/om/io/http (rustg_http_request_async / rustg_http_check_request) and
// /datum/om/io/rustg_job (an iconforge job started by the caller). A kind is a
// singleton; per-job state lives on the job.

/// Deciseconds a job may stay unanswered before the lane abandons it with an error.
#define OM_IO_TIMEOUT_DS (5 MINUTES)

/// One pending I/O job. Holds no object references: the owner and datum context args are
/// OM handles.
/datum/om/io_job
	var/id = 0
	/// The owner's OM handle.
	var/owner_h
	var/kind_type
	/// The request args, as the caller passed them (text and numbers).
	var/list/request
	/// The rust-g job id; null while the job waits for a free slot.
	var/job_id
	var/on_done
	var/list/context
	var/list/positions
	/// REALTIMEOFDAY when the job was queued, and when it was handed to rust-g.
	var/queued_at = 0
	var/started_at = 0
	/// Set when the job is already answered (it failed to start); delivered next pass.
	var/raw
	var/preset_error

// ---------------------------------------------------------------- kinds

/datum/om/io
	var/name = "io"
	/// Request args om_io() takes before the callback.
	var/arg_count = 0
	/// Jobs of this kind that may be in flight at once (0: no limit). The rest queue.
	var/max_active = 0

/// Hands the request to rust-g. Returns the job id, or null and sets `J.preset_error`.
/datum/om/io/proc/start(datum/om/io_job/J)
	J.preset_error = "no start() for [type]"
	return null

/// rust-g's check call: RUSTG_JOB_NO_RESULTS_YET, or the raw result.
/datum/om/io/proc/check(job_id)
	return RUSTG_JOB_NO_RESULTS_YET

/// Turns a raw result into list(result, error). error is null on success.
/datum/om/io/proc/decode(raw)
	return list(raw, null)

/// The in-flight limit right now.
/datum/om/io/proc/active_limit()
	return max_active

/// SQL: om_io(E, /datum/om/io/sql, sql, arguments, on_done, ...).
/// `sql` uses :name placeholders filled from the `arguments` assoc list (parameterized
/// only; format_table_name() for tables). result = list("rows" = list of row lists,
/// "affected" = n, "last_insert_id" = id), or null with error text.
/datum/om/io/sql
	name = "sql"
	arg_count = 2

/datum/om/io/sql/active_limit()
	return SSdbcore?.max_concurrent_queries || 10

/datum/om/io/sql/start(datum/om/io_job/J)
	if(!SSdbcore || !SSdbcore.IsConnected())
		J.preset_error = "No connection!"
		return null
	var/list/arguments = J.request[2]
	var/id = rustg_sql_query_async(SSdbcore.connection, J.request[1], json_encode(arguments || list()))
	if(!id)
		J.preset_error = "sql start failed"
		return null
	return id

/datum/om/io/sql/check(job_id)
	return rustg_sql_check_query(job_id)

/datum/om/io/sql/decode(raw)
	var/list/result
	try
		result = json_decode(raw)
	catch // ALLOW(silent_catch): a malformed result is returned to the caller as the job's error
		return list(null, "bad sql result: [raw]")
	switch(result?["status"])
		if("ok")
			return list(list("rows" = result["rows"], "affected" = result["affected"], "last_insert_id" = result["last_insert_id"]), null)
		if("err")
			return list(null, result["data"])
		if("offline")
			return list(null, "CONNECTION OFFLINE")
	return list(null, "bad sql result: [raw]")

/// HTTP: om_io(E, /datum/om/io/http, method, url, body, headers, on_done, ...).
/// `method` is RUSTG_HTTP_METHOD_*; body text or ""; headers an assoc list or null.
/// result = /datum/http_response (status_code, body, headers), or null with error text.
/datum/om/io/http
	name = "http"
	arg_count = 4

/datum/om/io/http/start(datum/om/io_job/J)
	var/list/headers = J.request[4]
	var/id = rustg_http_request_async(J.request[1], J.request[2], J.request[3] || "", length(headers) ? json_encode(headers) : "", null)
	if(isnull(text2num(id)))
		J.preset_error = "http start failed: [id]"
		return null
	return id

/datum/om/io/http/check(job_id)
	return rustg_http_check_request(job_id)

/datum/om/io/http/decode(raw)
	var/datum/http_response/R = new
	try
		var/list/L = json_decode(raw)
		R.status_code = L["status_code"]
		R.headers = L["headers"]
		R.body = L["body"]
	catch // ALLOW(silent_catch): a malformed result is returned to the caller as the job's error
		return list(null, "bad http result: [raw]")
	return list(R, null)

/// rust-g jobs the caller already started: om_io(E, /datum/om/io/rustg_job, job_id, on_done, ...).
/// `job_id` comes from an iconforge `*_async` call; the kind polls rustg_iconforge_check() on the I/O lane
/// instead of the caller spinning on it. result = the job's raw text, or null with error text.
/datum/om/io/rustg_job
	name = "rustg_job"
	arg_count = 1

/datum/om/io/rustg_job/start(datum/om/io_job/J)
	var/id = J.request[1]
	if(isnull(id) || id == "")
		J.preset_error = "rustg job start failed: no job id"
		return null
	return "[id]"

/datum/om/io/rustg_job/check(job_id)
	return rustg_iconforge_check(job_id)

/datum/om/io/rustg_job/decode(raw)
	if(raw == RUSTG_JOB_ERROR || raw == RUSTG_JOB_NO_SUCH_JOB)
		return list(null, "rustg job failed: [raw]")
	return list(raw, null)

/proc/om_io_kind(kind_type)
	RETURN_TYPE(/datum/om/io)
	var/static/list/kinds = list()
	var/datum/om/io/K = kinds[kind_type]
	if(!K && ispath(kind_type, /datum/om/io))
		K = kinds[kind_type] = new kind_type
	return K

// ---------------------------------------------------------------- scheduler state

/datum/om/scheduler/var/list/io_jobs
/datum/om/scheduler/var/io_seq = 0
/// Poll cursor: the lane resumes here when the budget ran out mid-list.
/datum/om/scheduler/var/io_cursor = 1
/// Per kind name: list(started, completed, errors, dropped, latency total ms, latency max ms).
/datum/om/scheduler/var/list/io_stats

#define OM_IO_STAT_STARTED 1
#define OM_IO_STAT_COMPLETED 2
#define OM_IO_STAT_ERRORS 3
#define OM_IO_STAT_DROPPED 4
#define OM_IO_STAT_LAT_TOTAL 5
#define OM_IO_STAT_LAT_MAX 6

/proc/om_io_stat(sched_arg, datum/om/io/K, stat, amount = 1)
	var/datum/om/scheduler/sched = sched_arg
	LAZYINITLIST(sched.io_stats)
	var/list/S = sched.io_stats[K.name]
	if(!S)
		S = sched.io_stats[K.name] = list(0, 0, 0, 0, 0, 0)
	if(stat == OM_IO_STAT_LAT_MAX)
		S[stat] = max(S[stat], amount)
	else
		S[stat] += amount

// ---------------------------------------------------------------- API

/// Starts an I/O job owned by E and returns at once: the job id, or 0 if E or a datum
/// context arg is already gone. See the header for the argument layout.
/proc/om_io(owner, kind_type, ...)
	var/datum/E = owner
	var/datum/om/io/K = om_io_kind(kind_type)
	if(!K)
		CRASH("om_io: [kind_type] is not an I/O kind")
	if(length(args) < 3 + K.arg_count)
		CRASH("om_io: [kind_type] takes [K.arg_count] request args and a callback")
	if(isnull(E))
		E = om_global_owner()
	if(QDELETED(E))
		return 0
	var/owner_h = om_handle(E)
	if(!owner_h)
		return 0
	var/datum/om/io_job/J = new
	J.owner_h = owner_h
	J.kind_type = kind_type
	J.request = K.arg_count ? args.Copy(3, 3 + K.arg_count) : list()
	J.on_done = args[3 + K.arg_count]
	if(length(args) > 3 + K.arg_count)
		var/list/capture = capture_args(args.Copy(4 + K.arg_count))
		if(!capture)
			return 0
		J.context = capture[1]
		J.positions = capture[2]
	var/datum/om/scheduler/sched = om_scheduler()
	J.id = ++sched.io_seq
	J.queued_at = REALTIMEOFDAY
	LAZYADD(sched.io_jobs, J)
	om_io_try_start(sched, K, J)
	om_io_wake(sched)
	return J.id

/// Cancels job `id`. The rust-g job still finishes; its result is discarded.
/proc/om_io_cancel(id)
	var/datum/om/scheduler/sched = om_scheduler()
	for(var/datum/om/io_job/J as anything in sched.io_jobs)
		if(J.id == id)
			J.on_done = null
			return TRUE
	return FALSE

/proc/om_io_pending(id)
	var/datum/om/scheduler/sched = om_scheduler()
	for(var/datum/om/io_job/J as anything in sched.io_jobs)
		if(J.id == id)
			return !isnull(J.on_done)
	return FALSE

/// Number of jobs not yet answered (all kinds, or one).
/proc/om_io_count(kind_type)
	var/datum/om/scheduler/sched = om_scheduler()
	. = 0
	for(var/datum/om/io_job/J as anything in sched.io_jobs)
		if(!kind_type || J.kind_type == kind_type)
			.++

// ---------------------------------------------------------------- the lane

/proc/om_io_active(sched_arg, kind_type)
	var/datum/om/scheduler/sched = sched_arg
	. = 0
	for(var/datum/om/io_job/J as anything in sched.io_jobs)
		if(J.kind_type == kind_type && !isnull(J.job_id))
			.++

/// Hands `J` to rust-g if its kind has a free slot. A failed start is answered next pass.
/proc/om_io_try_start(sched_arg, datum/om/io/K, datum/om/io_job/J)
	var/datum/om/scheduler/sched = sched_arg
	if(!isnull(J.job_id) || J.preset_error)
		return
	var/limit = K.active_limit()
	if(limit && om_io_active(sched, J.kind_type) >= limit)
		return
	var/id = K.start(J)
	if(isnull(id))
		if(!J.preset_error)
			J.preset_error = "[K.name] start failed"
		return
	J.job_id = id
	J.started_at = REALTIMEOFDAY
	om_io_stat(sched, K, OM_IO_STAT_STARTED)

/// Puts the I/O lane on the wheel (next pass) if it isn't already.
/proc/om_io_wake(sched_arg)
	var/datum/om/scheduler/sched = sched_arg
	var/datum/om/global_owner/G = sched.global_owner || om_global_owner()
	var/datum/om/behaviour/B = om_registry().behaviour(/datum/om/behaviour/internal/io)
	if(!B || om_deadline_pending(G, B))
		return
	om_deadline(G, 1, B)

/datum/om/behaviour/internal/io
	name = "om: io"
	lane = LANE_BACKGROUND

/datum/om/behaviour/internal/io/on_deadline(datum/E)
	var/datum/om/scheduler/sched = E.om_rec?.sched || om_scheduler()
	om_io_poll(sched)
	if(length(sched.io_jobs))
		om_deadline(E, 1, src)

/// One pass of the I/O lane: check each pending job once, resuming at the cursor, until the
/// budget runs out. Answered jobs leave the list before their callback runs.
/proc/om_io_poll(sched_arg)
	var/datum/om/scheduler/sched = sched_arg
	var/list/jobs = sched.io_jobs
	if(!length(jobs))
		sched.io_cursor = 1
		return
	if(sched.io_cursor > length(jobs))
		sched.io_cursor = 1
	var/checked = 0
	var/total = length(jobs)
	while(checked < total && length(sched.io_jobs))
		jobs = sched.io_jobs
		if(sched.io_cursor > length(jobs))
			sched.io_cursor = 1
		var/datum/om/io_job/J = jobs[sched.io_cursor]
		checked++
		var/datum/om/io/K = om_io_kind(J.kind_type)
		om_io_try_start(sched, K, J)
		var/raw = null
		var/answered = FALSE
		if(J.preset_error)
			answered = TRUE
		else if(!isnull(J.job_id))
			raw = K.check(J.job_id)
			if(raw != RUSTG_JOB_NO_RESULTS_YET)
				answered = TRUE
			else if(REALTIMEOFDAY - J.started_at > OM_IO_TIMEOUT_DS)
				log_world("OM IO: [K.name] job [J.id] timed out after [OM_IO_TIMEOUT_DS / 10]s; abandoning")
				J.preset_error = "[K.name] job timed out"
				answered = TRUE
		if(!answered)
			sched.io_cursor++
		else
			jobs.Cut(sched.io_cursor, sched.io_cursor + 1)
			if(!length(jobs))
				sched.io_jobs = null
			om_io_deliver(sched, K, J, raw)
		if(sched.out_of_budget())
			break
	if(sched.io_cursor > length(sched.io_jobs))
		sched.io_cursor = 1

/// Runs the callback for an answered job on its owner, if the owner and context still exist.
/proc/om_io_deliver(sched_arg, datum/om/io/K, datum/om/io_job/J, raw)
	var/datum/om/scheduler/sched = sched_arg
	var/list/outcome = J.preset_error ? list(null, J.preset_error) : K.decode(raw)
	if(J.started_at)
		var/latency = REALTIMEOFDAY - J.started_at
		om_io_stat(sched, K, OM_IO_STAT_LAT_TOTAL, latency * 100)
		om_io_stat(sched, K, OM_IO_STAT_LAT_MAX, latency * 100)
	om_io_stat(sched, K, OM_IO_STAT_COMPLETED)
	if(outcome[2])
		om_io_stat(sched, K, OM_IO_STAT_ERRORS)
	if(!J.on_done)
		om_io_stat(sched, K, OM_IO_STAT_DROPPED)
		return
	var/datum/E = om_resolve(J.owner_h)
	var/list/captured = J.context ? J.context.Copy() : null
	if(!E || (captured && !resolve_captured(captured, J.positions)))
		om_io_stat(sched, K, OM_IO_STAT_DROPPED)
		log_qdel("OM: dropped io [K.name] callback [J.on_done]: its owner or a captured argument was deleted")
		return
	var/list/call_args = list(outcome[1], outcome[2])
	if(captured)
		call_args += captured
	try
		om_guarded_call(E, J.on_done, call_args)
	catch(var/exception/e)
		dq_report_caught(e, "om io [K.name] callback [J.on_done] on [E]")

/// The I/O section of om_diagnostics().
/proc/om_io_diagnostics(sched_arg)
	var/datum/om/scheduler/sched = sched_arg
	. = list()
	var/list/pending = list()
	var/list/queued = list()
	for(var/datum/om/io_job/J as anything in sched.io_jobs)
		var/datum/om/io/K = om_io_kind(J.kind_type)
		if(isnull(J.job_id))
			queued[K.name] += 1
		else
			pending[K.name] += 1
	var/list/names = list()
	for(var/name in sched.io_stats)
		names[name] = TRUE
	for(var/name in pending)
		names[name] = TRUE
	for(var/name in queued)
		names[name] = TRUE
	for(var/name in names)
		var/list/S = sched.io_stats?[name] || list(0, 0, 0, 0, 0, 0)
		.[name] = list(
			"started" = S[OM_IO_STAT_STARTED],
			"completed" = S[OM_IO_STAT_COMPLETED],
			"errors" = S[OM_IO_STAT_ERRORS],
			"dropped" = S[OM_IO_STAT_DROPPED],
			"pending" = pending[name] || 0,
			"queued" = queued[name] || 0,
			"latency_avg_ms" = S[OM_IO_STAT_COMPLETED] ? round(S[OM_IO_STAT_LAT_TOTAL] / S[OM_IO_STAT_COMPLETED], 0.1) : 0,
			"latency_max_ms" = S[OM_IO_STAT_LAT_MAX],
		)

// ---------------------------------------------------------------- callers' helpers

/// om_io() callback target for fire-and-forget writes: logs a failed query, nothing else.
/proc/om_io_log_sql_error(list/result, error, sql)
	if(error)
		log_sql("[error] | Query used: [sql]")

/// Fire-and-forget HTTP GET (webhooks). Owned by the global owner; a failure is logged.
/proc/om_http_get(url)
	return om_io(null, /datum/om/io/http, RUSTG_HTTP_METHOD_GET, url, "", null, /proc/om_io_log_http_error, url)

/proc/om_io_log_http_error(result, error, url)
	if(error)
		log_world("OM IO: HTTP GET failed ([error]): [url]")

#undef OM_IO_STAT_STARTED
#undef OM_IO_STAT_COMPLETED
#undef OM_IO_STAT_ERRORS
#undef OM_IO_STAT_DROPPED
#undef OM_IO_STAT_LAT_TOTAL
#undef OM_IO_STAT_LAT_MAX
