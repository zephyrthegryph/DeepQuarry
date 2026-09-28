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
// New code asks with typed prompts, om_ask() (ask.dm); multi-step actions are flows (flow.dm).
// Multi-question flows: P.chain(spec, on_answer) asks the same user about the
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
	/// The sequence's own user (a step may ask someone else: its "user").
	var/seq_user_h

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

/// Adds a value to the data carried by chain().
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
	P.ui = P.show(user)
	return P.ui ? P : null

/// Asks P's user about P's E again, carrying P's data (and target, unless `spec` names its own).
/datum/om/prompt/proc/chain(list/spec, on_answer)
	var/datum/E = entity()
	var/mob/user = om_resolve(user_h)
	if(!E || !user)
		return null
	spec = spec ? spec.Copy() : list()
	for(var/key in list("requires", "on_refused", "timeout"))
		if(isnull(spec[key]) && !isnull(src.spec[key]))
			spec[key] = src.spec[key]
	var/datum/om/prompt/next = om_prompt(E, user, spec, on_answer)
	if(!next)
		return null
	if(data)
		var/list/merged = data.Copy()
		if(next.data)
			merged |= next.data
			for(var/key in next.data)
				merged[key] = next.data[key]
		next.data = merged
	if(isnull(spec["target"]) && !isnull(src.spec["target"]))
		next.spec = next.spec.Copy()
		next.spec["target"] = src.spec["target"]
	return next

// ---------------------------------------------------------------- sequences
//
// om_prompt_sequence(E, user, steps, on_done, base) asks a list of questions one after another.
// Each step is a spec (with a "key"), null (skipped), or a proc on E called as (user, P) that returns a spec,
// null to skip the question, or PROMPT_STOP to end the sequence there; P.get(key) reads the answers so far, so later questions can depend
// on earlier ones. `base` holds the keys every question shares (requires, target, data,
// on_refused, on_cancel, timeout). Each answer is stored under its spec's "key" (else the
// step's name) and re-checked like any prompt; a cancel ends the sequence. When the last step
// is answered, on_done is called on E as (user, P) (a global proc: (E, user, P)).
// Per-step keys:
//   "optional"  TRUE: a cancel stores null under the key and the sequence goes on
//               ("pick one, or cancel for none").
//   "confirm"   the answer the sequence needs to go on ("Yes"): any other answer, or a
//               cancel, ends it quietly. For "are you sure?" steps.
//   "abort"     an answer (or a list of answers) that ends the sequence quietly ("Cancel").
//   "on_stop"   proc called on E as (user, P) when this step ends the sequence (a cancel, or an
//               answer "confirm"/"abort" stops on): "they declined".
//   "user"      a different mob answers this step (consent from the other party). Held as a
//               handle; the sequence ends if they're gone. Their answer is re-checked with
//               them as the actor (give the step "requires" = list() to skip the base checks).
// on_done and step procs always get the sequence's own user.

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
	for(var/i in 1 to length(P.seq_steps))
		var/list/step = P.seq_steps[i]
		if(islist(step) && isdatum(step["user"]))
			step = step.Copy()
			step["user"] = om_prompt_wrap(step["user"])
			P.seq_steps[i] = step
	P.seq_done = on_done
	P.seq_user_h = uh
	return P.sequence_next()

/// Asks the sequence's next question, or calls on_done when there are none left.
/datum/om/prompt/proc/sequence_next()
	var/static/list/inherited = list("requires", "target", "on_refused", "on_cancel", "timeout")
	var/datum/E = entity()
	var/mob/user = om_resolve(seq_user_h || user_h)
	if(!E || !user || !resolve_data())
		return null
	while(seq_index < length(seq_steps))
		seq_index++
		var/step = seq_steps[seq_index]
		if(isnull(step))
			continue
		var/list/spec = step
		if(!islist(step))
			spec = null
			try
				if(copytext("[step]", 1, 7) == "/proc/")
					spec = call(step)(E, user, src)
				else
					spec = call(E, step)(user, src)
			catch(var/exception/e)
				stack_trace("om prompt sequence step [step] on [E]: [e]")
				return null
		if(spec == PROMPT_STOP)
			return null
		if(!islist(spec))
			continue
		spec = spec.Copy()
		for(var/key in inherited)
			if(isnull(spec[key]) && !isnull(src.spec[key]))
				spec[key] = src.spec[key]
		spec["om_seq_key"] = spec["key"] || "[step]"
		if(spec["optional"])
			spec["on_cancel"] = /proc/om_prompt_sequence_skipped
		else if(spec["on_stop"])
			spec["on_cancel"] = /proc/om_prompt_sequence_stopped
		spec -= "data"
		var/mob/asked = user
		if(!isnull(spec["user"]))
			asked = om_prompt_unwrap(spec["user"])
			if(!asked)
				return null
		var/datum/om/prompt/next = om_prompt(E, asked, spec, /proc/om_prompt_sequence_answered)
		if(!next)
			return null
		next.data = data?.Copy()
		next.seq_steps = seq_steps
		next.seq_index = seq_index
		next.seq_done = seq_done
		next.seq_user_h = seq_user_h
		return next
	if(seq_done)
		try
			if(copytext("[seq_done]", 1, 7) == "/proc/")
				call(seq_done)(E, user, src)
			else
				call(E, seq_done)(user, src)
		catch(var/exception/e)
			stack_trace("om prompt sequence [seq_done] on [E]: [e]")
	return src

/proc/om_prompt_sequence_answered(datum/E, mob/user, answer, datum/om/prompt/P)
	var/abort = P.spec["abort"]
	if((!isnull(P.spec["confirm"]) && answer != P.spec["confirm"]) || (!isnull(abort) && (islist(abort) ? (answer in abort) : answer == abort)))
		om_prompt_sequence_stopped(E, user, P)
		return
	P.put(P.spec["om_seq_key"], answer)
	P.sequence_next()

/// A step ended the sequence: its on_stop runs with the sequence's user.
/proc/om_prompt_sequence_stopped(datum/E, mob/user, datum/om/prompt/P)
	var/mob/owner = om_resolve(P.seq_user_h || P.user_h)
	if(owner && P.spec["on_stop"])
		om_prompt_call(E, P.spec["on_stop"], owner, P)

/// An optional step was cancelled: its answer is null, and the sequence goes on once the
/// requires still hold.
/proc/om_prompt_sequence_skipped(datum/E, mob/user, datum/om/prompt/P)
	if(!isnull(P.recheck(E, user)))
		return
	P.put(P.spec["om_seq_key"], null)
	P.sequence_next()

/datum/om/prompt/proc/entity()
	if(copytext(entity_h, 1, 6) == "ckey:")
		return om_prompt_unwrap(entity_h)
	return om_resolve(entity_h)

/// Resolves P's data into P.values. FALSE if a datum in it is gone.
/datum/om/prompt/proc/resolve_data()
	values = list()
	for(var/key in data)
		var/raw = data[key]
		var/value = om_prompt_unwrap(raw)
		if(isnull(value) && (islist(raw) || (istext(raw) && copytext(raw, 1, 6) == "ckey:")))
			return FALSE
		values[key] = value
	return TRUE

/// Delivers an answer (tgui, or a test). Returns null when on_answer ran, else the reason it did not.
/datum/om/prompt/proc/answer(answer)
	if(answered)
		return "answered"
	answered = TRUE
	ui = null
	var/datum/E = entity()
	var/mob/user = om_resolve(user_h)
	if(!E || !user || !resolve_data())
		return "gone"
	if(kind_name && isnull(answer) && isnull(spec["cancel_answer"]))
		// A typed prompt's cancel: om_ask_cancelled() restores its state.
		if(spec["on_cancel"])
			om_prompt_call(E, spec["on_cancel"], user, src)
		return "no answer"
	if(kind_name && !unpark())
		refused("gone")
		return "gone"
	if(spec["kind"] == "typepath" && istext(answer))
		// The typed part of a path: one match is the answer, several are picked from a list.
		var/list/matches = om_prompt_typepaths(answer, spec["root"] || /atom)
		if(length(matches) == 1)
			answer = matches[1]
		else if(length(matches))
			answered = FALSE
			var/datum/tgui_list_input/om/L = new(user, "Select a type", spec["title"] || "Typepath", matches, null, 0, GLOB.tgui_always_state)
			L.om_prompt = src
			ui = L
			L.tgui_interact(user)
			return "picking"
		else
			to_chat(user, span_warning("No results found.  Sorry."))
			answer = null
	if(isnull(answer))
		answer = spec["cancel_answer"]
	if(isnull(answer))
		if(spec["on_cancel"])
			om_prompt_call(E, spec["on_cancel"], user, src)
		return "no answer"
	if(isdatum(answer))
		var/datum/answered_datum = answer
		if(QDELETED(answered_datum))
			return "gone"
	if(kind_name && !take_answer(answer))
		// A typed prompt answered no (confirm): nothing to re-check.
		declined()
		return "declined"
	var/reason = recheck(E, user)
	if(!isnull(reason))
		if((reason != "gone" || kind_name) && spec["on_refused"])
			om_prompt_call(E, spec["on_refused"], user, reason, src)
		return reason
	om_prompt_call(E, on_answer, user, answer, src)
	return null

/// Re-checks P's requires (and that its target is still there). Null when they hold, else the reason.
/datum/om/prompt/proc/recheck(datum/E, mob/user)
	var/datum/check_target = E
	var/list/target = spec["target"]
	if(islist(target))
		check_target = om_prompt_unwrap(target[1])
		if(!check_target)
			return "gone"
	for(var/check_spec in om_spec_list(spec["requires"]))
		var/reason = om_why_not(check_spec, user, check_target)
		if(!isnull(reason))
			return reason
	if(kind_name)
		return typed_recheck(E, user)
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
/datum/om/prompt/proc/closed()
	if(answered)
		return
	if(!isnull(spec["cancel_answer"]))
		answer(spec["cancel_answer"])
		return
	answered = TRUE
	ui = null
	if(!spec["on_cancel"])
		return
	var/datum/E = entity()
	var/mob/user = om_resolve(user_h)
	if(E && user && resolve_data())
		om_prompt_call(E, spec["on_cancel"], user, src)

// ---------------------------------------------------------------- tgui

/datum/om/prompt/proc/show(mob/user)
	var/list/S = spec
	var/timeout = S["timeout"] || 0
	switch(S["kind"] || "alert")
		if("list")
			if(!length(S["choices"]))
				return null
			var/datum/tgui_list_input/om/L = new(user, S["message"], S["title"] || "Select", S["choices"], S["default"], timeout, GLOB.tgui_always_state)
			if(L.invalid)
				qdel(L)
				return null
			L.om_prompt = src
			L.tgui_interact(user)
			return L
		if("text", "typepath")
			var/datum/tgui_input_text/om/T = new(user, S["message"], S["title"] || "Text Input", S["default"], S["max_length"] || MAX_TGUI_INPUT, S["multiline"], isnull(S["encode"]) ? TRUE : S["encode"], timeout, GLOB.tgui_always_state)
			T.om_prompt = src
			T.tgui_interact(user)
			return T
		if("number")
			var/datum/tgui_input_number/om/N = new(user, S["message"], S["title"] || "Number Input", S["default"] || 0, isnull(S["max"]) ? INFINITY : S["max"], S["min"] || 0, timeout, isnull(S["round"]) ? TRUE : S["round"], GLOB.tgui_always_state)
			N.om_prompt = src
			N.tgui_interact(user)
			return N
		if("color")
			var/datum/tgui_color_picker/om/C = new(user, S["message"], S["title"] || "Pick a color", S["default"] || "#000000", timeout, TRUE, GLOB.tgui_always_state)
			C.om_prompt = src
			C.tgui_interact(user)
			return C
		if("checkboxes")
			if(!length(S["choices"]))
				return null
			var/datum/tgui_checkbox_input/om/X = new(user, S["message"], S["title"] || "Select", S["choices"], isnull(S["min"]) ? 1 : S["min"], S["max"] || 50, timeout, GLOB.tgui_always_state)
			X.om_prompt = src
			X.tgui_interact(user)
			return X
		if("bitfield")
			if(!length(get_valid_bitflags(S["bitfield"])))
				return null
			var/datum/tgui_bitfield_input/om/B = new(user, S["title"] || S["message"] || "Bitfield", get_valid_bitflags(S["bitfield"]), S["default"] || 0, isnull(S["editable"]) ? ALL : S["editable"], timeout)
			B.om_prompt = src
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
			M.om_prompt = src
			M.tgui_interact(user)
			return M
	var/datum/tgui_alert/om/A = new(user, S["message"], S["title"], S["choices"] || list("Ok"), timeout, TRUE, GLOB.tgui_always_state)
	A.om_prompt = src
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
		P.answer(src.choice)

/datum/tgui_alert/om/tgui_close(mob/user)
	. = ..()
	if(om_prompt)
		om_prompt.closed()
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
		P.answer(src.choice)

/datum/tgui_list_input/om/tgui_close(mob/user)
	. = ..()
	if(om_prompt)
		om_prompt.closed()
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
		P.answer(src.entry)

/datum/tgui_input_text/om/tgui_close(mob/user)
	. = ..()
	if(om_prompt)
		om_prompt.closed()
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
		P.answer(src.entry)

/datum/tgui_input_number/om/tgui_close(mob/user)
	. = ..()
	if(om_prompt)
		om_prompt.closed()
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
		P.answer(src.choice)

/datum/tgui_color_picker/om/tgui_close(mob/user)
	. = ..()
	if(om_prompt)
		om_prompt.closed()
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
		P.answer(src.choices)

/datum/tgui_checkbox_input/om/tgui_close(mob/user)
	. = ..()
	if(om_prompt)
		om_prompt.closed()
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
		P.answer(src.entry)

/datum/tgui_input_colormatrix/om/tgui_close(mob/user)
	. = ..()
	if(om_prompt)
		om_prompt.closed()
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
		P.answer(value)
		SStgui.close_uis(src)
		return TRUE
	return ..()

/datum/tgui_bitfield_input/om/tgui_close(mob/user)
	. = ..()
	if(om_prompt)
		om_prompt.closed()
		om_prompt = null
	qdel(src)
