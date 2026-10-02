// Object-model core: SQL inside prompt flows (doc/rewrite/object_model_core.md §4.11, §4.12).
//
// A prompt flow (prompt_helpers.dm) is an entry proc that re-runs from the top each time an
// answer arrives. The same works for database answers: inside a running flow,
// `query.Execute()` (async, the default) starts the query as an om_io job and unwinds the
// flow; when the rows arrive the entry runs again with the same arguments and the same
// Execute() call - the flow's Nth query - returns at once with the stored result, so
// `NextRow()`/`item` read as they always did. Nothing waits.
//
//	/datum/admins/proc/show_things(page)
//		if(!GLOB.prompt_flow)
//			return prompt_flow(src, PROC_REF(show_things), args)
//		if(!check_rights(R_ADMIN))	// re-checked on every re-run
//			return
//		var/datum/db_query/Q = SSdbcore.NewQuery("SELECT ...", list(...))
//		if(!Q.Execute())		// the first run unwinds here; the re-run gets the rows
//			...
//
// Rules, as for flow_ask():
// - Everything the flow does before its last query runs once per answer. Do reads first and
//   act after them; a write query in the middle is fine (its stored result is replayed, it is
//   not sent twice), but chat output and logs before a later query would repeat.
// - I/O answers are keyed by their order in the run ("io1", "io2", ...), so a re-run must make
//   the same queries in the same order given the same answers (it does, if it only branches
//   on answers and on state it re-checks). flow_http_get() works the same way for HTTP.
// - The re-run re-checks: an asker client that left, a datum asker that was deleted, a user
//   that logged out, or (with `rights`) a user who lost the rights drops the answer.
// Execute(async = TRUE) outside a flow is an error (the legacy wait, db_query/sync(), is gone):
// use om_io(E, /datum/om/io/sql, ...) with a callback, or run the caller as a flow.
// Execute(async = FALSE) blocks, and is kept for boot and shutdown (dbcore.dm is exempt from the sync_sql
// lint by path; any other boot-only caller carries a justified-keep annotation for sys_sync_sql).

/// The stored answers (prompts and queries) of the flow re-run in progress, or null.
/proc/om_flow_answers()
	var/list/flow = GLOB.prompt_flow
	if(!flow)
		return null
	var/asker = flow["asker"]
	if(istype(asker, /client))
		var/client/C = asker
		if(C.om_answers && C.om_answers_proc == flow["proc"])
			return C.om_answers
		return null
	return GLOB.om_rerun_answers["[REF(asker)]:[flow["proc"]]"]

/// The running flow's next I/O answer: the stored outcome once it has arrived, else starts the
/// job (om_io, kind `kind_type` with `request` as its request args) and unwinds the flow
/// (throws OM_FLOW_PENDING). Outcomes: list("error" = text) on failure; SQL list("rows",
/// "affected", "last_insert_id"); HTTP list("status", "body"); any other kind list("value").
/proc/flow_io_answer(kind_type, list/request)
	var/list/flow = GLOB.prompt_flow
	if(!flow)
		CRASH("flow_io_answer([kind_type]) outside a prompt flow")
	flow["io_seq"] = (flow["io_seq"] || 0) + 1
	var/key = "io[flow["io_seq"]]"
	var/list/answers = om_flow_answers()
	var/list/stored = answers?[key]
	if(islist(stored))
		return stored
	var/asker = flow["asker"]
	var/asker_ref
	if(istype(asker, /client))
		var/client/AC = asker
		asker_ref = "ckey:[AC.ckey]"
	else
		asker_ref = om_handle(asker)
	var/list/wrapped = list()
	for(var/value in flow["args"])
		wrapped += list(om_prompt_wrap(value))
	var/user_ckey = usr?.ckey
	var/list/call_args = list(null, kind_type) + request + list(/proc/om_flow_io_done, asker_ref, flow["proc"], wrapped, answers ? answers.Copy() : list(), key, user_ckey, flow["rights"])
	om_io(arglist(call_args))
	throw OM_FLOW_PENDING

/// Runs `Q` as the running flow's next query: TRUE/FALSE (success) once its result is stored,
/// else starts it and unwinds the flow (throws OM_FLOW_PENDING).
/datum/db_query/proc/flow_execute()
	var/list/flow = GLOB.prompt_flow
	if(!flow)
		CRASH("flow_execute() outside a prompt flow")
	LAZYADD(flow["queries"], src)
	var/list/stored = flow_io_answer(/datum/om/io/sql, list(sql, arguments))
	Close()
	if(stored["error"])
		last_error = stored["error"]
		status = DB_QUERY_BROKEN
		log_sql("[last_error] | Query used: [sql] | Arguments: [json_encode(arguments)]")
		return FALSE
	rows = stored["rows"]
	affected = stored["affected"]
	last_insert_id = stored["last_insert_id"]
	next_row_to_take = 1
	status = DB_QUERY_FINISHED
	return TRUE

/// The running flow's next HTTP GET: list("status", "body"), or list("error") on failure.
/proc/flow_http_get(url)
	return flow_io_answer(/datum/om/io/http, list(RUSTG_HTTP_METHOD_GET, url, "", null))

/// om_io() callback: stores a flow job's outcome and runs the flow again.
/proc/om_flow_io_done(result, error, asker_ref, proc_name, list/wrapped, list/answers, key, user_ckey, rights)
	var/asker
	if(om_is_handle(asker_ref))
		asker = om_resolve(asker_ref)
	else
		asker = om_prompt_unwrap(asker_ref)
	if(!asker)
		return
	var/mob/user
	if(user_ckey)
		var/client/UC = GLOB.directory[user_ckey]
		if(!UC)
			return
		user = UC.mob
		if(rights && !check_rights_for(UC, rights))
			return
	var/list/proc_args = list()
	for(var/value in wrapped)
		var/unwrapped = om_prompt_unwrap(value)
		if(isnull(unwrapped) && !isnull(value))
			return
		proc_args += list(unwrapped)
	if(error)
		answers[key] = list("error" = "[error]")
	else if(istype(result, /datum/http_response))
		var/datum/http_response/R = result
		answers[key] = list("status" = R.status_code, "body" = R.body)
	else if(islist(result))
		var/list/L = result
		answers[key] = list("rows" = L["rows"], "affected" = L["affected"], "last_insert_id" = L["last_insert_id"])
	else // another kind's plain value
		answers[key] = list("value" = result)
	om_flow_rerun(asker, proc_name, proc_args, answers, user)

/// Runs a flow's entry again with its stored answers (shared by the query callback).
/proc/om_flow_rerun(asker, proc_name, list/proc_args, list/answers, mob/user)
	usr = user // Flow entries are verbs, panels and topics, and read usr as they did first.
	if(istype(asker, /client))
		var/client/C = asker
		C.om_answers = answers
		C.om_answers_proc = proc_name
		try
			call(C, proc_name)(arglist(proc_args))
		catch(var/exception/e)
			stack_trace("flow re-run [proc_name]: [e]")
		C.om_answers = null
		C.om_answers_proc = null
		return
	var/id = "[REF(asker)]:[proc_name]"
	GLOB.om_rerun_answers[id] = answers
	try
		call(asker, proc_name)(arglist(proc_args))
	catch(var/exception/e)
		stack_trace("flow re-run [proc_name] on [asker]: [e]")
	GLOB.om_rerun_answers -= id
	if(isdatum(asker))
		SStgui.update_uis(asker)

/// prompt_flow() calls this when the flow unwound on a pending query: the queries it made this
/// run are finished with (the re-run makes new ones).
/proc/om_flow_unwound(list/flow)
	for(var/datum/db_query/Q as anything in flow["queries"])
		qdel(Q)

// ---------------------------------------------------------------- panel views
//
// A panel whose tgui_data shows database rows can't query inside tgui_data. It fetches with
// om_sql_view(src, key, sql, arguments, PROC_REF(sql_rows_arrived)) when it opens or its
// filters change, keeps what its callback gets, and tgui_data reads that (showing "loading"
// until it arrives). The callback is a proc on the panel, called (result, error, key) like any
// om_io() callback; om_sql_view_rows() turns that into the rows. The job is owned by the
// panel: a closed (deleted) panel drops the answer. The callback re-checks whatever the panel
// requires (the viewer's rights) before keeping the rows.

/// Starts a read for a panel; on_rows(result, error, key) runs on `owner` with the answer.
/proc/om_sql_view(owner, key, sql, list/arguments, on_rows)
	return om_io(owner, /datum/om/io/sql, sql, arguments, on_rows, key)

/// The rows of an om_sql_view() answer (positional lists), or null (logged) on an error.
/proc/om_sql_view_rows(list/result, error, key, owner)
	if(error)
		log_sql("[error] | view [owner] [key]")
		return null
	return result["rows"] || list()

/// Runs one statement as the running flow's next query (the flow unwinds until it's answered)
/// and returns TRUE on success. For a write whose success the flow reads, or that a later read
/// in the same flow must see (om_sql_write() jobs run concurrently and aren't ordered).
/proc/flow_sql(sql, list/arguments)
	var/datum/db_query/Q = SSdbcore.NewQuery(sql, arguments)
	. = Q.Execute()
	qdel(Q)
