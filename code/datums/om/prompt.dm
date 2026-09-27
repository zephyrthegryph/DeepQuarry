// Object-model core: prompts without sleeping (doc/rewrite/object_model_core.md §4.11).
//
// om_prompt(E, user, spec, on_answer) shows `user` a tgui input and returns at once. When the
// user answers, E, the user and every datum in the spec's `data` are resolved from handles and
// the spec's `requires` are re-checked (actor = user, target = the spec's `target`, else E)
// before on_answer runs, so an answer that arrives after the user walked away, died, or E was
// deleted does nothing. No proc waits on the answer.
//
// spec keys:
//   "kind"       "alert" (buttons), "list" (choices), "text", "number", "color" or
//                "checkboxes" (a list of the ticked choices). Default "alert".
//   "message", "title"
//   "choices"    alert buttons, list items or checkboxes
//   "default", "timeout" (deciseconds)
//   "min", "max"             number bounds (default 0 and INFINITY), checkbox counts
//   "round"                  number: round the entry (default TRUE)
//   "multiline", "max_length", "encode" (default TRUE)   text
//   "requires"   check specs re-checked before on_answer (check.dm); PROMPT_* in defs.dm
//   "target"     the datum the requires read as their target, when it isn't E; it must
//                still exist when the answer arrives
//   "data"       an assoc list of state for the continuation. Datums are held as handles
//                (never kept alive); if any is gone, the answer is dropped. Read with P.get().
//   "on_refused" proc called as (user, reason, P) when a re-check fails
//   "on_cancel"  proc called as (user, P) when the user closes the window or cancels
// on_answer: a type proc called on E as (user, answer, P), or a global proc called as
// (E, user, answer, P). A datum answer (a list pick) that was deleted meanwhile is dropped.
//
// E may be a /client (admin verbs); it is held by ckey. `user` may be a client too; the
// continuation always gets the client's current mob.
// Multi-question flows: om_prompt_chain(P, spec, on_answer) asks the same user about the
// same E again, carrying P's data, target, requires and on_refused forward (P.put() adds to
// the data). om_prompt_sequence() runs a
// list of questions and calls one proc with every answer at the end.

/datum/om/prompt
	/// Handles (timer.dm), or "ckey:" for a client: the prompt never keeps E or the user alive.
	var/entity_h
	var/user_h
	var/list/spec
	var/on_answer
	var/answered = FALSE
	/// The spec's data with datums as handles; resolved into `values` when the answer arrives.
	var/list/data
	/// The data as the continuation reads it (resolved), during and after the answer.
	var/list/values
	/// The tgui input showing it, if any.
	var/datum/ui
	/// om_prompt_sequence(): the steps, the one being asked, and the proc called at the end.
	var/list/seq_steps
	var/seq_index = 0
	var/seq_done

/// Test schedulers collect prompts here instead of opening a window.
/datum/om/scheduler/var/list/test_prompts

/// A value from the prompt's data, resolved.
/datum/om/prompt/proc/get(key)
	if(values)
		return values[key]
	return om_prompt_unwrap(data?[key])

/// Adds a value to the data carried by om_prompt_chain().
/datum/om/prompt/proc/put(key, value)
	LAZYINITLIST(data)
	data[key] = om_prompt_wrap(value)
	LAZYINITLIST(values)
	values[key] = value

/proc/om_prompt_wrap(value)
	if(istype(value, /client))
		var/client/C = value
		return "ckey:[C.ckey]"
	if(isdatum(value))
		return list("om_h" = om_handle(value))
	return value

/proc/om_prompt_unwrap(value)
	if(istext(value) && copytext(value, 1, 6) == "ckey:")
		return GLOB.directory[copytext(value, 6)]
	if(islist(value) && length(value) == 1 && value["om_h"])
		return om_resolve(value["om_h"])
	return value

/// Asks `user` and calls `on_answer` with the answer later. Returns the prompt, or null if E
/// or the user is gone or has no client (outside tests).
/proc/om_prompt(datum/E, mob/user, list/spec, on_answer)
	if(isnull(E))
		E = om_global_owner()
	if(istype(user, /client))
		var/client/UC = user
		user = UC.mob
	var/eh = om_prompt_wrap(E)
	if(islist(eh))
		eh = eh["om_h"]
	var/uh = om_handle(user)
	if(!eh || !uh)
		return null
	var/datum/om/prompt/P = new
	P.entity_h = eh
	P.user_h = uh
	P.spec = spec || list()
	P.on_answer = on_answer
	var/list/D = P.spec["data"]
	if(length(D))
		P.data = list()
		for(var/key in D)
			P.data[key] = om_prompt_wrap(D[key])
	if(!isnull(P.spec["target"]) && !islist(P.spec["target"]))
		var/list/wrapped = list(om_prompt_wrap(P.spec["target"]))
		P.spec = P.spec.Copy()
		P.spec["target"] = wrapped
	var/datum/om/scheduler/sched = om_scheduler()
	if(sched.test_prompts)
		sched.test_prompts += P
		return P
	if(!user.client)
		return null
	P.ui = om_prompt_show(P, user)
	return P.ui ? P : null

/// Asks P's user about P's E again, carrying P's data (and target, unless `spec` names its own).
/proc/om_prompt_chain(datum/om/prompt/P, list/spec, on_answer)
	var/datum/E = om_prompt_entity(P)
	var/mob/user = om_resolve(P.user_h)
	if(!E || !user)
		return null
	spec = spec ? spec.Copy() : list()
	for(var/key in list("requires", "on_refused", "timeout"))
		if(isnull(spec[key]) && !isnull(P.spec[key]))
			spec[key] = P.spec[key]
	var/datum/om/prompt/next = om_prompt(E, user, spec, on_answer)
	if(!next)
		return null
	if(P.data)
		var/list/merged = P.data.Copy()
		if(next.data)
			merged |= next.data
			for(var/key in next.data)
				merged[key] = next.data[key]
		next.data = merged
	if(isnull(spec["target"]) && !isnull(P.spec["target"]))
		next.spec = next.spec.Copy()
		next.spec["target"] = P.spec["target"]
	return next

// ---------------------------------------------------------------- sequences
//
// om_prompt_sequence(E, user, steps, on_done, base) asks a list of questions one after another.
// Each step is a spec (with a "key"), null (skipped), or a proc on E called as (user, P) that returns a spec, or
// null to skip the question; P.get(key) reads the answers so far, so later questions can depend
// on earlier ones. `base` holds the keys every question shares (requires, target, data,
// on_refused, on_cancel, timeout). Each answer is stored under its spec's "key" (else the
// step's name) and re-checked like any prompt; a cancel ends the sequence. When the last step
// is answered, on_done is called on E as (user, P) (a global proc: (E, user, P)).

/proc/om_prompt_sequence(datum/E, mob/user, list/steps, on_done, list/base)
	if(isnull(E))
		E = om_global_owner()
	if(istype(user, /client))
		var/client/UC = user
		user = UC.mob
	var/eh = om_prompt_wrap(E)
	if(islist(eh))
		eh = eh["om_h"]
	var/uh = om_handle(user)
	if(!eh || !uh || !length(steps))
		return null
	var/datum/om/prompt/P = new
	P.entity_h = eh
	P.user_h = uh
	P.spec = base ? base.Copy() : list()
	var/list/D = P.spec["data"]
	if(length(D))
		P.data = list()
		for(var/key in D)
			P.data[key] = om_prompt_wrap(D[key])
	if(!isnull(P.spec["target"]) && !islist(P.spec["target"]))
		P.spec["target"] = list(om_prompt_wrap(P.spec["target"]))
	P.seq_steps = steps.Copy()
	P.seq_done = on_done
	return om_prompt_sequence_next(P)

/// Asks the sequence's next question, or calls on_done when there are none left.
/proc/om_prompt_sequence_next(datum/om/prompt/P)
	var/static/list/inherited = list("requires", "target", "on_refused", "on_cancel", "timeout")
	var/datum/E = om_prompt_entity(P)
	var/mob/user = om_resolve(P.user_h)
	if(!E || !user || !om_prompt_resolve_data(P))
		return null
	while(P.seq_index < length(P.seq_steps))
		P.seq_index++
		var/step = P.seq_steps[P.seq_index]
		if(isnull(step))
			continue
		var/list/spec = step
		if(!islist(step))
			spec = null
			try
				if(copytext("[step]", 1, 7) == "/proc/")
					spec = call(step)(E, user, P)
				else
					spec = call(E, step)(user, P)
			catch(var/exception/e)
				stack_trace("om prompt sequence step [step] on [E]: [e]")
				return null
		if(!islist(spec))
			continue
		spec = spec.Copy()
		for(var/key in inherited)
			if(isnull(spec[key]) && !isnull(P.spec[key]))
				spec[key] = P.spec[key]
		spec["om_seq_key"] = spec["key"] || "[step]"
		spec -= "data"
		var/datum/om/prompt/next = om_prompt(E, user, spec, /proc/om_prompt_sequence_answered)
		if(!next)
			return null
		next.data = P.data?.Copy()
		next.seq_steps = P.seq_steps
		next.seq_index = P.seq_index
		next.seq_done = P.seq_done
		return next
	if(P.seq_done)
		try
			if(copytext("[P.seq_done]", 1, 7) == "/proc/")
				call(P.seq_done)(E, user, P)
			else
				call(E, P.seq_done)(user, P)
		catch(var/exception/e)
			stack_trace("om prompt sequence [P.seq_done] on [E]: [e]")
	return P

/proc/om_prompt_sequence_answered(datum/E, mob/user, answer, datum/om/prompt/P)
	P.put(P.spec["om_seq_key"], answer)
	om_prompt_sequence_next(P)

/proc/om_prompt_entity(datum/om/prompt/P)
	if(copytext(P.entity_h, 1, 6) == "ckey:")
		return om_prompt_unwrap(P.entity_h)
	return om_resolve(P.entity_h)

/// Resolves P's data into P.values. FALSE if a datum in it is gone.
/proc/om_prompt_resolve_data(datum/om/prompt/P)
	P.values = list()
	for(var/key in P.data)
		var/raw = P.data[key]
		var/value = om_prompt_unwrap(raw)
		if(isnull(value) && (islist(raw) || (istext(raw) && copytext(raw, 1, 6) == "ckey:")))
			return FALSE
		P.values[key] = value
	return TRUE

/// Delivers an answer (tgui, or a test). Returns null when on_answer ran, else the reason it did not.
/proc/om_prompt_answer(datum/om/prompt/P, answer)
	if(P.answered)
		return "answered"
	P.answered = TRUE
	P.ui = null
	var/datum/E = om_prompt_entity(P)
	var/mob/user = om_resolve(P.user_h)
	if(!E || !user || !om_prompt_resolve_data(P))
		return "gone"
	if(isnull(answer))
		if(P.spec["on_cancel"])
			om_prompt_call(E, P.spec["on_cancel"], user, P)
		return "no answer"
	if(isdatum(answer))
		var/datum/answered_datum = answer
		if(QDELETED(answered_datum))
			return "gone"
	var/datum/check_target = E
	var/list/target = P.spec["target"]
	if(islist(target))
		check_target = om_prompt_unwrap(target[1])
		if(!check_target)
			return "gone"
	for(var/check_spec in om_spec_list(P.spec["requires"]))
		var/reason = om_why_not(check_spec, user, check_target)
		if(!isnull(reason))
			if(P.spec["on_refused"])
				om_prompt_call(E, P.spec["on_refused"], user, reason, P)
			return reason
	om_prompt_call(E, P.on_answer, user, answer, P)
	return null


/proc/om_prompt_call(datum/E, proc_ref, mob/user, value, datum/om/prompt/P)
	if(!proc_ref)
		return
	try
		if(copytext("[proc_ref]", 1, 7) == "/proc/")
			call(proc_ref)(E, user, value, P)
		else
			call(E, proc_ref)(user, value, P)
	catch(var/exception/e)
		stack_trace("om prompt [proc_ref] on [E]: [e]")

/// The user closed the window without answering.
/proc/om_prompt_closed(datum/om/prompt/P)
	if(P.answered)
		return
	P.answered = TRUE
	P.ui = null
	if(!P.spec["on_cancel"])
		return
	var/datum/E = om_prompt_entity(P)
	var/mob/user = om_resolve(P.user_h)
	if(E && user && om_prompt_resolve_data(P))
		om_prompt_call(E, P.spec["on_cancel"], user, P)

// ---------------------------------------------------------------- tgui

/proc/om_prompt_show(datum/om/prompt/P, mob/user)
	var/list/S = P.spec
	var/timeout = S["timeout"] || 0
	switch(S["kind"] || "alert")
		if("list")
			if(!length(S["choices"]))
				return null
			var/datum/tgui_list_input/om/L = new(user, S["message"], S["title"] || "Select", S["choices"], S["default"], timeout, GLOB.tgui_always_state)
			if(L.invalid)
				qdel(L)
				return null
			L.om_prompt = P
			L.tgui_interact(user)
			return L
		if("text")
			var/datum/tgui_input_text/om/T = new(user, S["message"], S["title"] || "Text Input", S["default"], S["max_length"] || MAX_TGUI_INPUT, S["multiline"], isnull(S["encode"]) ? TRUE : S["encode"], timeout, GLOB.tgui_always_state)
			T.om_prompt = P
			T.tgui_interact(user)
			return T
		if("number")
			var/datum/tgui_input_number/om/N = new(user, S["message"], S["title"] || "Number Input", S["default"] || 0, isnull(S["max"]) ? INFINITY : S["max"], S["min"] || 0, timeout, isnull(S["round"]) ? TRUE : S["round"], GLOB.tgui_always_state)
			N.om_prompt = P
			N.tgui_interact(user)
			return N
		if("color")
			var/datum/tgui_color_picker/om/C = new(user, S["message"], S["title"] || "Pick a color", S["default"] || "#000000", timeout, TRUE, GLOB.tgui_always_state)
			C.om_prompt = P
			C.tgui_interact(user)
			return C
		if("checkboxes")
			if(!length(S["choices"]))
				return null
			var/datum/tgui_checkbox_input/om/X = new(user, S["message"], S["title"] || "Select", S["choices"], isnull(S["min"]) ? 1 : S["min"], S["max"] || 50, timeout, GLOB.tgui_always_state)
			X.om_prompt = P
			X.tgui_interact(user)
			return X
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

/datum/tgui_color_picker/om
	var/datum/om/prompt/om_prompt

/datum/tgui_color_picker/om/set_choice(choice)
	. = ..()
	if(om_prompt && !isnull(src.choice))
		var/datum/om/prompt/P = om_prompt
		om_prompt = null
		om_prompt_answer(P, src.choice)

/datum/tgui_color_picker/om/tgui_close(mob/user)
	. = ..()
	if(om_prompt)
		om_prompt_closed(om_prompt)
		om_prompt = null
	qdel(src)

/datum/tgui_checkbox_input/om
	var/datum/om/prompt/om_prompt

/datum/tgui_checkbox_input/om/set_choices(list/selections)
	. = ..()
	if(om_prompt && !isnull(src.choices))
		var/datum/om/prompt/P = om_prompt
		om_prompt = null
		om_prompt_answer(P, src.choices)

/datum/tgui_checkbox_input/om/tgui_close(mob/user)
	. = ..()
	if(om_prompt)
		om_prompt_closed(om_prompt)
		om_prompt = null
	qdel(src)
