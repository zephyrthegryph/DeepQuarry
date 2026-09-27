// Object-model core: prompts without sleeping (doc/rewrite/object_model_core.md §4.11).
//
// om_prompt(E, user, spec, on_answer) shows `user` a tgui input and returns at once. When the
// user answers, E and the user are resolved from handles and the spec's `requires` are
// re-checked (actor = user, target = E) before on_answer runs, so an answer that arrives after
// the user walked away, died, or E was deleted does nothing. No proc waits on the answer.
//
// spec keys:
//   "kind"     "alert" (buttons), "list" (choices), "text" or "number". Default "alert".
//   "message", "title"
//   "choices"  alert buttons or list items
//   "default", "min", "max", "timeout" (deciseconds)
//   "requires" check specs re-checked before on_answer (check.dm)
//   "on_refused" proc called like on_answer, with the refusal reason, when a re-check fails
// on_answer: a type proc called on E as (user, answer), or a global proc called as (E, user, answer).

/datum/om/prompt
	/// Handles (timer.dm): the prompt never keeps E or the user alive.
	var/entity_h
	var/user_h
	var/list/spec
	var/on_answer
	var/answered = FALSE
	/// The tgui input showing it, if any.
	var/datum/ui

/// Test schedulers collect prompts here instead of opening a window.
/datum/om/scheduler/var/list/test_prompts

/// Asks `user` and calls `on_answer` with the answer later. Returns the prompt, or null if E
/// or the user is gone or has no client (outside tests).
/proc/om_prompt(datum/E, mob/user, list/spec, on_answer)
	if(isnull(E))
		E = om_global_owner()
	var/eh = om_handle(E)
	var/uh = om_handle(user)
	if(!eh || !uh)
		return null
	var/datum/om/prompt/P = new
	P.entity_h = eh
	P.user_h = uh
	P.spec = spec || list()
	P.on_answer = on_answer
	var/datum/om/scheduler/sched = om_scheduler()
	if(sched.test_prompts)
		sched.test_prompts += P
		return P
	if(!user.client)
		return null
	P.ui = om_prompt_show(P, user)
	return P.ui ? P : null

/// Delivers an answer (tgui, or a test). Returns null when on_answer ran, else the reason it did not.
/proc/om_prompt_answer(datum/om/prompt/P, answer)
	if(P.answered)
		return "answered"
	P.answered = TRUE
	P.ui = null
	var/datum/E = om_resolve(P.entity_h)
	var/mob/user = om_resolve(P.user_h)
	if(!E || !user)
		return "gone"
	if(isnull(answer))
		return "no answer"
	for(var/check_spec in om_spec_list(P.spec["requires"]))
		var/reason = om_why_not(check_spec, user, E)
		if(!isnull(reason))
			if(P.spec["on_refused"])
				om_prompt_call(E, P.spec["on_refused"], user, reason)
			return reason
	om_prompt_call(E, P.on_answer, user, answer)
	return null

/proc/om_prompt_call(datum/E, proc_ref, mob/user, value)
	try
		if(copytext("[proc_ref]", 1, 7) == "/proc/")
			call(proc_ref)(E, user, value)
		else
			call(E, proc_ref)(user, value)
	catch(var/exception/e)
		stack_trace("om prompt [proc_ref] on [E]: [e]")

/// The user closed the window without answering.
/proc/om_prompt_closed(datum/om/prompt/P)
	if(!P.answered)
		P.answered = TRUE
		P.ui = null

// ---------------------------------------------------------------- tgui

/proc/om_prompt_show(datum/om/prompt/P, mob/user)
	var/list/S = P.spec
	var/timeout = S["timeout"] || 0
	switch(S["kind"] || "alert")
		if("list")
			var/datum/tgui_list_input/om/L = new(user, S["message"], S["title"] || "Select", S["choices"], S["default"], timeout, GLOB.tgui_always_state)
			if(L.invalid)
				qdel(L)
				return null
			L.om_prompt = P
			L.tgui_interact(user)
			return L
		if("text")
			var/datum/tgui_input_text/om/T = new(user, S["message"], S["title"] || "Text Input", S["default"], MAX_TGUI_INPUT, FALSE, TRUE, timeout, GLOB.tgui_always_state)
			T.om_prompt = P
			T.tgui_interact(user)
			return T
		if("number")
			var/datum/tgui_input_number/om/N = new(user, S["message"], S["title"] || "Number Input", S["default"] || 0, isnull(S["max"]) ? INFINITY : S["max"], S["min"] || 0, timeout, TRUE, GLOB.tgui_always_state)
			N.om_prompt = P
			N.tgui_interact(user)
			return N
	var/datum/tgui_alert/om/A = new(user, S["message"], S["title"], S["choices"] || list("Ok"), timeout, TRUE, GLOB.tgui_always_state)
	A.om_prompt = P
	A.tgui_interact(user)
	return A

/datum/tgui_alert/om
	var/datum/om/prompt/om_prompt

/datum/tgui_alert/om/set_choice(choice)
	. = ..()
	if(om_prompt && !isnull(src.choice))
		var/datum/om/prompt/P = om_prompt
		om_prompt = null
		om_prompt_answer(P, src.choice)

/datum/tgui_alert/om/tgui_close(mob/user)
	. = ..()
	if(om_prompt)
		om_prompt_closed(om_prompt)
		om_prompt = null
	qdel(src)

/datum/tgui_list_input/om
	var/datum/om/prompt/om_prompt

/datum/tgui_list_input/om/set_choice(choice)
	. = ..()
	if(om_prompt && !isnull(src.choice))
		var/datum/om/prompt/P = om_prompt
		om_prompt = null
		om_prompt_answer(P, src.choice)

/datum/tgui_list_input/om/tgui_close(mob/user)
	. = ..()
	if(om_prompt)
		om_prompt_closed(om_prompt)
		om_prompt = null
	qdel(src)

/datum/tgui_input_text/om
	var/datum/om/prompt/om_prompt

/datum/tgui_input_text/om/set_entry(entry)
	. = ..()
	if(om_prompt && !isnull(src.entry))
		var/datum/om/prompt/P = om_prompt
		om_prompt = null
		om_prompt_answer(P, src.entry)

/datum/tgui_input_text/om/tgui_close(mob/user)
	. = ..()
	if(om_prompt)
		om_prompt_closed(om_prompt)
		om_prompt = null
	qdel(src)

/datum/tgui_input_number/om
	var/datum/om/prompt/om_prompt

/datum/tgui_input_number/om/set_entry(entry)
	. = ..()
	if(om_prompt && !isnull(src.entry))
		var/datum/om/prompt/P = om_prompt
		om_prompt = null
		om_prompt_answer(P, src.entry)

/datum/tgui_input_number/om/tgui_close(mob/user)
	. = ..()
	if(om_prompt)
		om_prompt_closed(om_prompt)
		om_prompt = null
	qdel(src)
