// I/O jobs: the transport under the /datum/io requests (doc/rewrite/final_api.html section 2, "Requests and waiting"; code/engine/io/db.dm).
// Moved here from the object model (code/datums/om/io.dm) when it was retired.
//
// Gameplay never waits on I/O. A job is started with
//
//     io_job(E, /datum/io_backend/<kind>, request args..., on_done, context args...)
//
// which returns at once (a job id, or 0 if E is already gone). The backend consumes exactly its `arg_count` request args; the next arg
// is the callback, and anything after it is passed to the callback after the result:
//
//     on_done(result, error, context args...)
//
//   - owned by E: dropped when E is deleted. E null: no owner, and on_done is a global proc.
//   - weak: E and every datum context arg are held as handles and resolved when the job completes. If any is gone the result is
//     dropped (counted per backend).
//   - on the I/O lane: a keyed after() of the lane polls every pending job's rust-g check call once a tick, within the tick's budget,
//     and stops when none are pending. Jobs queued before the kernel runs wait until it does.
//   - visible in io_diagnostics(): per backend started/completed/errors/dropped, pending, queued, and latency (average and max, ms).
//
// Backends: /datum/io_backend/sql (rustg_sql_query_async / rustg_sql_check_query), /datum/io_backend/http (rustg_http_request_async /
// rustg_http_check_request) and /datum/io_backend/rustg_job (an iconforge job started by the caller). A backend is a singleton; per-job
// state lives on the job. Content does not start jobs: it opens a /datum/io request, or calls sql_write().

/// Deciseconds a job may stay unanswered before the lane abandons it with an error.
#define IO_JOB_TIMEOUT_DS (5 MINUTES)

/// One pending I/O job. Holds no object references: the owner and datum context args are handles.
/datum/io_job
	var/id = 0
	/// The owner's handle, or null for a job nobody owns.
	var/owner_h
	var/backend_type
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
	var/preset_error

// ---------------------------------------------------------------- backends

/datum/io_backend
	var/name = "io"
	/// Request args io_job() takes before the callback.
	var/arg_count = 0
	/// Jobs of this backend that may be in flight at once (0: no limit). The rest queue.
	var/max_active = 0

/// Hands the request to rust-g. Returns the job id, or null and sets `J.preset_error`.
/datum/io_backend/proc/start(datum/io_job/J)
	J.preset_error = "no start() for [type]"
	return null

/// rust-g's check call: RUSTG_JOB_NO_RESULTS_YET, or the raw result.
/datum/io_backend/proc/check(job_id)
	return RUSTG_JOB_NO_RESULTS_YET

/// Turns a raw result into list(result, error). error is null on success.
/datum/io_backend/proc/decode(raw)
	return list(raw, null)

/// The in-flight limit right now.
/datum/io_backend/proc/active_limit()
	return max_active

/// SQL: io_job(E, /datum/io_backend/sql, sql, arguments, on_done, ...). `sql` uses :name placeholders filled from the `arguments`
/// assoc list (parameterized only; format_table_name() for tables). result = list("rows" = list of row lists, "affected" = n,
/// "last_insert_id" = id), or null with error text.
/datum/io_backend/sql
	name = "sql"
	arg_count = 2

/datum/io_backend/sql/active_limit()
	return SSdbcore?.max_concurrent_queries || 10

/datum/io_backend/sql/start(datum/io_job/J)
	if(!SSdbcore || !SSdbcore.IsConnected())
		J.preset_error = "No connection!"
		return null
	var/list/arguments = J.request[2]
	var/id = rustg_sql_query_async(SSdbcore.connection, J.request[1], json_encode(arguments || list()))
	if(!id)
		J.preset_error = "sql start failed"
		return null
	return id

/datum/io_backend/sql/check(job_id)
	return rustg_sql_check_query(job_id)

/datum/io_backend/sql/decode(raw)
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

/// HTTP: io_job(E, /datum/io_backend/http, method, url, body, headers, on_done, ...). `method` is RUSTG_HTTP_METHOD_*; body text or
/// ""; headers an assoc list or null. result = /datum/http_response (status_code, body, headers), or null with error text.
/datum/io_backend/http
	name = "http"
	arg_count = 4

/datum/io_backend/http/start(datum/io_job/J)
	var/list/headers = J.request[4]
	var/id = rustg_http_request_async(J.request[1], J.request[2], J.request[3] || "", length(headers) ? json_encode(headers) : "", null)
	if(isnull(text2num(id)))
		J.preset_error = "http start failed: [id]"
		return null
	return id

/datum/io_backend/http/check(job_id)
	return rustg_http_check_request(job_id)

/datum/io_backend/http/decode(raw)
	var/datum/http_response/R = new
	try
		var/list/L = json_decode(raw)
		R.status_code = L["status_code"]
		R.headers = L["headers"]
		R.body = L["body"]
	catch // ALLOW(silent_catch): a malformed result is returned to the caller as the job's error
		return list(null, "bad http result: [raw]")
	return list(R, null)

/// rust-g jobs the caller already started: io_job(E, /datum/io_backend/rustg_job, job_id, on_done, ...). `job_id` comes from an
/// iconforge `*_async` call; the backend polls rustg_iconforge_check() on the I/O lane instead of the caller spinning on it. result =
/// the job's raw text, or null with error text.
/datum/io_backend/rustg_job
	name = "rustg_job"
	arg_count = 1

/datum/io_backend/rustg_job/start(datum/io_job/J)
	var/id = J.request[1]
	if(isnull(id) || id == "")
		J.preset_error = "rustg job start failed: no job id"
		return null
	return "[id]"

/datum/io_backend/rustg_job/check(job_id)
	return rustg_iconforge_check(job_id)

/datum/io_backend/rustg_job/decode(raw)
	if(raw == RUSTG_JOB_ERROR || raw == RUSTG_JOB_NO_SUCH_JOB)
		return list(null, "rustg job failed: [raw]")
	return list(raw, null)

/proc/io_backend(backend_type)
	RETURN_TYPE(/datum/io_backend)
	var/static/list/backends = list()
	var/datum/io_backend/K = backends[backend_type]
	if(!K && ispath(backend_type, /datum/io_backend))
		K = backends[backend_type] = new backend_type
	return K

// ---------------------------------------------------------------- the lane

/// The I/O lane: its pending jobs, its poll cursor and its counters. Its own after() polls it.
/datum/io_lane
	var/list/jobs
	var/seq = 0
	/// Poll cursor: the lane resumes here when the budget ran out mid-list.
	var/cursor = 1
	/// Per backend name: list(started, completed, errors, dropped, latency total ms, latency max ms).
	var/list/stats

GLOBAL_DATUM_INIT(io_lane, /datum/io_lane, new)

#define IO_STAT_STARTED 1
#define IO_STAT_COMPLETED 2
#define IO_STAT_ERRORS 3
#define IO_STAT_DROPPED 4
#define IO_STAT_LAT_TOTAL 5
#define IO_STAT_LAT_MAX 6

/datum/io_lane/proc/count_stat(datum/io_backend/K, which, amount = 1)
	LAZYINITLIST(stats)
	var/list/S = stats[K.name]
	if(!S)
		S = stats[K.name] = list(0, 0, 0, 0, 0, 0)
	if(which == IO_STAT_LAT_MAX)
		S[which] = max(S[which], amount)
	else
		S[which] += amount

// ---------------------------------------------------------------- API

/// Starts an I/O job owned by E and returns at once: the job id, or 0 if E or a datum context arg is already gone. See the header for
/// the argument layout.
/proc/io_job(owner, backend_type, ...)
	var/datum/E = owner
	var/datum/io_backend/K = io_backend(backend_type)
	if(!K)
		CRASH("io_job: [backend_type] is not an I/O backend")
	if(length(args) < 3 + K.arg_count)
		CRASH("io_job: [backend_type] takes [K.arg_count] request args and a callback")
	var/owner_h = null
	if(!isnull(E))
		if(QDELETED(E))
			return 0
		owner_h = om_handle(E) // ALLOW(ownership): the IO lane keeps its own queue and a deletion-safe handle to the job owner
		if(!owner_h)
			return 0
	var/datum/io_job/J = new
	J.owner_h = owner_h
	J.backend_type = backend_type
	J.request = K.arg_count ? args.Copy(3, 3 + K.arg_count) : list()
	J.on_done = args[3 + K.arg_count]
	if(length(args) > 3 + K.arg_count)
		var/list/capture = capture_args(args.Copy(4 + K.arg_count))
		if(!capture)
			return 0
		J.context = capture[1]
		J.positions = capture[2]
	var/datum/io_lane/lane = GLOB.io_lane
	J.id = ++lane.seq
	J.queued_at = REALTIMEOFDAY
	LAZYADD(lane.jobs, J) // ALLOW(ownership): the IO lane keeps its own queue and a deletion-safe handle to the job owner
	io_try_start(lane, K, J)
	io_lane_wake(lane)
	return J.id

/// Cancels job `id`. The rust-g job still finishes; its result is discarded.
/proc/io_job_cancel(id)
	for(var/datum/io_job/J as anything in GLOB.io_lane.jobs)
		if(J.id == id)
			J.on_done = null
			return TRUE
	return FALSE

/proc/io_job_pending(id)
	for(var/datum/io_job/J as anything in GLOB.io_lane.jobs)
		if(J.id == id)
			return !isnull(J.on_done)
	return FALSE

/// Number of jobs not yet answered (all backends, or one).
/proc/io_job_count(backend_type)
	. = 0
	for(var/datum/io_job/J as anything in GLOB.io_lane.jobs)
		if(!backend_type || J.backend_type == backend_type)
			.++

/proc/io_active(datum/io_lane/lane, backend_type)
	. = 0
	for(var/datum/io_job/J as anything in lane.jobs)
		if(J.backend_type == backend_type && !isnull(J.job_id))
			.++

/// Hands `J` to rust-g if its backend has a free slot. A failed start is answered next pass.
/proc/io_try_start(datum/io_lane/lane, datum/io_backend/K, datum/io_job/J)
	if(!isnull(J.job_id) || J.preset_error)
		return
	var/limit = K.active_limit()
	if(limit && io_active(lane, J.backend_type) >= limit)
		return
	var/id = K.start(J)
	if(isnull(id))
		if(!J.preset_error)
			J.preset_error = "[K.name] start failed"
		return
	J.job_id = id
	J.started_at = REALTIMEOFDAY
	lane.count_stat(K, IO_STAT_STARTED)

/// Arms the lane's next pass (one tick from now) if it isn't already.
/proc/io_lane_wake(datum/io_lane/lane)
	if(after_pending(lane, "io_poll"))
		return
	after(lane, 0.1 SECONDS, TYPE_PROC_REF(/datum/io_lane, poll_pass), key = "io_poll", clock = CLOCK_WORLD)

/// The lane's after(): one pass, then the next while jobs are pending.
/datum/io_lane/proc/poll_pass()
	io_poll(src)
	if(length(jobs))
		io_lane_wake(src)

/// One pass of the I/O lane: check each pending job once, resuming at the cursor, until the tick's budget runs out. Answered jobs leave
/// the list before their callback runs.
/proc/io_poll(datum/io_lane/lane)
	var/list/jobs = lane.jobs
	if(!length(jobs))
		lane.cursor = 1
		return
	if(lane.cursor > length(jobs))
		lane.cursor = 1
	var/checked = 0
	var/total = length(jobs)
	while(checked < total && length(lane.jobs))
		jobs = lane.jobs
		if(lane.cursor > length(jobs))
			lane.cursor = 1
		var/datum/io_job/J = jobs[lane.cursor]
		checked++
		var/datum/io_backend/K = io_backend(J.backend_type)
		io_try_start(lane, K, J)
		var/raw = null
		var/answered = FALSE
		if(J.preset_error)
			answered = TRUE
		else if(!isnull(J.job_id))
			raw = K.check(J.job_id)
			if(raw != RUSTG_JOB_NO_RESULTS_YET)
				answered = TRUE
			else if(REALTIMEOFDAY - J.started_at > IO_JOB_TIMEOUT_DS)
				log_world("IO: [K.name] job [J.id] timed out after [IO_JOB_TIMEOUT_DS / 10]s; abandoning")
				J.preset_error = "[K.name] job timed out"
				answered = TRUE
		if(!answered)
			lane.cursor++
		else
			jobs.Cut(lane.cursor, lane.cursor + 1)
			if(!length(jobs))
				lane.jobs = null
			io_deliver(lane, K, J, raw)
		if(Kernel?.processing && TICK_USAGE >= Kernel.current_ticklimit)
			break
	if(lane.cursor > length(lane.jobs))
		lane.cursor = 1

/// Runs the callback for an answered job on its owner, if the owner and context still exist.
/proc/io_deliver(datum/io_lane/lane, datum/io_backend/K, datum/io_job/J, raw)
	var/list/outcome = J.preset_error ? list(null, J.preset_error) : K.decode(raw)
	if(J.started_at)
		var/latency = REALTIMEOFDAY - J.started_at
		lane.count_stat(K, IO_STAT_LAT_TOTAL, latency * 100)
		lane.count_stat(K, IO_STAT_LAT_MAX, latency * 100)
	lane.count_stat(K, IO_STAT_COMPLETED)
	if(outcome[2])
		lane.count_stat(K, IO_STAT_ERRORS)
	if(!J.on_done)
		lane.count_stat(K, IO_STAT_DROPPED)
		return
	var/datum/E = null
	if(J.owner_h)
		E = om_resolve(J.owner_h) // ALLOW(ownership): the IO lane keeps its own queue and a deletion-safe handle to the job owner
		if(!E)
			lane.count_stat(K, IO_STAT_DROPPED)
			log_qdel("IO: dropped [K.name] callback [J.on_done]: its owner was deleted")
			return
	var/list/captured = J.context ? J.context.Copy() : null
	if(captured && !resolve_captured(captured, J.positions))
		lane.count_stat(K, IO_STAT_DROPPED)
		log_qdel("IO: dropped [K.name] callback [J.on_done]: a captured argument was deleted")
		return
	var/list/call_args = list(outcome[1], outcome[2])
	if(captured)
		call_args += captured
	try
		om_guarded_call(E, J.on_done, call_args)
	catch(var/exception/e)
		dq_report_caught(e, "io [K.name] callback [J.on_done] on [E]")

/// Per backend: started, completed, errors, dropped, pending, queued and latency.
/proc/io_diagnostics()
	. = list()
	var/datum/io_lane/lane = GLOB.io_lane
	var/list/pending = list()
	var/list/queued = list()
	for(var/datum/io_job/J as anything in lane.jobs)
		var/datum/io_backend/K = io_backend(J.backend_type)
		if(isnull(J.job_id))
			queued[K.name] += 1
		else
			pending[K.name] += 1
	var/list/names = list()
	for(var/name in lane.stats)
		names[name] = TRUE
	for(var/name in pending)
		names[name] = TRUE
	for(var/name in queued)
		names[name] = TRUE
	for(var/name in names)
		var/list/S = lane.stats?[name] || list(0, 0, 0, 0, 0, 0)
		.[name] = list(
			"started" = S[IO_STAT_STARTED],
			"completed" = S[IO_STAT_COMPLETED],
			"errors" = S[IO_STAT_ERRORS],
			"dropped" = S[IO_STAT_DROPPED],
			"pending" = pending[name] || 0,
			"queued" = queued[name] || 0,
			"latency_avg_ms" = S[IO_STAT_COMPLETED] ? round(S[IO_STAT_LAT_TOTAL] / S[IO_STAT_COMPLETED], 0.1) : 0,
			"latency_max_ms" = S[IO_STAT_LAT_MAX],
		)

// ---------------------------------------------------------------- callers' helpers

/// io_job() callback for fire-and-forget writes: logs a failed query, nothing else.
/proc/io_log_sql_error(list/result, error, sql)
	if(error)
		log_sql("[error] | Query used: [sql]")

/// Fire-and-forget HTTP GET (webhooks); a failure is logged.
/proc/http_get_async(url)
	return io_job(null, /datum/io_backend/http, RUSTG_HTTP_METHOD_GET, url, "", null, GLOBAL_PROC_REF(io_log_http_error), url)

/proc/io_log_http_error(result, error, url)
	if(error)
		log_world("IO: HTTP GET failed ([error]): [url]")

#undef IO_STAT_STARTED
#undef IO_STAT_COMPLETED
#undef IO_STAT_ERRORS
#undef IO_STAT_DROPPED
#undef IO_STAT_LAT_TOTAL
#undef IO_STAT_LAT_MAX
