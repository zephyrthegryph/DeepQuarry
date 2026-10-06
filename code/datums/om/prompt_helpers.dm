// Object-model core: re-run prompts (doc/rewrite/object_model_core.md §4.11).
//
// Some procs ask before they act and can't be split into an answer proc: a Topic() or
// tgui_act() handler, an admin verb, a proc that asks several things in a row. They ask with a
// re-run helper: the first call opens a typed prompt (ask.dm) and returns null (the proc
// returns); the answer runs the proc again with the same arguments, and this time the same
// helper call returns the answer (the kind's answer_value()). The re-run re-checks everything
// the proc checks. Ask everything before doing anything: the proc runs once per answer.
//
// Every helper is a macro taking the prompt kind and its named arguments, like om_ask():
//
//	var/amount = rerun_ask(user, "amount", PROC_REF(insert), args, /datum/om/prompt/number, message = "How many?", max = 10)
//	if(isnull(amount))
//		return
//
//   topic_ask(user, href_list, key, prompt, ...)             a Topic() handler
//   verb_ask(user, key, args, prompt, ...)                   an ADMIN_VERB body (the verb's rights are re-checked)
//   client_ask(key, PROC_REF(this proc), args, rights, prompt, ...)   a /client proc (`rights`: R_* re-checked)
//   rerun_ask(user, key, PROC_REF(this proc), args, prompt, ...)      any datum proc
//   flow_ask(user, key, prompt, ...)                         a question deep inside a prompt_flow()
//
// Each is a small flow (flow.dm): the user is its actor and the datum re-run its target, so the
// answer is dropped if either is gone, and datum arguments are held as handles while it waits.

/// Starts a re-run flow of `flow_type` asking `prompt` (with `fields`). `vars` set the flow's own state.
/proc/om_rerun_begin(flow_type, mob/user, datum/target, key, prompt, list/fields, list/flow_vars)
	if(istype(user, /client))
		var/client/C = user
		user = C.mob
	if(!ismob(user))
		return
	flow_vars["answer_key"] = key
	flow_vars["prompt"] = prompt
	flow_vars["fields"] = fields
	om_flow_begin(flow_type, user, target, flow_vars)

/// A re-run: asks one typed prompt, then runs whatever asked it again with the answer.
/datum/om/flow/rerun
	name = "rerun"
	/// The answer's name within the re-run proc.
	var/answer_key
	/// The prompt kind and its named arguments (handed to om_ask_begin() by start()).
	var/prompt
	var/list/fields

/datum/om/flow/rerun/start()
	var/list/prompt_fields = fields
	fields = null
	om_ask_begin(src, actor, prompt, PROC_REF(answered), prompt_fields)

/datum/om/flow/rerun/proc/answered(datum/om/prompt/P)
	rerun(P.answer_value())

/// Runs the asker again with `answer`.
/datum/om/flow/rerun/proc/rerun(answer)
	return

// ---------------------------------------------------------------- Topic() handlers
//
// The answer re-enters the TOPIC_ACTION dispatcher with the same href_list plus the answer;
// `key` names it. A handler passes its args list (the raw href_list is args[TOPIC_HREF]).

/datum/proc/om_topic_ask(mob/user, list/href_list, key, prompt, list/fields)
	// A TOPIC_ACTION handler passes its args list: the raw href_list rides in it.
	if(islist(href_list[TOPIC_HREF]))
		href_list = href_list[TOPIC_HREF]
	var/answer_key = "om_answer_[key]"
	if(!isnull(href_list[answer_key]))
		return href_list[answer_key]
	om_rerun_begin(/datum/om/flow/rerun/topic, user, src, answer_key, prompt, fields, list("href_list" = href_list.Copy()))
	return null

/datum/om/flow/rerun/topic
	var/list/href_list

/datum/om/flow/rerun/topic/rerun(answer)
	href_list[answer_key] = answer
	// Topic() handlers read usr; the answer arrives from the user's own tgui action, so this is
	// who it already is, but say so for answers delivered any other way.
	usr = actor
	topic_dispatch(target, actor, href_list)

// ---------------------------------------------------------------- re-runs keeping their answers
//
// Verbs and procs re-run with the same arguments; the answers given so far ride along and are
// read back by key. Datum arguments and answers are held as handles.

/datum/om/flow/rerun/kept
	/// key -> wrapped answer, of every answer given in this chain so far.
	var/list/answers
	/// The re-run's arguments, wrapped.
	var/list/rerun_args

/datum/om/flow/rerun/kept/rerun(answer)
	LAZYINITLIST(answers)
	answers[answer_key] = om_prompt_wrap(answer)
	var/list/unwrapped = om_prompt_unwrap_list(rerun_args)
	if(isnull(unwrapped))
		return
	usr = actor // Verbs and panel procs read usr, as they did when first run.
	try
		run_again(unwrapped)
	catch(var/exception/e)
		stack_trace("[type] re-run: [e]")
	finished()

/// Calls the asker again with `unwrapped` (its arguments), `answers` visible to it.
/datum/om/flow/rerun/kept/proc/run_again(list/unwrapped)
	return

/// Clears the answers the re-run could see.
/datum/om/flow/rerun/kept/proc/finished()
	return

/// A previously given answer from a kept list, unwrapped (null if not given).
/proc/om_kept_answer(list/answers, key)
	if(!answers || isnull(answers[key]))
		return null
	return om_prompt_unwrap(answers[key])

// ---- admin verbs

/// Answers of the re-run in progress (verb_ask), keyed like the prompts.
/datum/admin_verb/var/list/om_answers

/datum/admin_verb/proc/om_verb_ask(client/user, key, list/verb_args, prompt, list/fields)
	if(om_answers && !isnull(om_answers[key]))
		return om_kept_answer(om_answers, key)
	var/list/rest = verb_args.Copy(2)
	om_rerun_begin(/datum/om/flow/rerun/kept/admin_verb, user, src, key, prompt, fields, list("answers" = om_answers?.Copy(), "rerun_args" = om_prompt_wrap_list(rest), "requires" = PROMPT_ADMIN(permissions)))
	return null

/datum/om/flow/rerun/kept/admin_verb/run_again(list/unwrapped)
	var/mob/user = actor
	var/datum/admin_verb/V = target
	if(!user.client)
		return
	V.om_answers = answers
	SSadmin_verbs.dynamic_invoke_verb(arglist(list(user.client, V.type) + unwrapped))

/datum/om/flow/rerun/kept/admin_verb/finished()
	var/datum/admin_verb/V = target
	if(V)
		V.om_answers = null

// ---- client procs

/// Answers of the re-run in progress (client_ask), and which proc they're for.
/client/var/list/om_answers
/client/var/om_answers_proc

/client/proc/om_client_ask(key, proc_name, list/proc_args, rights, prompt, list/fields)
	var/mine = om_answers && om_answers_proc == proc_name
	if(mine && !isnull(om_answers[key]))
		return om_kept_answer(om_answers, key)
	var/list/flow_vars = list("answers" = mine ? om_answers.Copy() : null, "rerun_args" = om_prompt_wrap_list(proc_args), "asking_client" = src, "proc_name" = proc_name)
	if(rights)
		flow_vars["requires"] = PROMPT_ADMIN(rights)
	om_rerun_begin(/datum/om/flow/rerun/kept/client, mob, null, key, prompt, fields, flow_vars)
	return null

/datum/om/flow/rerun/kept/client
	/// Held by ckey while the prompt is open.
	var/client/asking_client
	var/proc_name

/datum/om/flow/rerun/kept/client/run_again(list/unwrapped)
	asking_client.om_answers = answers
	asking_client.om_answers_proc = proc_name
	call(asking_client, proc_name)(arglist(unwrapped))

/datum/om/flow/rerun/kept/client/finished()
	if(asking_client)
		asking_client.om_answers = null
		asking_client.om_answers_proc = null

// ---- any datum proc

/// Answers of the re-runs in progress, by "[REF(datum)]:[proc]".
GLOBAL_LIST_EMPTY(om_rerun_answers)

/datum/proc/om_rerun_ask(mob/user, key, proc_name, list/proc_args, prompt, list/fields)
	var/list/answers = GLOB.om_rerun_answers["[REF(src)]:[proc_name]"]
	if(answers && !isnull(answers[key]))
		return om_kept_answer(answers, key)
	om_rerun_begin(/datum/om/flow/rerun/kept/datum_proc, user, src, key, prompt, fields, list("answers" = answers?.Copy(), "rerun_args" = om_prompt_wrap_list(proc_args), "proc_name" = proc_name))
	return null

/datum/om/flow/rerun/kept/datum_proc
	var/proc_name

/datum/om/flow/rerun/kept/datum_proc/run_again(list/unwrapped)
	GLOB.om_rerun_answers["[REF(target)]:[proc_name]"] = answers
	call(target, proc_name)(arglist(unwrapped))

/datum/om/flow/rerun/kept/datum_proc/finished()
	if(!target)
		return
	GLOB.om_rerun_answers -= "[REF(target)]:[proc_name]"
	SStgui.update_uis(target)

// ---------------------------------------------------------------- prompt flows
//
// A prompt flow is an entry proc whose questions are asked deep below it, in helpers shared by
// many entries (View Variables' value picker, the type picker). The entry starts with
//	if(!GLOB.prompt_flow)
//		return prompt_flow(src, PROC_REF(this_proc), args)
// and every question below it is flow_ask(user, key, prompt, ...): null the first time
// (return), and the answer runs the entry again with the same arguments, where the same
// flow_ask() returns it. Entries reached inside a running flow just run, so keys must be unique
// in the whole flow. Everything is asked before anything is done.

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
		if(e == OM_FLOW_PENDING)
			return null
		throw e
	GLOB.prompt_flow = null

/// flow_ask()'s body: asks `user` a question of the running prompt flow.
/proc/om_flow_ask(mob/user, key, prompt, list/fields)
	var/list/running = GLOB.prompt_flow
	if(!running)
		CRASH("flow_ask([key]) outside a prompt flow")
	var/asker = running["asker"]
	if(istype(asker, /client))
		var/client/C = asker
		return C.om_client_ask(key, running["proc"], running["args"], running["rights"], prompt, fields)
	var/datum/D = asker
	return D.om_rerun_ask(user, key, running["proc"], running["args"], prompt, fields)

// ---------------------------------------------------------------- shared questions

/// A name typed into one of the asker's vars (a bot assembly's created_name, a label). The user
/// must still be next to or holding the atom.
/datum/om/prompt/text/name_var
	requires = PROMPT_ADJACENT
	encode = FALSE
	max_length = MAX_NAME_LEN
	var/var_name

/// Asks for a new name and stores it in `var_name`.
/atom/proc/ask_name_var(mob/user, var_name = "created_name", message = "Enter new robot name", max_length = MAX_NAME_LEN)
	om_ask(user, /datum/om/prompt/text/name_var, PROC_REF(name_var_entered), message = message, title = name, default = vars[var_name], max_length = max_length, var_name = var_name)

/atom/proc/name_var_entered(datum/om/prompt/text/name_var/ask)
	var/value = sanitizeSafe(ask.text, ask.max_length)
	if(value)
		vars[ask.var_name] = value
