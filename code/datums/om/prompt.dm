// Object-model core: prompts without sleeping (doc/rewrite/object_model_core.md §4.11).
//
// om_prompt(E, user, spec, on_answer) shows `user` a tgui input and returns at once. When the
// user answers, E, the user and every datum in the spec's `data` are resolved from handles and
// the spec's `requires` are re-checked (actor = user, target = the spec's `target`, else E)
// before on_answer runs, so an answer that arrives after the user walked away, died, or E was
// deleted does nothing. No proc waits on the answer.
//
// spec keys:
//   "kind"       "alert" (buttons), "list" (choices), "text", "number", "color",
//                "checkboxes" (a list of the ticked choices) or "colormatrix" (the ColorMate
//                window: "preview", "matrix_only", "ui_state") or "typepath" (a typed part of a
//                path under "root", default /atom; several matches are picked from a list, and
//                the answer is the path) or "bitfield" (flag checkboxes: "bitfield" names the
//                flag set for get_valid_bitflags(), "default" is the value, "editable" the mask
//                of flags that may change; the answer is the new value). Default "alert".
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
//   "cancel_answer"  the answer a cancel, a closed window or a timeout gives instead (re-checked
//                like any answer): "Yes" for a request that goes through unless refused in time
// on_answer: a type proc called on E as (user, answer, P), or a global proc called as
// (E, user, answer, P). A datum answer (a list pick) that was deleted meanwhile is dropped.
//
// E may be a /client (admin verbs); it is held by ckey. `user` may be a client too; the
// continuation always gets the client's current mob.
// This is the plumbing under typed prompts: callers outside code/datums/om ask with om_ask()
// (ask.dm), om_ask_sequence() or a flow (flow.dm); tools/ci/api_lints.py (prompt_spec) keeps
// om_prompt() calls inside code/datums/om.

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

/// The prompt and the tgui input showing it point at each other.
/datum/om/prompt/declared_pair_vars()
	var/static/list/pairs = list("ui" = "om_prompt")
	return pairs

/// Test schedulers collect prompts here instead of opening a window.
/datum/om/scheduler/var/list/test_prompts

/// A value from the prompt's data, resolved.
/datum/om/prompt/proc/get(key)
	if(values)
		return values[key]
	return om_prompt_unwrap(data?[key])

/// Adds a value to the prompt's data.
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
/// or the user is gone or has no client (outside tests). `P`: a typed prompt (ask.dm) to show
/// instead of a new plain one; new code asks with om_ask().
/proc/om_prompt(datum/E, mob/user, list/spec, on_answer, datum/om/prompt/P)
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
	if(!P)
		P = new
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
/// `cancelled`: the answer is the cancel_answer a closed window gave (never refused by re-checks).
/proc/om_prompt_answer(datum/om/prompt/P, answer, cancelled = FALSE)
	if(P.answered)
		return "answered"
	P.answered = TRUE
	P.ui = null
	var/datum/E = om_prompt_entity(P)
	var/mob/user = om_resolve(P.user_h)
	if(!E || !user || !om_prompt_resolve_data(P))
		return "gone"
	if(P.kind_name && isnull(answer) && isnull(P.spec["cancel_answer"]))
		if(P.optional)
			// An optional question: a cancel answers "nothing", unchecked.
			if(!P.unpark())
				P.refused("gone")
				return "gone"
			om_ask_answered(E, user, null, P)
			return null
		// A typed prompt's cancel: om_ask_cancelled() restores its state.
		if(P.spec["on_cancel"])
			om_prompt_call(E, P.spec["on_cancel"], user, P)
		return "no answer"
	if(P.kind_name && !P.unpark())
		P.refused("gone")
		return "gone"
	if(P.kind_name && P.is_cancel_answer(answer))
		// The kind's own cancel button (Yes/No/Cancel).
		P.cancelled()
		return "no answer"
	if(P.spec["kind"] == "typepath" && istext(answer))
		// The typed part of a path: one match is the answer, several are picked from a list.
		var/list/matches = om_prompt_typepaths(answer, P.spec["root"] || /atom)
		if(length(matches) == 1)
			answer = matches[1]
		else if(length(matches))
			P.answered = FALSE
			var/datum/tgui_list_input/om/L = new(user, "Select a type", P.spec["title"] || "Typepath", matches, null, 0, GLOB.tgui_always_state)
			L.om_prompt = P
			P.ui = L
			L.tgui_interact(user)
			return "picking"
		else
			to_chat(user, span_warning("No results found.  Sorry."))
			answer = null
	if(isnull(answer))
		answer = P.spec["cancel_answer"]
		cancelled = TRUE
	if(isnull(answer))
		if(P.spec["on_cancel"])
			om_prompt_call(E, P.spec["on_cancel"], user, P)
		return "no answer"
	if(isdatum(answer))
		var/datum/answered_datum = answer
		if(QDELETED(answered_datum))
			return "gone"
	if(P.kind_name && !P.take_answer(answer))
		// A typed prompt answered no (confirm): nothing to re-check.
		P.declined()
		return "declined"
	var/reason = cancelled ? null : om_prompt_recheck(P, E, user)
	if(!isnull(reason))
		if((reason != "gone" || P.kind_name) && P.spec["on_refused"])
			om_prompt_call(E, P.spec["on_refused"], user, reason, P)
		return reason
	om_prompt_call(E, P.on_answer, user, answer, P)
	return null

/// Re-checks P's requires (and that its target is still there). Null when they hold, else the reason.
/proc/om_prompt_recheck(datum/om/prompt/P, datum/E, mob/user)
	var/datum/check_target = E
	var/list/target = P.spec["target"]
	if(islist(target))
		check_target = om_prompt_unwrap(target[1])
		if(!check_target)
			return "gone"
	for(var/check_spec in om_spec_list(P.spec["requires"]))
		var/reason = om_why_not(check_spec, user, check_target)
		if(!isnull(reason))
			return reason
	if(P.kind_name)
		return P.typed_recheck(E, user)
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

/// Types under `root` whose path contains `text`, for kind "typepath".
/proc/om_prompt_typepaths(text, root)
	var/list/matches = list()
	for(var/path in typesof(root))
		if(findtext("[path]", text))
			matches += path
	return matches

/// The user closed the window without answering (or it timed out).
/proc/om_prompt_closed(datum/om/prompt/P)
	if(P.answered)
		return
	if(!isnull(P.spec["cancel_answer"]))
		om_prompt_answer(P, P.spec["cancel_answer"], TRUE)
		return
	if(P.kind_name)
		om_prompt_answer(P, null, TRUE)
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
		if("text", "typepath")
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
		if("bitfield")
			if(!length(get_valid_bitflags(S["bitfield"])))
				return null
			var/datum/tgui_bitfield_input/om/B = new(user, S["title"] || S["message"] || "Bitfield", get_valid_bitflags(S["bitfield"]), S["default"] || 0, isnull(S["editable"]) ? ALL : S["editable"], timeout)
			B.om_prompt = P
			B.tgui_interact(user)
			return B
		if("colormatrix")
			var/preview = S["preview"]
			if(!ispath(preview) && !isatom(preview))
				return null
			var/was_path = ispath(preview)
			var/atom/movable/shown = was_path ? new preview : preview
			var/list/default = islist(S["default"]) && length(S["default"]) ? S["default"] : DEFAULT_COLORMATRIX
			if(length(default) < 12)
				default = default.Copy()
				default.len = 12
			var/datum/tgui_input_colormatrix/om/M = new(user, S["message"], S["title"] || "Matrix Recolor", shown, default, S["matrix_only"], timeout || 30 MINUTES, S["ui_state"] || GLOB.tgui_always_state, was_path)
			M.om_prompt = P
			M.tgui_interact(user)
			return M
	var/datum/tgui_alert/om/A = new(user, S["message"], S["title"], S["choices"] || list("Ok"), timeout, TRUE, GLOB.tgui_always_state)
	A.om_prompt = P
	A.tgui_interact(user)
	return A

/datum/tgui_alert/om
	var/datum/om/prompt/om_prompt

/datum/tgui_alert/om/declared_pair_vars()
	var/static/list/pairs = list("om_prompt" = "ui")
	return pairs

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

/datum/tgui_list_input/om/declared_pair_vars()
	var/static/list/pairs = list("om_prompt" = "ui")
	return pairs

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

/datum/tgui_input_text/om/declared_pair_vars()
	var/static/list/pairs = list("om_prompt" = "ui")
	return pairs

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

/datum/tgui_input_number/om/declared_pair_vars()
	var/static/list/pairs = list("om_prompt" = "ui")
	return pairs

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

/datum/tgui_color_picker/om/declared_pair_vars()
	var/static/list/pairs = list("om_prompt" = "ui")
	return pairs

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

/datum/tgui_checkbox_input/om/declared_pair_vars()
	var/static/list/pairs = list("om_prompt" = "ui")
	return pairs

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

/// kind "colormatrix": the ColorMate window. "preview" is the atom (painted in place) or the
/// path (a preview made for the window and deleted with it); the answer is the matrix.
/datum/tgui_input_colormatrix/om
	var/datum/om/prompt/om_prompt

/datum/tgui_input_colormatrix/om/declared_pair_vars()
	var/static/list/pairs = list("om_prompt" = "ui")
	return pairs

/datum/tgui_input_colormatrix/om/set_entry(entry)
	. = ..()
	if(om_prompt && !isnull(src.entry))
		var/datum/om/prompt/P = om_prompt
		om_prompt = null
		om_prompt_answer(P, src.entry)

/datum/tgui_input_colormatrix/om/tgui_close(mob/user)
	. = ..()
	if(om_prompt)
		om_prompt_closed(om_prompt)
		om_prompt = null
	qdel(src)

/datum/tgui_input_colormatrix/om/Destroy(force)
	if(was_path && target)
		qdel(target)
	return ..()

/// kind "bitfield": the flag checkboxes. Submit answers the value; cancel or close cancels.
/datum/tgui_bitfield_input/om
	var/datum/om/prompt/om_prompt

/datum/tgui_bitfield_input/om/declared_pair_vars()
	var/static/list/pairs = list("om_prompt" = "ui")
	return pairs

/datum/tgui_bitfield_input/om/tgui_act(action, list/params, datum/tgui/ui)
	// Answer before the window closes: closing it means cancel.
	if(om_prompt && action == "submit")
		var/datum/om/prompt/P = om_prompt
		om_prompt = null
		om_prompt_answer(P, value)
		SStgui.close_uis(src)
		return TRUE
	return ..()

/datum/tgui_bitfield_input/om/tgui_close(mob/user)
	. = ..()
	if(om_prompt)
		om_prompt_closed(om_prompt)
		om_prompt = null
	qdel(src)
