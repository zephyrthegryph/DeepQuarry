// Linear prompts and forms (doc/rewrite/dx_conventions.md §6).
//
//	var/networks = ask_text(user, "Which networks?", default = "SS13")
//	if(!networks)
//		return   // cancelled, or the action is no longer valid (the player was told why)
//
// ask_*() captures the context of the dispatched action it runs in (user, target, held, the entry's
// requirements or the window's state) BEFORE it sleeps, and re-validates it when the answer
// arrives: a failure returns null and tells the player why. Handlers that prompt are already
// async (dispatch_call() runs with waitfor = FALSE). Outside a dispatch, pass target = to get a
// reach re-check. `needs =` (e.g. list(GLOBAL_PROC_REF(chk_conscious))) adds checks for a prompt outside an
// entry, re-run on the answer (library/checks.dm). Text is sanitised, numbers clamped.

/// The context to re-check for a prompt: the running dispatch, or a fresh one for target.
/**
 * The context an ask_*() re-checks. third_party: the answerer is not the acting user (a vore consent
 * prompt, "let them in?"): the running action's context belongs to the actor, so the answerer gets a
 * fresh one that checks only the answerer (and `target`, `needs` when given).
 */
/proc/ask_context(mob/user, datum/target, datum/dispatch_context/context, needs, third_party = FALSE)
	if(context)
		return ask_context_needs(context, needs)
	if(third_party)
		return ask_context_needs(new /datum/dispatch_context(user, target), needs)
	var/datum/dispatch_context/ctx = GLOB.dispatch_context_now
	if(ctx && ctx.user == user && (!target || ctx.target == target))
		if(ctx.returned)
			// A resumed handler asking again: unbind while it sleeps on the prompt.
			GLOB.dispatch_context_now = null
		return ask_context_needs(ctx, needs)
	return ask_context_needs(new /datum/dispatch_context(user, target), needs)

/// Adds the explicit needs (a ref or a list of them; global chk_* refs or target procs) to ctx.
/proc/ask_context_needs(datum/dispatch_context/ctx, needs)
	if(needs)
		LAZYINITLIST(ctx.ask_needs)
		ctx.ask_needs |= (islist(needs) ? needs : list(needs))
	return ctx

/// "[user]|[target]|[action]" -> TRUE while that prompt is open (M7: one per user per action).
GLOBAL_LIST_EMPTY(asks_open)

/// The key of ctx's action for the one-open-prompt rule.
/proc/ask_key(datum/dispatch_context/ctx)
	var/action = ctx.entry ? ctx.entry.id : (ctx.ui ? "ui" : "direct")
	return "[ctx.user ? SHARED_CACHE_UID(ctx.user) : "-"]|[ctx.target ? SHARED_CACHE_UID(ctx.target) : "-"]|[action]"

/// Claims the prompt slot of ctx's action for its user. FALSE (and a message) when one is already open.
/proc/ask_open(datum/dispatch_context/ctx)
	var/key = ask_key(ctx)
	if(GLOB.asks_open[key])
		to_chat(ctx.user, span_warning("You already have that open."))
		return FALSE
	GLOB.asks_open[key] = TRUE
	return TRUE

/proc/ask_close(datum/dispatch_context/ctx)
	GLOB.asks_open -= ask_key(ctx)

/// TRUE if ctx still holds (the answer counts), else tells the user why and returns FALSE. On TRUE
/// ctx becomes the current context again, so the handler's next ask_*() re-checks the same action.
/proc/ask_still_valid(datum/dispatch_context/ctx)
	var/reason = ctx.invalid_reason()
	if(!reason)
		if(ctx.returned)
			GLOB.dispatch_context_now = ctx
		return TRUE
	to_chat(ctx.user, span_warning("Never mind: [reason]."))
	return FALSE

/proc/ask_text(mob/user, message, title, default, max_length = MAX_MESSAGE_LEN, multiline = FALSE, datum/target, datum/dispatch_context/context, needs, third_party = FALSE)
	var/datum/dispatch_context/ctx = ask_context(user, target, context, needs, third_party)
	if(!ask_open(ctx))
		return null
	var/answer = tgui_input_text(user, message, title || "Input", default, max_length, multiline) // ALLOW(scheduler): ask_*() is the capability system's one blocking prompt primitive (re-validates after the answer)
	ask_close(ctx)
	if(isnull(answer) || !ask_still_valid(ctx))
		return null
	answer = sanitize(answer, max_length)
	return length(answer) ? answer : null

/proc/ask_number(mob/user, message, min_value = 0, max_value = INFINITY, title, default = 0, round_value = TRUE, datum/target, datum/dispatch_context/context, needs, third_party = FALSE)
	var/datum/dispatch_context/ctx = ask_context(user, target, context, needs, third_party)
	if(!ask_open(ctx))
		return null
	var/answer = tgui_input_number(user, message, title || "Input", default, max_value, min_value, 0, round_value) // ALLOW(scheduler): ask_*() is the capability system's one blocking prompt primitive (re-validates after the answer)
	ask_close(ctx)
	if(isnull(answer) || !ask_still_valid(ctx))
		return null
	return ui_number(answer, min_value, max_value, round_value ? 1 : 0)

/proc/ask_list(mob/user, message, list/choices, title, default, datum/target, datum/dispatch_context/context, needs, third_party = FALSE)
	var/datum/dispatch_context/ctx = ask_context(user, target, context, needs, third_party)
	if(!ask_open(ctx))
		return null
	var/answer = tgui_input_list(user, message, title || "Select", choices, default) // ALLOW(scheduler): ask_*() is the capability system's one blocking prompt primitive (re-validates after the answer)
	ask_close(ctx)
	if(isnull(answer) || !ask_still_valid(ctx))
		return null
	return ui_choice(answer, choices)

/// TRUE for yes, FALSE for no, null when cancelled or no longer valid.
/proc/ask_yes_no(mob/user, message, title, datum/target, datum/dispatch_context/context, needs, third_party = FALSE)
	var/datum/dispatch_context/ctx = ask_context(user, target, context, needs, third_party)
	if(!ask_open(ctx))
		return null
	var/answer = tgui_alert(user, message, title || "Confirm", list("Yes", "No")) // ALLOW(scheduler): ask_*() is the capability system's one blocking prompt primitive (re-validates after the answer)
	ask_close(ctx)
	if(isnull(answer) || !ask_still_valid(ctx))
		return null
	return answer == "Yes"

/proc/ask_color(mob/user, message, title, default = "#ffffff", datum/target, datum/dispatch_context/context, needs, third_party = FALSE)
	var/datum/dispatch_context/ctx = ask_context(user, target, context, needs, third_party)
	if(!ask_open(ctx))
		return null
	var/answer = tgui_color_picker(user, message, title || "Colour", default)
	ask_close(ctx)
	if(isnull(answer) || !ask_still_valid(ctx))
		return null
	return sanitize_hexcolor(answer, default)

/// One of `candidates` (mobs), by name.
/proc/ask_mob(mob/user, message, list/candidates, title, datum/target, datum/dispatch_context/context, needs, third_party = FALSE)
	var/list/by_name = list()
	for(var/mob/M as anything in candidates)
		by_name[avoid_assoc_duplicate_keys(M.name, by_name)] = M
	var/choice = ask_list(user, message, by_name, title, target = target, context = context, needs = needs, third_party = third_party)
	if(isnull(choice))
		return null
	var/mob/M = by_name[choice]
	return QDELETED(M) ? null : M

// ---- forms: form = list(choice_field(), text_field(), number_field()) on a capability entry ----

/datum/form_field
	/// The handler's argument name.
	var/name
	var/message
	var/title

/// Asks this field in ctx; null cancels the form.
/datum/form_field/proc/ask(datum/dispatch_context/ctx)
	return null

/datum/form_field/choice
	/// A list, or a PROC_REF on the target returning one ((mob/user) -> list).
	var/choices

/datum/form_field/choice/ask(datum/dispatch_context/ctx)
	var/list/L = istext(choices) ? holder_call(ctx.target, choices, list(ctx.user)) : choices
	return ask_list(ctx.user, message || "Choose [name]:", L, title, context = ctx)

/datum/form_field/text
	var/max_length = MAX_MESSAGE_LEN
	var/default

/datum/form_field/text/ask(datum/dispatch_context/ctx)
	return ask_text(ctx.user, message || "Enter [name]:", title, default, max_length, context = ctx)

/datum/form_field/number
	var/min_value = 0
	var/max_value = INFINITY
	var/default = 0

/datum/form_field/number/ask(datum/dispatch_context/ctx)
	return ask_number(ctx.user, message || "Enter [name]:", min_value, max_value, title, default, context = ctx)

/proc/choice_field(name, choices, message, title)
	var/datum/form_field/choice/F = new
	F.name = name
	F.choices = choices
	F.message = message
	F.title = title
	return F

/proc/text_field(name, max_length = MAX_MESSAGE_LEN, message, title, default)
	var/datum/form_field/text/F = new
	F.name = name
	F.max_length = max_length
	F.message = message
	F.title = title
	F.default = default
	return F

/proc/number_field(name, min_value = 0, max_value = INFINITY, message, title, default = 0)
	var/datum/form_field/number/F = new
	F.name = name
	F.min_value = min_value
	F.max_value = max_value
	F.message = message
	F.title = title
	F.default = default
	return F
