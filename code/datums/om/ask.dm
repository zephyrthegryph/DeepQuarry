// Object-model core: typed prompts (doc/rewrite/object_model_core.md §4.11, §11).
//
// A typed prompt is a /datum/om/prompt/<kind> subtype. Its question and its re-checks are
// declared on the type, its state is typed vars, and its answer lands in a typed var:
//
//	/datum/om/prompt/confirm/leash_offer
//		title = "Become Leashed"
//		ask_flags = ASK_FACE_TO_FACE | ASK_HELD   // re-checked before the answer proc runs
//		var/obj/item/leash/leash                   // state: held as a handle while it's open
//
//	/datum/om/prompt/confirm/leash_offer/prepare()
//		message = "Would you like to be leashed by [asker]?"
//
//	om_ask(pet, /datum/om/prompt/confirm/leash_offer, PROC_REF(leash_accepted), asker = user, subject = src)
//
//	/obj/item/leash/proc/leash_accepted(datum/om/prompt/confirm/leash_offer/ask)
//		... ask.asker, ask.leash: typed, resolved, still valid
//
// Kinds and their answer var:
//   /datum/om/prompt/confirm    yes (TRUE/FALSE). The answer proc runs on yes only unless
//                               answer_on_no = TRUE; declined() runs on no.
//   /datum/om/prompt/choice     choice: one of `choices` (a list, or alert buttons with buttons = TRUE)
//   /datum/om/prompt/text       text (sanitised by the tgui input unless encode = FALSE)
//   /datum/om/prompt/number     number, within min/max
//   /datum/om/prompt/color      picked_color ("#rrggbb")
//   /datum/om/prompt/checklist  picked: the ticked `choices`
//
// Roles: the answerer sees the window; the asker started it (default: the answerer, or the
// flow's actor); the subject is what it is about (default: the receiver when it's an atom, or
// the flow's target). ask_flags (ASK_* in code/__defines/om.dm) re-check them; `requires` are
// check specs read with actor = the answerer and target = the subject; valid() is the type's
// own re-check. Any failure drops the answer and calls refused(reason).
//
// Every datum in a scalar var the type adds (and asker/subject) is held as a handle while the
// window is open, so the prompt never keeps them alive; if one is gone when the answer arrives,
// the answer is dropped. Lists are kept as they are.
//
// om_ask() (a macro) passes the caller's src as the receiver: the answer proc runs on it with
// the prompt as its one argument (a /proc/ path is called globally with the prompt). Named
// arguments set the prompt's vars; `receiver = X` runs the answer proc on X instead of src, and
// the prompt's `receiver` var is that datum (resolved) in every hook. om_prompt() is the plumbing
// underneath and is not called outside code/datums/om (tools/ci/api_lints.py, prompt_spec).
//
// Options on every kind:
//   optional = TRUE      a cancel runs the answer proc anyway, with the answer var null
//                        ("pick one, or cancel for none")
//   cancel_text          confirm: a third button that cancels (Yes/No/Cancel; cancel stops a flow)
//   cancel_choice        choice: the choice that counts as a cancel
//   hold_strong          names of state vars kept as plain references while open (a datum the
//                        prompt created and nothing else owns); the rest are handles
//   ui_refresh           a datum whose tgui windows are refreshed after the answer proc runs
//   key                  the answer's name in an om_ask_sequence()
// A cancel (and cancel_answer) is always accepted: it is never refused by the re-checks.
// answer_value() is the kind's answer (yes, choice, text, ...) for a proc serving several kinds.

/datum/om/prompt
	// ---- declaration (typed prompts; null on the old list form)
	/// The tgui kind the type shows (see om_prompt_show()).
	var/kind_name
	var/title
	var/message
	/// ASK_* re-checks.
	var/ask_flags = NONE
	/// Check specs, actor = the answerer, target = the subject.
	var/list/requires
	/// Deciseconds; 0 waits for as long as the window stays open.
	var/timeout = 0
	/// The proc called with the prompt when no on_answer is passed to om_ask().
	var/answer_proc
	/// The answer a cancel, a closed window or a timeout gives instead (re-checked like any
	/// answer). Null: a cancel calls cancelled().
	var/cancel_answer
	/// A cancel runs the answer proc with the answer var null instead of calling cancelled().
	var/optional = FALSE
	/// State var names held strongly (not as handles) while the window is open.
	var/list/hold_strong
	/// A datum whose tgui windows are refreshed after the answer proc runs.
	var/datum/ui_refresh
	/// The answer's name in an om_ask_sequence().
	var/key
	// ---- roles (held as handles while open)
	/// Who sees the window.
	var/mob/answerer
	var/mob/asker
	var/datum/subject
	/// What the answer proc runs on (om_ask()'s src, or `receiver = X`); null for a global proc.
	var/datum/receiver
	// ---- run state
	/// The answer proc for this run.
	var/answer_ref
	/// The flow waiting on this prompt (flow.dm): held strongly, so the flow lives exactly as
	/// long as its open question.
	var/datum/om/flow/flow
	/// name -> wrapped handle of the state held while the window is open.
	var/list/parked

/// Builds the question from the state (the message naming the asker, the choices). FALSE: don't ask.
/datum/om/prompt/proc/prepare()
	return TRUE

/// The type's own re-check when the answer arrives (the answer var is already set): null, or
/// the reason to drop the answer.
/datum/om/prompt/proc/valid()
	return null

/// A re-check failed when the answer arrived (the prompt's state is resolved, or null if gone).
/datum/om/prompt/proc/refused(reason)
	flow?.stop(reason)

/// The window was closed, cancelled or timed out.
/datum/om/prompt/proc/cancelled()
	flow?.stop("cancelled")

/// confirm: the answer was no.
/datum/om/prompt/proc/declined()
	flow?.stop("declined")

/// Stores `answer` in the kind's typed var. FALSE: don't call the answer proc (declined()).
/datum/om/prompt/proc/take_answer(answer)
	return TRUE

/// The kind's answer (yes, choice, text, number, picked_color, picked, matrix).
/datum/om/prompt/proc/answer_value()
	return null

/// TRUE when `answer` is the kind's cancel button (confirm cancel_text, choice cancel_choice).
/datum/om/prompt/proc/is_cancel_answer(answer)
	return FALSE

/// The spec om_prompt_show() reads, from the typed vars.
/datum/om/prompt/proc/build_spec()
	. = list("kind" = kind_name, "title" = title, "message" = message, "timeout" = timeout)
	if(!isnull(cancel_answer))
		.["cancel_answer"] = cancel_answer

// ---------------------------------------------------------------- kinds

/datum/om/prompt/confirm
	kind_name = "alert"
	var/yes_text = "Yes"
	var/no_text = "No"
	/// Show the no button first.
	var/no_first = FALSE
	/// TRUE: the answer proc also runs on no (read `yes`).
	var/answer_on_no = FALSE
	/// A third button that cancels (Yes/No/Cancel); null: none.
	var/cancel_text
	/// The answer.
	var/yes = FALSE

/datum/om/prompt/confirm/build_spec()
	. = ..()
	var/list/buttons = no_first ? list(no_text, yes_text) : list(yes_text, no_text)
	if(cancel_text)
		buttons += cancel_text
	.["choices"] = buttons

/datum/om/prompt/confirm/answer_value()
	return yes

/datum/om/prompt/confirm/is_cancel_answer(answer)
	return !isnull(cancel_text) && answer == cancel_text

/datum/om/prompt/confirm/take_answer(answer)
	yes = (answer == yes_text)
	return yes || answer_on_no

/datum/om/prompt/choice
	kind_name = "list"
	var/list/choices
	var/default
	/// TRUE: alert buttons instead of a list.
	var/buttons = FALSE
	/// The choice that counts as a cancel ("Cancel" in a button list); null: none.
	var/cancel_choice
	/// The answer.
	var/choice

/datum/om/prompt/choice/answer_value()
	return choice

/datum/om/prompt/choice/is_cancel_answer(answer)
	return !isnull(cancel_choice) && answer == cancel_choice

/datum/om/prompt/choice/build_spec()
	. = ..()
	if(buttons)
		.["kind"] = "alert"
	.["choices"] = choices
	.["default"] = default

/datum/om/prompt/choice/take_answer(answer)
	choice = answer
	return TRUE

/datum/om/prompt/text
	kind_name = "text"
	var/default
	var/max_length = MAX_MESSAGE_LEN
	var/multiline = FALSE
	var/encode = TRUE
	/// The answer.
	var/text

/datum/om/prompt/text/build_spec()
	. = ..()
	.["default"] = default
	.["max_length"] = max_length
	.["multiline"] = multiline
	.["encode"] = encode

/datum/om/prompt/text/answer_value()
	return text

/datum/om/prompt/text/take_answer(answer)
	text = answer
	return TRUE

/datum/om/prompt/number
	kind_name = "number"
	var/default = 0
	var/min = 0
	var/max = INFINITY
	var/round_entry = TRUE
	/// The answer.
	var/number

/datum/om/prompt/number/build_spec()
	. = ..()
	.["default"] = default
	.["min"] = min
	.["max"] = max
	.["round"] = round_entry

/datum/om/prompt/number/answer_value()
	return number

/datum/om/prompt/number/take_answer(answer)
	number = answer
	return TRUE

/datum/om/prompt/color
	kind_name = "color"
	var/default = "#000000"
	/// The answer: "#rrggbb".
	var/picked_color

/datum/om/prompt/color/build_spec()
	. = ..()
	.["default"] = default

/datum/om/prompt/color/answer_value()
	return picked_color

/datum/om/prompt/color/take_answer(answer)
	picked_color = answer
	return TRUE

/datum/om/prompt/checklist
	kind_name = "checkboxes"
	var/list/choices
	var/min_picks = 1
	var/max_picks = 50
	/// The answer: the ticked choices.
	var/list/picked

/datum/om/prompt/checklist/build_spec()
	. = ..()
	.["choices"] = choices
	.["min"] = min_picks
	.["max"] = max_picks

/datum/om/prompt/checklist/answer_value()
	return picked

/datum/om/prompt/checklist/take_answer(answer)
	picked = answer
	return TRUE

/// The ColorMate window. `preview` is the atom painted in place, or a path (a preview is made
/// for the window and deleted with it). The answer is the colour matrix.
/datum/om/prompt/colormatrix
	kind_name = "colormatrix"
	timeout = 30 MINUTES
	var/preview
	var/list/default
	var/matrix_only = FALSE
	/// The tgui state the window uses (null: always).
	var/datum/tgui_state/ui_state
	/// The answer: the matrix.
	var/list/matrix

/datum/om/prompt/colormatrix/build_spec()
	. = ..()
	.["preview"] = preview
	.["default"] = default
	.["matrix_only"] = matrix_only
	.["ui_state"] = ui_state

/datum/om/prompt/colormatrix/answer_value()
	return matrix

/datum/om/prompt/colormatrix/take_answer(answer)
	matrix = answer
	return TRUE

// ---------------------------------------------------------------- launching

/**
 * om_ask()'s body. `receiver` is the caller's src (null in a global proc): the answer proc runs
 * on it. `prompt` is a typed prompt type or instance; `params` (var name -> value) set its
 * vars. Returns the prompt, or null when it wasn't shown (the answerer is gone or has no
 * client, or prepare() said no).
 */
/proc/om_ask_begin(receiver, mob/answerer, prompt, on_answer, list/params)
	var/datum/om/prompt/P = ispath(prompt) ? new prompt : prompt
	if(!istype(P) || !P.kind_name)
		CRASH("om_ask: [prompt] is not a typed prompt (/datum/om/prompt/<kind>)")
	if(params && ("receiver" in params))
		receiver = params["receiver"]
		params = params.Copy()
		params -= "receiver"
	for(var/key in params)
		if(!istext(key))
			CRASH("om_ask: [P.type] was given a positional argument ([key]); name it (var = value)")
		if(!(key in P.vars))
			CRASH("om_ask: [P.type] has no var [key]")
		P.vars[key] = params[key]
	if(istype(answerer, /client))
		var/client/C = answerer
		answerer = C.mob
	if(!isdatum(answerer) || QDELETED(answerer))
		return null
	var/datum/om/flow/F = receiver
	if(istype(F))
		P.flow = F
		if(isnull(P.asker) && ismob(F.actor))
			P.asker = F.actor
		if(isnull(P.subject))
			P.subject = F.target
	P.answerer = answerer
	P.receiver = receiver
	if(isnull(P.asker))
		P.asker = answerer
	if(isnull(P.subject) && isatom(receiver))
		P.subject = receiver
	P.answer_ref = on_answer || P.answer_proc
	if(!P.prepare())
		return null
	var/list/spec = P.build_spec()
	spec["on_cancel"] = /proc/om_ask_cancelled
	spec["on_refused"] = /proc/om_ask_refused
	if(P.flow && !P.flow.park())
		return null
	var/list/names = P.state_var_names(/datum/om/prompt, list("answerer", "asker", "subject", "receiver", "ui_refresh"))
	if(length(P.hold_strong))
		names = names - P.hold_strong
	P.parked = P.park_state(names)
	if(isnull(P.parked))
		P.flow?.stop("gone")
		return null
	if(!om_prompt(receiver, answerer, spec, /proc/om_ask_answered, P))
		P.unpark_state(P.parked)
		P.parked = null
		P.flow?.stop("not asked")
		return null
	return P

/// Restores the prompt's held state. FALSE if a datum in it is gone.
/datum/om/prompt/proc/unpark()
	if(!parked)
		return TRUE
	var/list/held = parked
	parked = null
	return unpark_state(held)

/// The ask_flags, requires and valid(): null, or the reason to drop the answer.
/datum/om/prompt/proc/typed_recheck(datum/E, mob/answerer)
	var/mob/A = asker || answerer
	var/atom/S = subject
	if((ask_flags & (ASK_ALIVE | ASK_CONSCIOUS | ASK_CAPABLE | ASK_ADJACENT | ASK_NEAR_SUBJECT)) && (!ismob(answerer) || !ismob(A)))
		return "not a mob"
	if((ask_flags & ASK_ALIVE) && (answerer.stat == DEAD || A.stat == DEAD))
		return "dead"
	if((ask_flags & ASK_CONSCIOUS) && (answerer.stat != CONSCIOUS || A.stat != CONSCIOUS))
		return "not conscious"
	if((ask_flags & ASK_CAPABLE) && (answerer.incapacitated() || A.incapacitated()))
		return "not able to"
	if((ask_flags & ASK_RESTRAINED) && (!ismob(answerer) || !ismob(A) || answerer.restrained() || A.restrained()))
		return "restrained"
	if(ask_flags & ASK_ADJACENT)
		var/atom/other = (A != answerer) ? A : S
		if(!istype(other) || !answerer.Adjacent(other))
			return "too far away"
	if((ask_flags & ASK_NEAR_SUBJECT) && (!istype(S) || !answerer.Adjacent(S)))
		return "too far away"
	if(ask_flags & ASK_HELD)
		var/reason = om_why_not(/datum/om/check/in_hands, A, S)
		if(!isnull(reason))
			return reason
	if(ask_flags & ASK_CARRIED)
		var/reason = om_why_not(/datum/om/check/carried, A, S)
		if(!isnull(reason))
			return reason
	for(var/check_spec in om_spec_list(requires))
		var/reason = om_why_not(check_spec, answerer, S || E)
		if(!isnull(reason))
			return reason
	// A flow's own re-checks run when it resumes (its state is held until then).
	return valid()

// ---------------------------------------------------------------- continuations (om_prompt plumbing)

/// The answer passed its re-checks (take_answer() already stored it, so valid() could read it).
/proc/om_ask_answered(E, mob/user, answer, datum/om/prompt/P)
	var/proc_ref = P.answer_ref
	if(P.flow)
		P.flow.resume(proc_ref, P)
		return
	if(proc_ref)
		if(copytext("[proc_ref]", 1, 7) == "/proc/")
			call(proc_ref)(P)
		else
			call(P.receiver || E, proc_ref)(P)
	if(P.ui_refresh)
		SStgui.update_uis(P.ui_refresh)

/proc/om_ask_cancelled(E, mob/user, datum/om/prompt/P)
	P.unpark()
	P.cancelled()

/proc/om_ask_refused(E, mob/user, reason, datum/om/prompt/P)
	P.refused(reason)

// ---------------------------------------------------------------- held state (prompts, flows)

/// The vars this type adds over `root` (plus `extra`): its state. Cached per type.
/datum/om/proc/state_var_names(root, list/extra)
	var/datum/D = src
	var/static/list/by_type = list()
	var/key = "[D.type]"
	var/list/names = by_type[key]
	if(names)
		return names
	var/static/list/base_by_root = list()
	var/list/base = base_by_root["[root]"]
	if(!base)
		base = list()
		var/datum/proto = new root
		for(var/name in proto.vars)
			base[name] = TRUE
		base_by_root["[root]"] = base
	names = extra ? extra.Copy() : list()
	for(var/name in D.vars)
		if(!base[name])
			names += name
	by_type[key] = names
	return names

/// Swaps every datum (or client) in `names` for a handle. Returns name -> handle, or null if
/// one is already deleted (nothing is changed then).
/datum/om/proc/park_state(list/names)
	var/datum/D = src
	var/list/held = list()
	for(var/name in names)
		var/value = D.vars[name]
		if(!isdatum(value) && !istype(value, /client))
			continue
		var/datum/V = value
		if(isdatum(V) && QDELETED(V))
			return null
		held[name] = om_prompt_wrap(value)
	for(var/name in held)
		D.vars[name] = null
	return held

/// Puts parked state back. FALSE if a datum in it is gone (its var stays null).
/datum/om/proc/unpark_state(list/held)
	var/datum/D = src
	. = TRUE
	for(var/name in held)
		var/value = om_prompt_unwrap(held[name])
		if(isnull(value))
			. = FALSE
		D.vars[name] = value
