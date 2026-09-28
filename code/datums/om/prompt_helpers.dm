// Object-model core: small shared om_prompt continuations (doc/rewrite/object_model_core.md §4.11).
// Sites that asked the same question the same way share one of these instead of each writing
// its own continuation proc.

/// Asks for a new name and stores it in `var_name` (a bot assembly's created_name, a label).
/// The answer is re-checked: the user must still be next to or holding `src`.
/atom/proc/ask_name_var(mob/user, var_name = "created_name", message = "Enter new robot name", max_length = MAX_NAME_LEN)
	om_prompt(src, user, list("kind" = "text", "message" = message, "title" = name, "default" = vars[var_name], "max_length" = max_length, "encode" = FALSE, "requires" = PROMPT_ADJACENT, "data" = list("var" = var_name, "len" = max_length)), PROC_REF(name_var_entered))

/atom/proc/name_var_entered(mob/user, value, datum/om/prompt/ask)
	value = sanitizeSafe(value, ask.get("len"))
	if(value)
		vars[ask.get("var")] = value

// ---------------------------------------------------------------- Topic() handlers
//
// A Topic() handler asks with topic_prompt(): the first call shows the prompt and returns null
// (the handler returns); the answer re-enters Topic() with the same href_list plus the answer,
// so the handler re-runs every check it makes (rights, the target still existing) and this time
// topic_prompt() returns the answer. A handler that asks several things asks them in order, one
// re-entry each. `key` names the answer within the handler.

/datum/proc/topic_prompt(mob/user, list/href_list, key, list/spec)
	var/answer_key = "om_answer_[key]"
	if(!isnull(href_list[answer_key]))
		return href_list[answer_key]
	spec = spec.Copy()
	spec["data"] = list("href" = href_list.Copy(), "key" = answer_key)
	om_prompt(src, user, spec, /proc/om_topic_prompt_answered)
	return null

/proc/om_topic_prompt_answered(datum/E, mob/user, answer, datum/om/prompt/P)
	var/list/href_list = P.get("href")
	href_list[P.get("key")] = answer
	// Topic() handlers read usr; the answer arrives from the user's own tgui action, so this is
	// who it already is, but say so for answers delivered any other way.
	usr = user
	E.Topic(null, href_list)

// ---------------------------------------------------------------- tgui_act() handlers
//
// The same for a tgui_act() action: act_prompt() asks and returns null (the action returns);
// the answer re-runs the action with params[key] set while the window is still open and
// interactive (the base tgui_act() checks), so the action re-checks everything it checks.
// params["om_reentry"] is set on a re-run, for actions that log or charge once.

/datum/proc/act_prompt(mob/user, action, list/params, datum/tgui/ui, key, list/spec)
	var/answer_key = "om_answer_[key]"
	if(!isnull(params[answer_key]))
		return params[answer_key]
	spec = spec.Copy()
	spec["data"] = list("action" = action, "params" = params.Copy(), "ui" = ui, "key" = answer_key)
	om_prompt(src, user, spec, /proc/om_act_prompt_answered)
	return null

/proc/om_act_prompt_answered(datum/E, mob/user, answer, datum/om/prompt/P)
	var/datum/tgui/ui = P.get("ui")
	var/list/params = P.get("params")
	params[P.get("key")] = answer
	params["om_reentry"] = TRUE
	usr = user // tgui_act() handlers may read usr, as they do when the user clicks.
	if(E.tgui_act(P.get("action"), params, ui, ui.state()))
		SStgui.update_uis(E)

// ---------------------------------------------------------------- admin verbs
//
// An ADMIN_VERB body asks with verb_prompt(user, key, spec, args): the first run asks and
// returns null (the verb returns); the answer re-invokes the verb through
// SSadmin_verbs.dynamic_invoke_verb() (the rights check, usr) with the same arguments, and this
// time verb_prompt() returns the answer. Verb arguments that are datums are held as handles;
// the re-run is dropped if one is gone. Ask everything before doing anything: a verb runs once
// per answer.

/// Answers of the re-run in progress (verb_prompt), keyed like the prompts.
/datum/admin_verb/var/list/om_answers

/datum/admin_verb/proc/verb_prompt(client/user, key, list/spec, list/verb_args)
	if(om_answers && !isnull(om_answers[key]))
		return om_prompt_unwrap(om_answers[key])
	var/list/wrapped = list()
	for(var/i in 2 to length(verb_args))
		wrapped += list(om_prompt_wrap(verb_args[i]))
	spec = spec.Copy()
	spec["requires"] = PROMPT_ADMIN(permissions)
	spec["data"] = list("answers" = om_answers ? om_answers.Copy() : list(), "key" = key, "args" = wrapped)
	om_prompt(src, user, spec, /proc/om_verb_prompt_answered)
	return null

/proc/om_verb_prompt_answered(datum/admin_verb/V, mob/user, answer, datum/om/prompt/P)
	if(!user.client)
		return
	var/list/answers = P.get("answers")
	answers[P.get("key")] = om_prompt_wrap(answer)
	var/list/verb_args = list(user.client, V.type)
	for(var/wrapped in P.get("args"))
		var/value = om_prompt_unwrap(wrapped)
		if(isnull(value) && !isnull(wrapped))
			return
		verb_args += list(value)
	V.om_answers = answers
	try
		SSadmin_verbs.dynamic_invoke_verb(arglist(verb_args))
	catch(var/exception/e)
		V.om_answers = null
		stack_trace("admin verb [V.type] re-run: [e]")
		return
	V.om_answers = null

// ---------------------------------------------------------------- client procs
//
// The same for a /client proc (admin verbs that aren't ADMIN_VERBs): client_prompt(key, spec,
// PROC_REF(this proc), args) asks and returns null; the answer calls the proc again with the same
// arguments and returns the answer from the same client_prompt() call. Ask everything before
// doing anything. `rights` (R_* flags) are re-checked when the answer arrives.

/// Answers of the re-run in progress (client_prompt), and which proc they're for.
/client/var/list/om_answers
/client/var/om_answers_proc

/client/proc/client_prompt(key, list/spec, proc_name, list/proc_args, rights = 0)
	var/mine = om_answers && om_answers_proc == proc_name
	if(mine && !isnull(om_answers[key]))
		return om_prompt_unwrap(om_answers[key])
	var/list/wrapped = list()
	for(var/value in proc_args)
		wrapped += list(om_prompt_wrap(value))
	spec = spec.Copy()
	if(rights)
		spec["requires"] = PROMPT_ADMIN(rights)
	spec["data"] = list("answers" = mine ? om_answers.Copy() : list(), "key" = key, "args" = wrapped, "proc" = proc_name)
	om_prompt(src, src, spec, /proc/om_client_prompt_answered)
	return null

/proc/om_client_prompt_answered(client/C, mob/user, answer, datum/om/prompt/P)
	var/list/answers = P.get("answers")
	answers[P.get("key")] = om_prompt_wrap(answer)
	var/list/proc_args = list()
	for(var/wrapped in P.get("args"))
		var/value = om_prompt_unwrap(wrapped)
		if(isnull(value) && !isnull(wrapped))
			return
		proc_args += list(value)
	var/proc_name = P.get("proc")
	C.om_answers = answers
	C.om_answers_proc = proc_name
	usr = user // These procs are verbs and read usr.
	try
		call(C, proc_name)(arglist(proc_args))
	catch(var/exception/e)
		stack_trace("client prompt re-run [proc_name]: [e]")
	C.om_answers = null
	C.om_answers_proc = null

// ---------------------------------------------------------------- any proc
//
// rerun_prompt(user, key, spec, PROC_REF(this proc), args) is the same for any datum proc that
// asks before it acts (a panel's action handler, an interaction): the answer calls the proc on
// src again with the same arguments, and the same rerun_prompt() call returns it. Datum
// arguments are held as handles (the re-run is dropped if one is gone). Ask everything before
// doing anything; the proc re-checks whatever it checks.

/// Answers of the re-runs in progress, by "[REF(datum)]:[proc]".
GLOBAL_LIST_EMPTY(om_rerun_answers)

/datum/proc/rerun_prompt(mob/user, key, list/spec, proc_name, list/proc_args)
	var/list/answers = GLOB.om_rerun_answers["[REF(src)]:[proc_name]"]
	if(answers && !isnull(answers[key]))
		return om_prompt_unwrap(answers[key])
	var/list/wrapped = list()
	for(var/value in proc_args)
		wrapped += list(om_prompt_wrap(value))
	spec = spec.Copy()
	spec["data"] = list("answers" = answers ? answers.Copy() : list(), "key" = key, "args" = wrapped, "proc" = proc_name)
	om_prompt(src, user, spec, /proc/om_rerun_prompt_answered)
	return null

/proc/om_rerun_prompt_answered(datum/E, mob/user, answer, datum/om/prompt/P)
	var/list/answers = P.get("answers")
	answers[P.get("key")] = om_prompt_wrap(answer)
	var/list/proc_args = list()
	for(var/wrapped in P.get("args"))
		var/value = om_prompt_unwrap(wrapped)
		if(isnull(value) && !isnull(wrapped))
			return
		proc_args += list(value)
	var/proc_name = P.get("proc")
	var/id = "[REF(E)]:[proc_name]"
	GLOB.om_rerun_answers[id] = answers
	usr = user // Panel and admin procs read usr, as they did when first run.
	try
		call(E, proc_name)(arglist(proc_args))
	catch(var/exception/e)
		stack_trace("prompt re-run [proc_name] on [E]: [e]")
	GLOB.om_rerun_answers -= id
	SStgui.update_uis(E)

// ---------------------------------------------------------------- prompt flows
//
// A flow is an entry proc whose questions are asked deep below it, in helpers shared by many
// entries (View Variables' value picker, the type picker). The entry starts with
//	if(!GLOB.prompt_flow)
//		return prompt_flow(src, PROC_REF(this_proc), args)
// and every question below it is flow_ask(user, key, spec): null the first time (return), and
// the answer runs the entry again with the same arguments, where the same flow_ask() returns it.
// Entries reached inside a running flow just run, so keys must be unique in the whole flow.
// Everything is asked before anything is done.

/// The running flow: its asker (client or datum), entry proc and arguments. Null outside one.
GLOBAL_VAR(prompt_flow)

/proc/prompt_flow(asker, entry_proc, list/entry_args, rights = 0)
	if(GLOB.prompt_flow)
		return call(asker, entry_proc)(arglist(entry_args))
	GLOB.prompt_flow = list("asker" = asker, "proc" = entry_proc, "args" = entry_args.Copy(), "rights" = rights)
	try
		. = call(asker, entry_proc)(arglist(entry_args))
	catch(var/e)
		var/list/flow = GLOB.prompt_flow
		GLOB.prompt_flow = null
		if(e == OM_FLOW_PENDING) // a query is in flight (flow_io.dm); its answer re-runs the flow
			om_flow_unwound(flow)
			return null
		throw e
	GLOB.prompt_flow = null

/// Asks `user` a question of the running flow; null until the answer re-runs the flow.
/proc/flow_ask(mob/user, key, list/spec)
	var/list/flow = GLOB.prompt_flow
	if(!flow)
		CRASH("flow_ask([key]) outside a prompt flow")
	var/asker = flow["asker"]
	if(istype(asker, /client))
		var/client/C = asker
		return C.client_prompt(key, spec, flow["proc"], flow["args"], flow["rights"])
	var/datum/D = asker
	return D.rerun_prompt(user, key, spec, flow["proc"], flow["args"])
