// Prompts shown inside a window (doc/rewrite/final_api.html, section 13 "Requests, prompts and workflows (X3)": "Transport: the window a prompt, or an
// interface() modal, is shown in"). A prompt with inline = TRUE is a tgui modal of the window of the holder that asked: the client's ComplexModal draws it
// from data["modal"] (present_tgui_data() adds the holder's modal), answers it with the window's modal_answer action and closes it with modal_close, so the
// client needs nothing new. A window opens a modal with `modal_open` (its id): an op whose window action is "modal:<id>" answers it, and asks(..., inline) is the
// modal it opens:
//
//   op("add_to_buffer", ui_act("modal:add_to_buffer", arg("arguments")),
//       asks(/datum/prompt/number, fields = list("question" = "Amount to add", "inline" = TRUE), step = "amount"), then(PROC_REF(added)))
//
// One modal per window at a time, as the modal system always had: opening another ends the first one's question cancelled.

/// The modal of a prompt: the kind says its type and its data (inline_type(), inline_data()), and its answer is the prompt's.
/datum/tgui_modal/prompt
	var/datum/prompt/prompt

CAPABILITIES(/datum/tgui_modal/prompt)
	ref_one(nameof(prompt), /datum/prompt)

/datum/tgui_modal/prompt/New(datum/prompt/asked, id, list/arguments)
	..(id, asked.question, null, arguments)
	rel_set(src, nameof(prompt), asked)
	modal_type = asked.inline_type()

/datum/tgui_modal/prompt/preprocess_answer(answer)
	. = ..()
	if(prompt)
		. = prompt.inline_preprocess(.)

/datum/tgui_modal/prompt/on_answer(answer)
	var/datum/prompt/asked = prompt
	if(!asked || !asked.is_open())
		return FALSE
	var/value = asked.inline_answer(answer)
	if(isnull(value))
		return FALSE
	prompt_window_answer(asked, value)
	return TRUE

/datum/tgui_modal/prompt/to_data()
	. = ..()
	prompt?.inline_data(.)

/// Cleared by the client or replaced: the question ends cancelled.
/datum/tgui_modal/prompt/closed()
	var/datum/prompt/asked = prompt
	if(asked && asked.is_open())
		rel_clear(src, nameof(prompt))
		prompt_window_closed(asked)

/// The prompt asks inline: its modal goes into the window of the holder that asked (the pending op's holder, or the owner of a request opened outside an op).
/datum/prompt/begin_inline(mob/user)
	var/datum/host = owner
	var/datum/pending_op/pending = owner
	if(istype(pending))
		host = pending.holder
	if(!host || QDELETED(host))
		last_error = "no window to show it in"
		after(src, 1 TICK, TYPE_PROC_REF(/datum/prompt, nothing_to_ask), key = "request_begin")
		return
	var/datum/tgui_modal/prompt/modal = new(src, modal_id || "[type]", modal_args)
	tgui_modal_new(host, modal)
	rel_set(src, nameof(window), modal)
	log_game("prompt: [type] opened inline in [host.type] for [key_name(user)]")

/// The question ended or is shown again: its modal leaves the window if it is still the one showing.
/datum/prompt/dismiss_inline()
	var/datum/tgui_modal/prompt/shown = window
	rel_clear(src, nameof(window))
	if(!istype(shown))
		return
	var/datum/host = shown.owning_source()
	rel_clear(shown, nameof(shown.prompt)) // clearing it does not cancel what ended already
	if(host && LAZYACCESS(GLOB.tgui_modals, REF(host)) == shown)
		tgui_modal_clear(host)

/datum/prompt/presentation_refused(mob/user, reason)
	to_chat(user, span_warning("[reason]"))
