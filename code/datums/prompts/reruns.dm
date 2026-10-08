// Re-run prompts on native requests (doc/rewrite/final_api.html section 13, "Requests, prompts and workflows"). The legacy half of the
// prompt layer, moved here from the object model's prompt helpers when it was retired: every question is a /datum/prompt request (open_request()), and these helpers
// only keep the legacy procs that ask before they act working until each becomes an op with asks() or a request() with its own
// handler.
//
// Some procs ask before they act and can't be split into an answer proc yet: a Topic() handler, an admin verb, a proc that asks
// several things in a row. (A Topic() handler is an op with asks() steps.) They ask with a re-run helper: the first call opens a prompt request and returns null (the proc returns);
// the answer runs the proc again with the same arguments, and this time the same helper call returns the answer (the request's
// `value`). The re-run re-checks everything the proc checks. Ask everything before doing anything: the proc runs once per answer.
//
//	var/amount = rerun_ask(user, "amount", PROC_REF(insert), args, /datum/prompt/number, question = "How many?", max_value = 10)
//	if(isnull(amount))
//		return
//
//   verb_ask(user, key, args, prompt, ...)                           an ADMIN_VERB body (the verb's rights are re-checked)
//   client_ask(key, PROC_REF(this proc), args, rights, prompt, ...)  a /client proc (`rights`: R_* re-checked)
//   rerun_ask(user, key, PROC_REF(this proc), args, prompt, ...)     any datum proc
//   flow_ask(user, key, prompt, ...)                                 a question deep inside a prompt_flow()
//
// `prompt` is a /datum/prompt kind; the named arguments are its fields (question, title, choices, default, ...), as open_request()
// takes them, plus `cancel_answer`: the answer a cancel, a closed window or a timeout gives instead (null: the re-run is dropped). A
// prompt waits as long as its window stays open unless it is given a `timeout`. A yes_no answered "no" is dropped like a cancel.
// The user and the datum re-run are held weakly while the question is open: the answer is dropped if either is gone.

/// A re-run record: the owner of the prompt request it opened, and what runs again when it is answered.
/datum/prompt_rerun
	/// The answer's name within the re-run proc.
	var/answer_key
	/// Who answers (wrapped: a handle, never a reference).
	var/actor_w
	/// What is re-run (wrapped), or null.
	var/target_w
	/// What a cancel answers instead, or null (a cancel drops the re-run).
	var/cancel_answer
	/// The request kind, to read a yes_no's "no" as a cancel.
	var/prompt_type

/// Opens the record's prompt for `user`. Null when it could not be shown (no user).
/datum/prompt_rerun/proc/ask(mob/user, prompt_type, list/fields)
	src.prompt_type = prompt_type
	var/list/opened = fields ? fields.Copy() : list()
	cancel_answer = opened["cancel_answer"]
	opened -= "cancel_answer"
	if(isnull(opened["timeout"]))
		opened["timeout"] = 0
	opened["answerer"] = user
	actor_w = rerun_wrap(user)
	return request_open(src, prompt_type, TYPE_PROC_REF(/datum/prompt_rerun, answered), opened)

/// The request ended: an answer (or the cancel answer) runs the asker again; anything else drops it.
/datum/prompt_rerun/proc/answered(datum/act/request/A)
	var/answer
	if(A.answer)
		answer = A.answer.value
		if(ispath(prompt_type, /datum/prompt/yes_no) && !answer)
			return
	else if(!isnull(cancel_answer))
		answer = cancel_answer
	else
		return
	if(isnull(answer))
		return
	if(rerun_was_ref(actor_w) && !rerun_unwrap(actor_w))
		return
	if(rerun_was_ref(target_w) && !rerun_unwrap(target_w))
		return
	rerun(answer)

/// Runs the asker again with `answer`.
/datum/prompt_rerun/proc/rerun(answer)
	return

/// The mob that answered.
/datum/prompt_rerun/proc/actor()
	return rerun_unwrap(actor_w)

/// The datum re-run.
/datum/prompt_rerun/proc/target()
	return rerun_unwrap(target_w)

// ---------------------------------------------------------------- weak arguments

/// A value held while a question is open: a client as its ckey, a datum as a handle, anything else as it is.
/proc/rerun_wrap(value)
	if(istype(value, /client))
		var/client/C = value
		return "ckey:[C.ckey]"
	if(isdatum(value))
		return list("rerun_h" = om_handle(value)) // ALLOW(ownership): a deletion-safe handle keeps a re-run from holding the datum alive
	return value

/proc/rerun_unwrap(value)
	if(istext(value) && copytext(value, 1, 6) == "ckey:")
		return GLOB.directory[copytext(value, 6)]
	if(islist(value) && length(value) == 1 && value["rerun_h"])
		return om_resolve(value["rerun_h"]) // ALLOW(ownership): a deletion-safe handle keeps a re-run from holding the datum alive
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

/// Starts a re-run record of `record_type` asking `prompt_type` (with `fields`) of `user`. `record_vars` set the record's own state.
/proc/rerun_begin(record_type, mob/user, datum/target, key, prompt_type, list/fields, list/record_vars)
	if(istype(user, /client))
		var/client/C = user
		user = C.mob
	if(!ismob(user))
		return
	var/datum/prompt_rerun/R = new record_type
	R.answer_key = key
	R.target_w = target ? rerun_wrap(target) : null
	for(var/name in record_vars)
		R.vars[name] = record_vars[name] // ALLOW(api): a re-run record's state set by name from its helper
	R.ask(user, prompt_type, fields)

// ---------------------------------------------------------------- re-runs keeping their answers
//
// Verbs and procs re-run with the same arguments; the answers given so far ride along and are read back by key. Datum arguments and
// answers are held weakly.

/datum/prompt_rerun/kept
	/// key -> wrapped answer, of every answer given in this chain so far.
	var/list/answers
	/// The re-run's arguments, wrapped.
	var/list/rerun_args

/datum/prompt_rerun/kept/rerun(answer)
	LAZYINITLIST(answers)
	answers[answer_key] = rerun_wrap(answer)
	var/list/unwrapped = rerun_unwrap_list(rerun_args)
	if(isnull(unwrapped))
		return
	usr = actor() // Verbs and panel procs read usr, as they did when first run.
	try
		run_again(unwrapped)
	catch(var/exception/e)
		stack_trace("[type] re-run: [e]")
	finished()

/// Calls the asker again with `unwrapped` (its arguments), `answers` visible to it.
/datum/prompt_rerun/kept/proc/run_again(list/unwrapped)
	return

/// Clears the answers the re-run could see.
/datum/prompt_rerun/kept/proc/finished()
	return

/// A previously given answer from a kept list, unwrapped (null if not given).
/proc/rerun_kept_answer(list/answers, key)
	if(!answers || isnull(answers[key]))
		return null
	return rerun_unwrap(answers[key])

// ---- admin verbs

/// Answers of the re-run in progress (verb_ask), keyed like the prompts.
/datum/admin_verb/var/list/rerun_answers

/datum/admin_verb/proc/verb_rerun_ask(client/user, key, list/verb_args, prompt_type, list/fields)
	if(rerun_answers && !isnull(rerun_answers[key]))
		return rerun_kept_answer(rerun_answers, key)
	var/list/rest = verb_args.Copy(2)
	var/list/asked = fields ? fields.Copy() : list()
	asked["rights"] = permissions
	asked["recheck_on_open"] = TRUE
	rerun_begin(/datum/prompt_rerun/kept/admin_verb, user, src, key, prompt_type, asked, list("answers" = rerun_answers?.Copy(), "rerun_args" = rerun_wrap_list(rest)))
	return null

/datum/prompt_rerun/kept/admin_verb/run_again(list/unwrapped)
	var/mob/user = actor()
	var/datum/admin_verb/V = target()
	if(!user?.client || !V)
		return
	V.rerun_answers = answers
	SSadmin_verbs.dynamic_invoke_verb(arglist(list(user.client, V.type) + unwrapped))

/datum/prompt_rerun/kept/admin_verb/finished()
	var/datum/admin_verb/V = target()
	if(V)
		V.rerun_answers = null

// ---- client procs

/// Answers of the re-run in progress (client_ask), and which proc they're for.
/client/var/list/rerun_answers
/client/var/rerun_answers_proc

/client/proc/client_rerun_ask(key, proc_name, list/proc_args, rights, prompt_type, list/fields)
	var/mine = rerun_answers && rerun_answers_proc == proc_name
	if(mine && !isnull(rerun_answers[key]))
		return rerun_kept_answer(rerun_answers, key)
	var/list/record_vars = list("answers" = mine ? rerun_answers.Copy() : null, "rerun_args" = rerun_wrap_list(proc_args), "asking_ckey" = ckey, "proc_name" = proc_name)
	var/list/asked = fields ? fields.Copy() : list()
	if(rights)
		asked["rights"] = rights
		asked["recheck_on_open"] = TRUE
	rerun_begin(/datum/prompt_rerun/kept/client, mob, null, key, prompt_type, asked, record_vars)
	return null

/datum/prompt_rerun/kept/client
	/// The asking client, by ckey while the prompt is open.
	var/asking_ckey
	var/proc_name

/datum/prompt_rerun/kept/client/run_again(list/unwrapped)
	var/client/C = GLOB.directory[asking_ckey]
	if(!C)
		return
	C.rerun_answers = answers
	C.rerun_answers_proc = proc_name
	call(C, proc_name)(arglist(unwrapped))

/datum/prompt_rerun/kept/client/finished()
	var/client/C = GLOB.directory[asking_ckey]
	if(C)
		C.rerun_answers = null
		C.rerun_answers_proc = null

// ---- any datum proc

/// Answers of the re-runs in progress, by "[REF(datum)]:[proc]".
GLOBAL_LIST_EMPTY(rerun_answers)

/datum/proc/rerun_ask_proc(mob/user, key, proc_name, list/proc_args, prompt_type, list/fields)
	var/list/answers = GLOB.rerun_answers["[REF(src)]:[proc_name]"]
	if(answers && !isnull(answers[key]))
		return rerun_kept_answer(answers, key)
	rerun_begin(/datum/prompt_rerun/kept/datum_proc, user, src, key, prompt_type, fields, list("answers" = answers?.Copy(), "rerun_args" = rerun_wrap_list(proc_args), "proc_name" = proc_name))
	return null

/datum/prompt_rerun/kept/datum_proc
	var/proc_name
	/// REF text of the datum re-run, for its answers' key.
	var/target_ref

/datum/prompt_rerun/kept/datum_proc/run_again(list/unwrapped)
	var/datum/T = target()
	if(!T)
		return
	target_ref = "[REF(T)]:[proc_name]"
	GLOB.rerun_answers[target_ref] = answers
	call(T, proc_name)(arglist(unwrapped))

/datum/prompt_rerun/kept/datum_proc/finished()
	if(!target_ref)
		return
	GLOB.rerun_answers -= target_ref
	var/datum/T = target()
	if(T)
		SStgui.update_uis(T)

// ---------------------------------------------------------------- prompt flows
//
// A prompt flow is an entry proc whose questions are asked deep below it, in helpers shared by many entries (View Variables' value
// picker, the type picker). The entry starts with
//	if(!GLOB.prompt_flow)
//		return prompt_flow(src, PROC_REF(this_proc), args)
// and every question below it is flow_ask(user, key, prompt, ...): null the first time (return), and the answer runs the entry again with
// the same arguments, where the same flow_ask() returns it. Entries reached inside a running flow just run, so keys must be unique in
// the whole flow. Everything is asked before anything is done.

/// The running prompt flow: its asker (client or datum), entry proc and arguments. Null outside one.
GLOBAL_VAR(prompt_flow)

/proc/prompt_flow(asker, entry_proc, list/entry_args, rights = 0)
	if(GLOB.prompt_flow)
		return call(asker, entry_proc)(arglist(entry_args))
	GLOB.prompt_flow = list("asker" = asker, "proc" = entry_proc, "args" = entry_args.Copy(), "rights" = rights)
	try
		. = call(asker, entry_proc)(arglist(entry_args))
	catch(var/e)
		GLOB.prompt_flow = null
		if(e == PROMPT_FLOW_PENDING)
			return null
		throw e
	GLOB.prompt_flow = null

/// flow_ask()'s body: asks `user` a question of the running prompt flow.
/proc/prompt_flow_ask(mob/user, key, prompt_type, list/fields)
	var/list/running = GLOB.prompt_flow
	if(!running)
		CRASH("flow_ask([key]) outside a prompt flow")
	var/asker = running["asker"]
	if(istype(asker, /client))
		var/client/C = asker
		return C.client_rerun_ask(key, running["proc"], running["args"], running["rights"], prompt_type, fields)
	var/datum/D = asker
	return D.rerun_ask_proc(user, key, running["proc"], running["args"], prompt_type, fields)

// ---------------------------------------------------------------- I/O inside prompt flows
//
// The same works for database answers: inside a running flow, `flow_select(sql, params)` starts the query as an I/O job
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
// Rules, as for flow_ask():
// - Everything the flow does before its last query runs once per answer. Do reads first and act after them; a write query in the
//   middle is fine (its stored result is replayed, it is not sent twice), but chat output and logs before a later query would repeat.
// - I/O answers are keyed by their order in the run ("io1", "io2", ...), so a re-run must make the same queries in the same order given
//   the same answers. flow_http_get() works the same way for HTTP.
// - The re-run re-checks: an asker client that left, a datum asker that was deleted, a user that logged out, or (with `rights`) a user
//   who lost the rights drops the answer.

/// The stored answers (prompts and queries) of the flow re-run in progress, or null.
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
	var/user_ckey = usr?.ckey
	var/list/call_args = list(null, backend_type) + request + list(GLOBAL_PROC_REF(prompt_flow_io_done), asker_w, flow["proc"], wrapped, answers ? answers.Copy() : list(), key, user_ckey, flow["rights"])
	io_job(arglist(call_args))
	throw PROMPT_FLOW_PENDING

/// The running flow's next query's rows (a list of positional row lists, empty for none), once its answer is stored; else starts it and
/// unwinds the flow (throws PROMPT_FLOW_PENDING). Null when the query failed (logged; `warn` also tells usr).
/proc/flow_select(sql, list/arguments, warn = FALSE)
	var/list/stored = flow_io_answer(/datum/io_backend/sql, list(sql, arguments))
	if(stored["error"])
		GLOB.prompt_flow["sql_error"] = "[stored["error"]]"
		log_sql("[stored["error"]] | Query used: [sql] | Arguments: [json_encode(arguments)]")
		if(warn)
			to_chat(usr, span_danger("A SQL error occurred during this operation, check the server logs.")) // ALLOW(sys_usr_outside_verb): a flow re-runs as its asker did: usr is restored for it (prompt_flow_rerun)
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
	var/mob/user
	if(user_ckey)
		var/client/UC = GLOB.directory[user_ckey]
		if(!UC)
			return
		user = UC.mob
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
	prompt_flow_rerun(asker, proc_name, proc_args, answers, user)

/// Runs a flow's entry again with its stored answers (shared by the query callback).
/proc/prompt_flow_rerun(asker, proc_name, list/proc_args, list/answers, mob/user)
	usr = user // Flow entries are verbs, panels and topics, and read usr as they did first.
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
