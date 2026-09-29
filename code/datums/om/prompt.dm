// Object-model core: prompts without sleeping (doc/rewrite/object_model_core.md §4.11).
//
// The plumbing under typed prompts (ask.dm): a /datum/om/prompt/<kind> is opened with open(),
// which shows the answerer a tgui input and returns at once. The tgui input answers with
// om_prompt_answer() (or om_prompt_closed()): the prompt's held state is restored, its re-checks
// run, and the answer is delivered (deliver()). No proc waits on the answer.
//
// Callers never touch this file: they ask with om_ask() (ask.dm), om_ask_sequence() or a flow
// (flow.dm), or one of the re-run helpers (prompt_helpers.dm).

/// Test schedulers collect prompts here instead of opening a window.
/datum/om/scheduler/var/list/test_prompts

/datum/om/prompt/var/answered = FALSE
/// The tgui input showing it, if any.
/datum/om/prompt/var/datum/ui

/// The prompt and the tgui input showing it point at each other.
/datum/om/prompt/relations()
	. = ..()
	. += rel_one(nameof(ui), back = nameof(/datum/tgui_alert/om::om_prompt))

/// Shows the prompt to `user`. TRUE when it is waiting on an answer.
/datum/om/prompt/proc/open(mob/user)
	var/datum/om/scheduler/sched = om_scheduler()
	if(sched.test_prompts)
		sched.test_prompts += src
		return TRUE
	if(!user?.client)
		return FALSE
	return show_to(user)

/// Opens the kind's tgui input for `user`. TRUE when shown.
/datum/om/prompt/proc/show_to(mob/user)
	var/datum/window = open_ui(user)
	if(!window)
		return FALSE
	ui = window
	// Every om tgui input below declares om_prompt.
	var/datum/tgui_alert/om/answering = window
	answering.om_prompt = src
	window.tgui_interact(user)
	return TRUE

/// The kind's tgui input for `user` (not yet shown), or null when there is nothing to ask.
/datum/om/prompt/proc/open_ui(mob/user)
	CRASH("[type] is not a prompt kind (/datum/om/prompt/<kind>)")

/// Turns the raw tgui answer into the kind's answer before anything else happens. Returns
/// OM_PROMPT_REOPENED when it asked again instead (the typepath kind's pick list).
/datum/om/prompt/proc/refine_answer(answer)
	return answer

/// A role or state var, resolved without unparking it.
/datum/om/prompt/proc/peek(name)
	if(parked && (name in parked))
		return om_prompt_unwrap(parked[name])
	return vars[name]

/// Delivers an answer (tgui, or a test). Returns null when the answer proc ran (or a cancel was
/// handled), else the reason it did not. `cancelled`: the window closed without an answer.
/proc/om_prompt_answer(datum/om/prompt/P, answer, cancelled = FALSE)
	if(P.answered)
		return "answered"
	if(!isnull(answer))
		answer = P.refine_answer(answer)
		if(answer == OM_PROMPT_REOPENED)
			return "picking"
	P.answered = TRUE
	P.ui = null
	var/receiver_gone = P.parked && ("receiver" in P.parked) && isnull(P.peek("receiver"))
	if(receiver_gone || isnull(P.peek("answerer")))
		// Whoever it answers to, or whoever answers, is gone: nothing runs.
		P.parked = null
		P.flow?.stop("gone")
		return "gone"
	if(!P.unpark())
		P.refused("gone")
		return "gone"
	if(isnull(answer))
		answer = P.cancel_answer
		cancelled = TRUE
	if(isnull(answer))
		if(P.optional)
			// An optional question: a cancel answers "nothing", unchecked.
			P.deliver()
			return null
		P.cancelled()
		return "no answer"
	if(P.is_cancel_answer(answer))
		P.cancelled()
		return "no answer"
	if(isdatum(answer))
		var/datum/answered_datum = answer
		if(QDELETED(answered_datum))
			P.refused("gone")
			return "gone"
	if(!P.take_answer(answer))
		P.declined()
		return "declined"
	if(!cancelled)
		var/reason = P.typed_recheck(P.receiver, P.answerer)
		if(!isnull(reason))
			P.refused(reason)
			return reason
	P.deliver()
	return null

/// The user closed the window without answering (or it timed out).
/proc/om_prompt_closed(datum/om/prompt/P)
	if(P.answered)
		return
	om_prompt_answer(P, null, TRUE)

/// Types under `root` whose path contains `text`, for the typepath kind.
/proc/om_prompt_typepaths(text, root)
	var/list/matches = list()
	for(var/path in typesof(root))
		if(findtext("[path]", text))
			matches += path
	return matches

/// A datum or client as it is held while a prompt or flow waits: a handle, or "ckey:<key>".
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

/// TRUE when `wrapped` held a datum or client (so a null unwrap means it is gone).
/proc/om_prompt_was_ref(wrapped)
	return islist(wrapped) || (istext(wrapped) && copytext(wrapped, 1, 6) == "ckey:")

/// Wraps every datum in a list (proc arguments held while a prompt waits).
/proc/om_prompt_wrap_list(list/values)
	. = list()
	for(var/value in values)
		. += list(om_prompt_wrap(value))

/// Unwraps om_prompt_wrap_list(); null if a datum in it is gone.
/proc/om_prompt_unwrap_list(list/wrapped)
	. = list()
	for(var/held in wrapped)
		var/value = om_prompt_unwrap(held)
		if(isnull(value) && om_prompt_was_ref(held))
			return null
		. += list(value)

// ---------------------------------------------------------------- tgui inputs
//
// Each kind's open_ui() makes one of these; they answer the prompt that opened them.

/datum/tgui_alert/om
	var/datum/om/prompt/om_prompt

/datum/tgui_alert/om/relations()
	. = ..()
	. += rel_one(nameof(om_prompt), back = nameof(/datum/om/prompt::ui))

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

/datum/tgui_list_input/om/relations()
	. = ..()
	. += rel_one(nameof(om_prompt), back = nameof(/datum/om/prompt::ui))

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

/datum/tgui_input_text/om/relations()
	. = ..()
	. += rel_one(nameof(om_prompt), back = nameof(/datum/om/prompt::ui))

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

/datum/tgui_input_number/om/relations()
	. = ..()
	. += rel_one(nameof(om_prompt), back = nameof(/datum/om/prompt::ui))

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

/datum/tgui_color_picker/om/relations()
	. = ..()
	. += rel_one(nameof(om_prompt), back = nameof(/datum/om/prompt::ui))

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

/datum/tgui_checkbox_input/om/relations()
	. = ..()
	. += rel_one(nameof(om_prompt), back = nameof(/datum/om/prompt::ui))

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

/datum/tgui_input_colormatrix/om/relations()
	. = ..()
	. += rel_one(nameof(om_prompt), back = nameof(/datum/om/prompt::ui))

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

/datum/tgui_input_colormatrix/om/on_destroy(force)
	if(was_path && target())
		qdel(target())
	..()

/// kind "bitfield": the flag checkboxes. Submit answers the value; cancel or close cancels.
/datum/tgui_bitfield_input/om
	var/datum/om/prompt/om_prompt

/datum/tgui_bitfield_input/om/relations()
	. = ..()
	. += rel_one(nameof(om_prompt), back = nameof(/datum/om/prompt::ui))

UI_ACT_OVERRIDE(/datum/tgui_bitfield_input/om, ui_act_submit)
	// Answer before the window closes: closing it means cancel.
	if(!om_prompt)
		return ..()
	var/datum/om/prompt/P = om_prompt
	om_prompt = null
	om_prompt_answer(P, value)
	SStgui.close_uis(src)
	return TRUE

/datum/tgui_bitfield_input/om/tgui_close(mob/user)
	. = ..()
	if(om_prompt)
		om_prompt_closed(om_prompt)
		om_prompt = null
	qdel(src)
