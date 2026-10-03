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
	/// What the answerer is asked.
	var/question
	/// The window's title (null: the kind's own).
	var/title
	/// The answer, once answered: the uniform value field every prompt kind reads it from.
	var/value
	/// The tgui window or radial ring showing it, while it is open. Closing it is a cancellation.
	var/datum/window

CAPABILITIES(/datum/prompt, ref_one(nameof(window), /datum))

/// The prompt asks its answerer: a player with a client sees the kind's window; anything else (a test driver, an AI) answers through request_answer().
/datum/prompt/begin()
	var/mob/user = answerer
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
	return

/// The kind's window for `user`, or null when there is nothing to ask. The kinds override it.
/datum/prompt/proc/present(mob/user)
	return null

/// The window goes away: the request ended (answered, cancelled, timed out). A kind with another window overrides it.
/datum/prompt/proc/dismiss()
	var/datum/shown = window
	rel_clear(src, nameof(window))
	if(shown && !QDELETED(shown))
		SStgui.close_uis(shown)

/// A window's answer was refused: the question stays open, so it is shown again (a prompt with no client to show it to just waits).
/datum/prompt/proc/reopen()
	var/mob/user = answerer
	if(!istype(user) || !user.client || !is_open())
		return
	dismiss()
	var/datum/shown = present(user)
	if(!isnull(shown))
		rel_set(src, nameof(window), shown)

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

/datum/prompt/yes_no/normalize(given)
	return !!given

/datum/prompt/yes_no/answer_of_button(button)
	return button == "Yes"

/datum/prompt/yes_no/present(mob/user)
	var/datum/tgui_alert/prompt/alert = new(user, question, title || "Confirm", list("Yes", "No"), timeout, TRUE, GLOB.tgui_always_state)
	rel_set(alert, nameof(alert.prompt), src)
	alert.tgui_interact(user)
	return alert

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

/datum/prompt/text/normalize(given)
	if(!istext(given))
		return null
	if(name_text)
		given = strip_name_tokens(given)
	if(max_len && length(given) > max_len)
		given = copytext(given, 1, max_len + 1)
	return given

/datum/prompt/text/present(mob/user)
	var/datum/tgui_input_text/prompt/box = new(user, question, title || "Text Input", default, max_len, multiline, TRUE, timeout, GLOB.tgui_always_state)
	rel_set(box, nameof(box.prompt), src)
	box.tgui_interact(user)
	return box

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

/datum/prompt/number/present(mob/user)
	var/datum/tgui_input_number/prompt/box = new(user, question, title || "Number Input", default, isnull(max_value) ? INFINITY : max_value, isnull(min_value) ? 0 : min_value, timeout, isnull(step), GLOB.tgui_always_state)
	rel_set(box, nameof(box.prompt), src)
	box.tgui_interact(user)
	return box

/datum/request
	/// The workflow step name an asks() gave this request (A.step("name")).
	var/step_name

/// Called by request_open() with the asking op's act (null outside an op), after the fields are set and before the request is shown.
/datum/request/proc/prepare(datum/act/A)
	return
