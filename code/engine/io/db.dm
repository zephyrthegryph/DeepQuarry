// The database on one path (doc/rewrite/final_api.html, section 2 "The database"; section 19 "E6").
//
// Content has two forms: a /datum/io/sql request, and sql_write() for a write nobody waits on.
//
//     open_request(src, /datum/io/sql/load_notes, PROC_REF(have_notes), ckey = ckey)
//     /datum/io/sql/load_notes
//         query = "SELECT note, author FROM notes WHERE ckey = :ckey"
//         row_type = /datum/io/sql/row/note
//         var/ckey
//     /datum/io/sql/row/note
//         var/note
//         var/author
//
// A request kind declares its query once. Each `:field` in it binds the request's own var of that name, and an answer's `rows` is
// a list of `row_type` datums, one per result row, each column (by position) a var of the row type, in declaration order. A query that is expected to return rows
// and matches nothing ends REQ_NO_RESULT, not an empty answer (`expects_rows = FALSE` marks a write). A connection that is
// down, or a query the server refuses, ends REQ_TRANSPORT_FAILED with `last_error` set. Nothing waits: the work runs on the I/O
// lane (datums/om/io.dm) and the answer arrives through the request's handler.
//
// SSdb owns the path's accounting; the connection itself is SSdbcore's (connect, disconnect, query_blocking). Code that is a prompt flow
// reads with flow_select() (datums/om/flow_io.dm).
//
// db_query_now() blocks its caller. It exists for the places BYOND itself waits: world/IsBanned, the boot loads and schema check,
// and the shutdown flush.

SYSTEM_DEF(db)
	name = "Database path"
	phase = KERNEL_PHASE_K
	latency_class = LATENCY_L0
	needs = list(/datum/system/dbcore)
	/// Requests started, answered, found nothing, and failed, since boot.
	var/started = 0
	var/answered = 0
	var/no_result = 0
	var/failed = 0
	/// Fire-and-forget writes handed to the I/O lane.
	var/writes = 0
	/// TRUE/FALSE overrides the connection answer (test builds); null asks SSdbcore.
	var/connected_override

/datum/system/db/proc/count_started()
	started++

/// TRUE when the database connection is up.
/datum/system/db/proc/connected()
	if(!isnull(connected_override))
		return connected_override
	return !!SSdbcore?.IsConnected()

/datum/system/db/metrics()
	. = ..()
	.["started"] = started
	.["answered"] = answered
	.["no_result"] = no_result
	.["failed"] = failed
	.["writes"] = writes

/// A fire-and-forget write (an insert or update nobody reads back), parameterized only: `query` uses :name placeholders filled
/// from `params`, and table names go through format_table_name(). Returns 0 when there is no connection (nothing is queued);
/// a failed write is logged to the SQL log with its query.
/proc/sql_write(query, list/params)
	if(!SSdb.connected())
		return 0
	SSdb.writes++
	return io_job(null, /datum/io_backend/sql, query, params, GLOBAL_PROC_REF(io_log_sql_error), query)

/// Runs `query` and waits for it: a blocking call, for the places BYOND itself waits (world/IsBanned, the boot schema check and the
/// boot-only loads), and for the shutdown flush once the I/O lane has stopped. The lint allows it nowhere else and accepts no ALLOW.
/// Returns the row lists, an empty list for no rows, or null when there is no connection or the query failed.
/proc/db_query_now(query, list/params)
	var/list/result = db_exec_now(query, params)
	if(!result)
		return null
	return result["rows"] || list()

/// db_query_now()'s full answer: list("rows", "affected", "last_insert_id"), or null (logged) when there is no connection or the
/// query failed.
/proc/db_exec_now(query, list/params)
	if(!SSdbcore?.IsConnected())
		return null
	var/raw = SSdbcore.query_blocking(query, params)
	var/list/decoded = io_backend(/datum/io_backend/sql).decode(raw)
	var/list/result = decoded[1]
	if(!result)
		log_sql("[decoded[2]] | Query used: [query]")
		return null
	return result

// ---------------------------------------------------------------- the request kind

/// A result row: its columns are the vars of the declared row_type, in the order the query selects them. A plain datum (the row types live under /datum/io/sql by name
/// only), never a request.
/datum/io/sql/row
	parent_type = /datum

/// A database query as a request. A kind sets `query` and (for a read) `row_type`, and declares a var for each :field.
/datum/io/sql
	abstract_type = /datum/io/sql
	/// The parameterized query. Each :field binds this request's var of that name.
	var/query
	/// The type of one answer row.
	var/row_type = /datum/io/sql/row
	/// TRUE for a read: a query that matches nothing ends REQ_NO_RESULT. A write sets FALSE.
	var/expects_rows = TRUE
	/// The answer: one row_type datum per result row, and the counts a write reports.
	var/list/rows
	var/affected = 0
	var/last_insert_id

/// The :field names a query binds, in order of appearance, each once.
/datum/io/sql/proc/bound_fields()
	. = list()
	var/query_length = length(query)
	var/at = 1
	while(at <= query_length)
		var/colon = findtext(query, ":", at)
		if(!colon)
			break
		var/end = colon + 1
		while(end <= query_length)
			var/code = text2ascii(query, end)
			if(!((code >= 48 && code <= 57) || (code >= 65 && code <= 90) || (code >= 97 && code <= 122) || code == 95))
				break
			end++
		var/name = copytext(query, colon + 1, end)
		if(length(name) && !(name in .))
			. += name
		at = max(end, colon + 1)

/// The names of the columns a result row carries, in order: the row_type's own vars in declaration order (the database returns
/// a row's columns by position, so the query selects them in that order).
/datum/io/sql/proc/row_columns()
	var/static/list/base_vars
	if(!base_vars)
		var/datum/io/sql/row/plain = new
		base_vars = plain.vars.Copy()
	var/datum/io/sql/row/sample = new row_type
	. = list()
	for(var/name in sample.vars)
		if(!(name in base_vars))
			. += name

/// The arguments the query binds: the request's own vars, by :field name.
/datum/io/sql/proc/arguments()
	. = list()
	for(var/name in bound_fields())
		if(!(name in vars))
			CRASH("[type] binds :[name] but declares no var of that name")
		.[name] = vars[name]

/datum/io/sql/begin()
	SSdb.count_started()
	if(!length(query))
		CRASH("[type] has no query")
	if(!SSdb.connected())
		fail_transport("No connection!")
		return
	run_backend()

/// Hands the query to the I/O lane. A test kind overrides this to answer without a database.
/datum/io/sql/proc/run_backend()
	io_job(src, /datum/io_backend/sql, query, arguments(), TYPE_PROC_REF(/datum/io/sql, sql_done))

/// The I/O lane's answer: `result` is list("rows", "affected", "last_insert_id"), or null with `error`.
/datum/io/sql/proc/sql_done(list/result, error)
	if(!is_open())
		return
	if(isnull(result))
		SSdb.failed++
		last_error = error
		request_end(src, REQ_TRANSPORT_FAILED, null)
		return
	affected = result["affected"] || 0
	last_insert_id = result["last_insert_id"]
	var/list/raw_rows = result["rows"]
	if(expects_rows && !length(raw_rows))
		SSdb.no_result++
		request_end(src, REQ_NO_RESULT, null)
		return
	var/list/names = row_columns()
	rows = list()
	for(var/list/columns as anything in raw_rows)
		var/datum/io/sql/row/row = new row_type
		for(var/index in 1 to min(length(columns), length(names)))
			row.vars[names[index]] = columns[index]
		rows += row // ALLOW(ownership): the answer rows are plain datums owned by this request until it ends
	SSdb.answered++
	request_end(src, REQ_ANSWERED, rows)

// ---------------------------------------------------------------- http

/// An HTTP request as a request kind: a webhook or a fetch. The answer is the response's status and body.
/datum/io/http
	abstract_type = /datum/io/http
	var/url
	/// RUSTG_HTTP_METHOD_*.
	var/method = RUSTG_HTTP_METHOD_GET
	var/body = ""
	var/list/headers
	/// The answer.
	var/status_code
	var/response_body
	var/list/response_headers

/datum/io/http/begin()
	if(!length(url))
		CRASH("[type] has no url")
	io_job(src, /datum/io_backend/http, method, url, body, headers, TYPE_PROC_REF(/datum/io/http, http_done))

/datum/io/http/proc/http_done(datum/http_response/response, error)
	if(!is_open())
		return
	if(!response)
		last_error = error
		request_end(src, REQ_TRANSPORT_FAILED, null)
		return
	status_code = response.status_code
	response_body = response.body
	response_headers = response.headers
	request_end(src, REQ_ANSWERED, response_body)
