// The prompt kinds an op's workflow can ask (doc/rewrite/final_api.html, section 13 "Requests, prompts and workflows (X3)"). A prompt is a request a
// player answers; its answer is the uniform `value` field. This file is the base every kind shares and the three the engine itself uses (confirms()
// is asks(/datum/prompt/yes_no, question = "text")); the library declares the rest (code/library/prompts/: choice, color, checklist, bitfield).
//
// A kind overrides what it needs, each with `src` the prompt:
//
//   prepare(datum/act/A)   fills its fields from the asking op's act before anything is shown (a choice list the holder computes)
//   present(mob/user)      the window the answerer sees, a tgui window or a radial ring (code/engine/present/prompt_windows.dm); null: nothing to ask
//   normalize(value)       the answer cleaned up: clamped, trimmed, sanitised (the schema's job, section 4)
//   refusal(value)         null when the (normalised) answer is allowed, else the reason; a refused answer leaves the prompt open
//
// A field whose value is a handler, written `computed(PROC_REF(x))`, is computed when the op asks: x(datum/act/op/A) returns the value. An answer
// reaches the request layer through request_submit() (a window) or request_answer() (the test driver), so both go through normalize() and refusal().

/datum/prompt
	/// asks(..., fields = list("inline" = TRUE)): the question is shown inside the window of the holder that asked, as a tgui modal of that window (doc section 13,
	/// "Transport"), not in a window of its own. The text, number, list (not radial) and yes_no kinds have an inline form; any other opens its own window as before.
	var/inline = FALSE
	/// The inline modal's id (the client's ComplexModal reads it: "analyze", "add_to_buffer"): the op's window action without its `modal:` prefix by default.
	var/modal_id
	/// What the client passed to the modal and takes back (modal_open's `arguments`: how windows chain modals); the op's arg("arguments") by default.
	var/list/modal_args
	/// What the answerer is asked.
	var/question
	/// The window's title (null: the kind's own).
	var/title
	/// The tgui window or radial ring showing it, while it is open. Closing it is a cancellation.
	var/datum/window
	/// How many times the answerer asked it again while it was open (the window was focused, not duplicated).
	var/focused = 0

CAPABILITIES(/datum/prompt)
	ref_one(nameof(window), /datum)

/// The prompt asks its answerer: a player with a client sees the kind's window; anything else (a test driver, an AI) answers through request_answer().
/datum/prompt/begin()
	var/mob/user = answerer
	if(inline && inline_type() && istype(user))
		begin_inline(user)
		return
	if(!istype(user) || !user.client)
		return
	var/datum/shown = present(user)
	if(isnull(shown))
		// nothing to ask (an empty list): the prompt ends cancelled on the next tick, never inside the call that opened it
		last_error = "nothing to ask"
		after(src, 1 TICK, TYPE_PROC_REF(/datum/prompt, nothing_to_ask), key = "request_begin")
		return
	rel_set(src, nameof(window), shown)
	log_game("prompt: [type] opened for [key_name(user)]")

/datum/prompt/proc/nothing_to_ask()
	request_end(src, REQ_CANCELLED, null)

/// Fills the prompt from the asking op's act, before it is shown. `A` is null for a request opened outside an op.
/datum/prompt/prepare(datum/act/A)
	if(!inline || !istype(A, /datum/act/op))
		return
	var/datum/act/op/OA = A
	if(isnull(modal_id))
		var/action = OA.oplan?.ui_action || OA.key
		modal_id = copytext(action, 1, length(OP_UI_MODAL_PREFIX) + 1) == OP_UI_MODAL_PREFIX ? copytext(action, length(OP_UI_MODAL_PREFIX) + 1) : action
	if(isnull(modal_args))
		var/list/passed = OA.args?["arguments"]
		if(islist(passed))
			modal_args = passed.Copy()

/// The kind's window for `user`, or null when there is nothing to ask. The kinds override it.
/datum/prompt/proc/present(mob/user)
	return null

/// The window goes away: the request ended (answered, cancelled, timed out). A kind with another window overrides it.
/datum/prompt/proc/dismiss()
	rel_clear(src, nameof(window))

/// A window's answer was refused: the question stays open, so it is shown again (a prompt with no client to show it to just waits).
/datum/prompt/proc/reopen()
	var/mob/user = answerer
	if(inline && inline_type() && istype(user) && is_open())
		dismiss_inline()
		begin_inline(user)
		return
	if(!istype(user) || !user.client || !is_open())
		return
	dismiss()
	var/datum/shown = present(user)
	if(!isnull(shown))
		rel_set(src, nameof(window), shown)

/// The answerer asked the same question again while it is open: its window comes to the front and is refreshed, and no second one opens. A prompt
/// nobody can see (a test driver, an AI) has nothing to focus.
/datum/prompt/proc/focus()
	var/mob/user = answerer
	focused++
	if(!is_open() || !istype(user) || !user.client)
		return
	var/datum/shown = window
	if(isnull(shown) || QDELETED(shown))
		return
	return focus_transport(user, shown)

/// Bring an existing question to the front through its presentation transport.
/datum/prompt/proc/focus_transport(mob/user, datum/shown)
	return

// ---- the inline form: a modal of the asking holder's window (code/engine/present/prompt_modals.dm) ----

/// The modal type that shows this kind inline ("input", "choice", "boolean"), or null when the kind has none (it opens its own window).
/datum/prompt/proc/inline_type()
	return null

/// The answer from the client's text, before it reaches the modal's check (a boolean modal answers 0 or 1).
/datum/prompt/proc/inline_preprocess(answer)
	return answer

/// The value the client's answer means for this kind, or null when it means none (the modal stays open).
/datum/prompt/proc/inline_answer(answer)
	return answer

/// The fields this kind adds to its modal's data (value, choices, labels).
/datum/prompt/proc/inline_data(list/data)
	return

/// What a button of the kind's alert window answers (the button's own text by default).
/datum/prompt/proc/answer_of_button(button)
	return button

/// The answer as the prompt keeps it: the schema's normaliser. The base keeps it as given.
/datum/prompt/proc/normalize(given)
	return given

/// null when `given` (already normalised) is an allowed answer, else why not. Reads only.
/datum/prompt/proc/refusal(given)
	return null

/// A yes or no. "No" ends the op and nothing is spent. confirms("text") asks it.
/datum/prompt/yes_no
	question = "Are you sure?"
	timeout = 30 SECONDS
	/// The labels of the two buttons ("Confirm" / "Cancel", "Launch" / "Cancel"). A label that depends on the asking op is computed(PROC_REF(x)).
	var/yes_text = "Yes"
	var/no_text = "No"
	/// The no button comes first.
	var/no_first = FALSE

/datum/prompt/yes_no/normalize(given)
	return !!given

/// A "no" spends nothing (a request's costs go with a yes).
/datum/prompt/yes_no/confirmed()
	return !!value

/datum/prompt/yes_no/inline_type()
	return "boolean"

/datum/prompt/yes_no/inline_preprocess(answer)
	return text2num(answer) || FALSE

/datum/prompt/yes_no/inline_answer(answer)
	return !!answer

/datum/prompt/yes_no/inline_data(list/data)
	data["yes_text"] = yes_text
	data["no_text"] = no_text

/datum/prompt/yes_no/answer_of_button(button)
	return button == yes_text


/// A line of text.
/datum/prompt/text
	question = "Enter text."
	timeout = 60 SECONDS
	/// The longest answer; a longer one is cut.
	var/max_len = MAX_MESSAGE_LEN
	/// The text window shows a multi-line box.
	var/multiline = FALSE
	/// The answer names something (an atom, a label, a tag): its % is stripped.
	var/name_text = FALSE
	/// What the box starts with.
	var/default
	/// The window HTML-encodes the answer (the default; a prompt whose answer is shown as plain text, or fed to say(), turns it off).
	var/encode = TRUE

/datum/prompt/text/normalize(given)
	if(!istext(given))
		return null
	if(name_text)
		given = strip_name_tokens(given)
	if(max_len && length(given) > max_len)
		given = copytext(given, 1, max_len + 1)
	return given

/datum/prompt/text/inline_type()
	return "input"

/datum/prompt/text/inline_data(list/data)
	data["value"] = default


/// A number.
/datum/prompt/number
	question = "Enter a number."
	timeout = 60 SECONDS
	/// The range an answer is clamped into (null: unbounded).
	var/min_value
	var/max_value
	/// Answers are rounded to a multiple of this (null: any).
	var/step
	var/default = 0
	/// The window rounds what is typed to a whole number (when no step is set). FALSE takes decimals.
	var/round_entry = TRUE

/datum/prompt/number/normalize(given)
	if(!isnum(given))
		given = text2num(given)
	if(!isnum(given))
		return null
	if(!isnull(step))
		given = round(given, step)
	if(!isnull(min_value))
		given = max(given, min_value)
	if(!isnull(max_value))
		given = min(given, max_value)
	return given

/datum/prompt/number/refusal(given)
	return isnum(given) ? null : "that is not a number"

/datum/prompt/number/inline_type()
	return "input"

/datum/prompt/number/inline_answer(answer)
	return text2num(answer)

/datum/prompt/number/inline_data(list/data)
	data["value"] = "[default]"


/datum/request
	/// The workflow step name an asks() gave this request (A.step("name")).
	var/step_name

/// Called by request_open() with the asking op's act (null outside an op), after the fields are set and before the request is shown.
/datum/request/proc/prepare(datum/act/A)
	return
