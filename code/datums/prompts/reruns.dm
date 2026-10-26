// Weak arguments and database answers for procs that run again (doc/rewrite/final_api.html section 13, "Requests, prompts and workflows").
// Questions are asked by sequences of asks (code/datums/prompts/sequence.dm) or by an op's asks() steps; what is left here is the prompt flow of the procs that
// read the database before they act (flow_select() and its relatives, below).

// ---------------------------------------------------------------- weak arguments

/// A value held while a question is open: a client as its ckey, a datum as a handle, anything else as it is.
/proc/rerun_wrap(value)
	if(istype(value, /client))
		var/client/C = value
		return "ckey:[C.ckey]"
	if(isdatum(value))
		return list("rerun_h" = ref_token(value))
	return value

/proc/rerun_unwrap(value)
	if(istext(value) && copytext(value, 1, 6) == "ckey:")
		return GLOB.directory[copytext(value, 6)]
	if(islist(value) && length(value) == 1 && value["rerun_h"])
		return resolve_token(value["rerun_h"])
	return value

/// TRUE when `wrapped` held a datum or client (so a null unwrap means it is gone).
/proc/rerun_was_ref(wrapped)
	return islist(wrapped) || (istext(wrapped) && copytext(wrapped, 1, 6) == "ckey:")

/// Wraps every value of a list (proc arguments held while a prompt waits).
/proc/rerun_wrap_list(list/values)
	. = list()
	for(var/value in values)
		. += list(rerun_wrap(value))

/// Unwraps rerun_wrap_list(); null if a datum in it is gone.
/proc/rerun_unwrap_list(list/wrapped)
	. = list()
	for(var/held in wrapped)
		var/value = rerun_unwrap(held)
		if(isnull(value) && rerun_was_ref(held))
			return null
		. += list(value)

// ---------------------------------------------------------------- re-run state
//
// The answers of the flow re-run in progress (stored database answers), on the asking client or, for a datum, by "[REF(datum)]:[proc]".

/// Answers of the re-run in progress (a prompt flow of a client), and which proc they're for.
/client/var/list/rerun_answers
/client/var/rerun_answers_proc

/// Answers of the re-runs in progress, by "[REF(datum)]:[proc]".
GLOBAL_LIST_EMPTY(rerun_answers)

// ---------------------------------------------------------------- prompt flows
//
// A prompt flow is an entry proc that reads the database (flow_select() and its relatives, below). The entry starts with
//	if(!GLOB.prompt_flow)
//		return prompt_flow(src, PROC_REF(this_proc), args)
// and every query below it is answered by a re-run of the entry with the same arguments. Entries reached inside a running flow just run.

/// The running prompt flow: its asker (client or datum), the ckey of the mob it runs as, entry proc and arguments. Null outside one.
GLOBAL_VAR(prompt_flow)

/// Starts a flow of `entry_proc` on `asker`. `actor` is the mob the flow runs as (whose ckey each answer re-finds, and who hears a failed query): the
/// asker's own mob for a client or a mob asker, else the one the entry names.
/proc/prompt_flow(asker, entry_proc, list/entry_args, rights = 0, mob/actor = null)
	if(GLOB.prompt_flow)
		return call(asker, entry_proc)(arglist(entry_args))
	if(!actor)
		if(istype(asker, /client))
			var/client/asking_client = asker
			actor = asking_client.mob
		else if(ismob(asker))
			actor = asker
	GLOB.prompt_flow = list("asker" = asker, "ckey" = actor?.ckey, "proc" = entry_proc, "args" = entry_args.Copy(), "rights" = rights)
	try
		. = call(asker, entry_proc)(arglist(entry_args))
	catch(var/e)
		GLOB.prompt_flow = null
		if(e == PROMPT_FLOW_PENDING)
			return null
		throw e
	GLOB.prompt_flow = null

// ---------------------------------------------------------------- I/O inside prompt flows
//
// Inside a running flow, `flow_select(sql, params)` starts the query as an I/O job
// (code/engine/io/jobs.dm) and unwinds the flow; when the rows arrive the entry runs again with the same arguments and the same
// flow_select() call - the flow's Nth query - returns at once with the stored rows. Nothing waits.
//
//	/datum/admins/proc/show_things(page)
//		if(!GLOB.prompt_flow)
//			return prompt_flow(src, PROC_REF(show_things), args)
//		if(!check_rights(R_ADMIN))	// re-checked on every re-run
//			return
//		var/list/rows = flow_select("SELECT a, b FROM t WHERE c = :c", list("c" = c))
//		if(isnull(rows))		// the first run unwinds above; the re-run gets the rows (null = the query failed)
//			...
//
// Rules:
// - Everything the flow does before its last query runs once per answer. Do reads first and act after them; a write query in the
//   middle is fine (its stored result is replayed, it is not sent twice), but chat output and logs before a later query would repeat.
// - I/O answers are keyed by their order in the run ("io1", "io2", ...), so a re-run must make the same queries in the same order given
//   the same answers. flow_http_get() works the same way for HTTP.
// - The re-run re-checks: an asker client that left, a datum asker that was deleted, a user that logged out, or (with `rights`) a user
//   who lost the rights drops the answer.

/// The stored answers (queries) of the flow re-run in progress, or null.
/proc/prompt_flow_answers()
	var/list/flow = GLOB.prompt_flow
	if(!flow)
		return null
	var/asker = flow["asker"]
	if(istype(asker, /client))
		var/client/C = asker
		if(C.rerun_answers && C.rerun_answers_proc == flow["proc"])
			return C.rerun_answers
		return null
	return GLOB.rerun_answers["[REF(asker)]:[flow["proc"]]"]

/// The running flow's next I/O answer: the stored outcome once it has arrived, else starts the job (io_job, backend `backend_type` with
/// `request` as its request args) and unwinds the flow (throws PROMPT_FLOW_PENDING). Outcomes: list("error" = text) on failure; SQL
/// list("rows", "affected", "last_insert_id"); HTTP list("status", "body"); any other backend list("value").
/proc/flow_io_answer(backend_type, list/request)
	var/list/flow = GLOB.prompt_flow
	if(!flow)
		CRASH("flow_io_answer([backend_type]) outside a prompt flow")
	flow["io_seq"] = (flow["io_seq"] || 0) + 1
	var/key = "io[flow["io_seq"]]"
	var/list/answers = prompt_flow_answers()
	var/list/stored = answers?[key]
	if(islist(stored))
		return stored
	var/asker = flow["asker"]
	var/asker_w = rerun_wrap(asker)
	var/list/wrapped = rerun_wrap_list(flow["args"])
	var/user_ckey = flow["ckey"]
	var/list/call_args = list(null, backend_type) + request + list(GLOBAL_PROC_REF(prompt_flow_io_done), asker_w, flow["proc"], wrapped, answers ? answers.Copy() : list(), key, user_ckey, flow["rights"])
	io_job(arglist(call_args))
	throw PROMPT_FLOW_PENDING

/// The running flow's next query's rows (a list of positional row lists, empty for none), once its answer is stored; else starts it and
/// unwinds the flow (throws PROMPT_FLOW_PENDING). Null when the query failed (logged; `warn` also tells the flow's actor).
/proc/flow_select(sql, list/arguments, warn = FALSE)
	var/list/stored = flow_io_answer(/datum/io_backend/sql, list(sql, arguments))
	if(stored["error"])
		GLOB.prompt_flow["sql_error"] = "[stored["error"]]"
		log_sql("[stored["error"]] | Query used: [sql] | Arguments: [json_encode(arguments)]")
		if(warn)
			var/client/flow_client = GLOB.directory[GLOB.prompt_flow["ckey"]]
			to_chat(flow_client?.mob, span_danger("A SQL error occurred during this operation, check the server logs."))
		return null
	return stored["rows"] || list()

/// The error text of the running flow's last failed flow_select().
/proc/flow_sql_error()
	return GLOB.prompt_flow?["sql_error"]

/// The running flow's next HTTP GET: list("status", "body"), or list("error") on failure.
/proc/flow_http_get(url)
	return flow_io_answer(/datum/io_backend/http, list(RUSTG_HTTP_METHOD_GET, url, "", null))

/// Runs one statement as the running flow's next query (the flow unwinds until it's answered) and returns TRUE on success. For a write
/// whose success the flow reads, or that a later read in the same flow must see (sql_write() jobs run concurrently and aren't ordered).
/proc/flow_sql(sql, list/arguments)
	return !isnull(flow_select(sql, arguments))

/// io_job() callback: stores a flow job's outcome and runs the flow again.
/proc/prompt_flow_io_done(result, error, asker_w, proc_name, list/wrapped, list/answers, key, user_ckey, rights)
	var/asker = rerun_unwrap(asker_w)
	if(!asker)
		return
	if(user_ckey)
		var/client/UC = GLOB.directory[user_ckey]
		if(!UC)
			return
		if(rights && !check_rights_for(UC, rights))
			return
	var/list/proc_args = rerun_unwrap_list(wrapped)
	if(isnull(proc_args))
		return
	if(error)
		answers[key] = list("error" = "[error]")
	else if(istype(result, /datum/http_response))
		var/datum/http_response/R = result
		answers[key] = list("status" = R.status_code, "body" = R.body)
	else if(islist(result))
		var/list/L = result
		answers[key] = list("rows" = L["rows"], "affected" = L["affected"], "last_insert_id" = L["last_insert_id"])
	else // another backend's plain value
		answers[key] = list("value" = result)
	prompt_flow_rerun(asker, proc_name, proc_args, answers)

/// Runs a flow's entry again with its stored answers (shared by the query callback). The entry starts its flow again, naming its actor as before.
/proc/prompt_flow_rerun(asker, proc_name, list/proc_args, list/answers)
	if(istype(asker, /client))
		var/client/C = asker
		C.rerun_answers = answers
		C.rerun_answers_proc = proc_name
		try
			call(C, proc_name)(arglist(proc_args))
		catch(var/exception/e)
			stack_trace("flow re-run [proc_name]: [e]")
		C.rerun_answers = null
		C.rerun_answers_proc = null
		return
	var/id = "[REF(asker)]:[proc_name]"
	GLOB.rerun_answers[id] = answers
	try
		call(asker, proc_name)(arglist(proc_args))
	catch(var/exception/e)
		stack_trace("flow re-run [proc_name] on [asker]: [e]")
	GLOB.rerun_answers -= id
	if(isdatum(asker))
		SStgui.update_uis(asker)

// ---------------------------------------------------------------- panel views
//
// A panel whose tgui_data shows database rows can't query inside tgui_data. It fetches with sql_view(src, key, sql, arguments,
// PROC_REF(sql_rows_arrived)) when it opens or its filters change, keeps what its callback gets, and tgui_data reads that (showing
// "loading" until it arrives). The callback is a proc on the panel, called (result, error, key) like any io_job() callback;
// sql_view_rows() turns that into the rows. The job is owned by the panel: a closed (deleted) panel drops the answer.

/// Starts a read for a panel; on_rows(result, error, key) runs on `owner` with the answer.
/proc/sql_view(owner, key, sql, list/arguments, on_rows)
	return io_job(owner, /datum/io_backend/sql, sql, arguments, on_rows, key)

/// The rows of an sql_view() answer (positional lists), or null (logged) on an error.
/proc/sql_view_rows(list/result, error, key, owner)
	if(error)
		log_sql("[error] | view [owner] [key]")
		return null
	return result["rows"] || list()

// ---------------------------------------------------------------- shared questions

/// A name typed into one of the asker's vars (a bot assembly's created_name, a label). The user must still be next to the atom and able.
/datum/prompt/text/name_var
	name_text = TRUE
	encode = FALSE
	ask_flags = ASK_ADJACENT | ASK_CAPABLE
	max_len = MAX_NAME_LEN
	/// The var of the asking atom the name goes into.
	var/var_name

/// Asks for a new name and stores it in `var_name`.
/atom/proc/ask_name_var(mob/user, var_name = "created_name", message = "Enter new robot name", max_length = MAX_NAME_LEN)
	open_request(src, /datum/prompt/text/name_var, PROC_REF(name_var_entered), answerer = user, question = message, title = name, default = vars[var_name], max_len = max_length, var_name = var_name)

/atom/proc/name_var_entered(datum/act/request/A)
	var/datum/prompt/text/name_var/asked = A.answer
	if(!asked)
		return
	var/value = sanitizeSafe(asked.value, asked.max_len)
	if(value)
		vars[asked.var_name] = value // ALLOW(api): ask_name_var() writes the var its caller named

/// The types under `root` whose path contains `text` (a type picker's matches).
/proc/typepaths_matching(text, root)
	READS_FROM() // reads the type tree, which no state changes at run time
	var/list/matches = list()
	for(var/path in typesof(root))
		if(findtext("[path]", text))
			matches += path
	return matches
