// Central dispatch (doc/rewrite/dx_conventions.md §7): every player-triggered handler (capability
// entries, ui_<action> procs, forms, prompt answers) runs through dispatch_call(), which:
//   - records the action's context so ask_*() can re-validate it when the answer arrives;
//   - runs the handler asynchronously if it sleeps (a prompt), so no handler writes INVOKE_ASYNC;
//   - afterwards marks the target changed, adds the user's fingerprint and writes the declared log.
// Handlers never call add_fingerprint(), log_game(), log_admin() or message_admins() for this.

/// What ask_*() re-checks when an answer arrives: who acted, on what, with what, through which
/// entry (an interaction's requirements) or window (a tgui state).
/datum/dispatch_context
	var/mob/user
	var/datum/target
	var/obj/item/held
	var/datum/interaction/entry
	var/datum/tgui/ui

/datum/dispatch_context/New(mob/user, datum/target, obj/item/held, datum/interaction/entry, datum/tgui/ui)
	src.user = user
	src.target = target
	src.held = held
	src.entry = entry
	src.ui = ui

/// Null when the action is still valid for its user, else the reason (told to the player by ask_*()).
/datum/dispatch_context/proc/invalid_reason()
	if(QDELETED(user))
		return "you are gone"
	if(QDELETED(target))
		return "it's gone"
	if(user.stat != CONSCIOUS)
		return "you can't do that now"
	if(ui)
		if(ui.status != STATUS_INTERACTIVE)
			return "you can't use it from here any more"
		return null
	if(entry && isatom(target))
		if(held && QDELETED(held))
			return "what you were holding is gone"
		var/reason = entry.why_not(user, target, held)
		if(reason)
			return reason
	else if(isatom(target) && !dq_interaction_reach(user, target, held))
		return "you moved too far away"
	return null

/// The context of the handler running now (ask_*() captures it before it sleeps).
GLOBAL_DATUM(dispatch_context_now, /datum/dispatch_context)

/**
 * Calls proc_ref on target with the named args (arglist), inside ctx. Returns the handler's result,
 * or null if it slept (it continues on its own and records itself when it finishes). A named arg
 * the handler doesn't declare is a runtime DM raises; it is caught, logged and refused here.
 */
/proc/dispatch_call(datum/dispatch_context/ctx, datum/target, proc_ref, list/named, action_name, log)
	set waitfor = FALSE
	var/datum/dispatch_context/outer = GLOB.dispatch_context_now
	GLOB.dispatch_context_now = ctx
	var/result
	var/failed = FALSE
	try
		result = call(target, proc_ref)(arglist(named))
	catch(var/exception/e)
		failed = TRUE
		stack_trace("dispatch: [target.type].[proc_ref] ([action_name]) by [key_name(ctx.user)] failed: [e] ([e.file]:[e.line])")
		if(ctx.user)
			refuse(ctx.user, "that didn't work")
	GLOB.dispatch_context_now = outer
	if(failed || result == UI_REFUSED || QDELETED(target))
		return failed ? FALSE : result
	changed(target)
	dispatch_record(ctx.user, target, action_name, log, null)
	return result

/// Tells user why an action was refused; a ui_<action> or entry handler returns its result.
/proc/refuse(mob/user, text)
	if(user && text)
		to_chat(user, span_warning(text))
		#ifdef UNIT_TESTS
		var/list/capture = GLOB.refuse_capture
		capture?.Add(list(list(user, text)))
		#endif
	return UI_REFUSED

#ifdef UNIT_TESTS
/// Test builds: while a test sets this to a list, refuse() also appends list(user, text) to it.
GLOBAL_VAR(refuse_capture)
#endif

/**
 * The fingerprint and the declared log line for a successful dispatch. log: LOG_GAME, LOG_ADMIN or
 * null. details: an assoc list rendered "k=v" after the line.
 */
/proc/dispatch_record(mob/user, datum/target, action, log, list/details)
	if(isatom(target) && isliving(user))
		var/atom/A = target
		A.add_fingerprint(user)
	if(!log)
		return
	var/line = "[key_name(user)] [action]"
	if(target && target != user)
		line += " on [target] ([target.type])"
	if(isatom(target))
		line += " at [AREACOORD(target)]"
	if(length(details))
		var/list/parts = list()
		for(var/k in details)
			parts += "[k]=[details[k]]"
		line += " ([jointext(parts, ", ")])"
	if(log & LOG_ADMIN)
		log_admin(line)
		message_admins(line)
	else
		log_game(line)
