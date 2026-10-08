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
	/// Extra `needs` (ask_*(needs =)): re-run on the answer, like an entry's, against the target.
	var/list/ask_needs
	/// dispatch_call() has returned to its caller (TRUE once the handler finished or slept).
	var/returned = FALSE
	/// A target was given (a null target means "none", never "deleted").
	var/had_target = FALSE

/datum/dispatch_context/New(mob/user, datum/target, obj/item/held, datum/interaction/entry, datum/tgui/ui)
	src.user = user // ALLOW(ownership): a dispatch context is a short-lived record of one dispatch: its fields are plain references that die with the call
	src.target = target // ALLOW(ownership): a dispatch context is a short-lived record of one dispatch: its fields are plain references that die with the call
	had_target = !isnull(target)
	src.held = held // ALLOW(ownership): a dispatch context is a short-lived record of one dispatch: its fields are plain references that die with the call
	src.entry = entry // ALLOW(ownership): a dispatch context is a short-lived record of one dispatch: its fields are plain references that die with the call
	src.ui = ui // ALLOW(ownership): a dispatch context is a short-lived record of one dispatch: its fields are plain references that die with the call

/// Null when the action is still valid for its user, else the reason (told to the player by ask_*()).
/datum/dispatch_context/proc/invalid_reason()
	if(QDELETED(user))
		return "you are gone"
	// The target is optional (a native verb, a Topic, world code): only a target that existed and was
	// deleted since refuses. Consciousness is not assumed: ghosts and admins answer prompts too; an
	// action that needs a conscious user says so in its needs (chk_conscious).
	if(had_target && QDELETED(target))
		return "it's gone"
	if(ask_needs)
		var/needs_reason = cap_needs_reason(target, user, held, ask_needs)
		if(needs_reason)
			return needs_reason
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
 * The current context is set only while the handler runs synchronously: when it sleeps, control
 * comes back here and the outer context is restored, so a sleeping handler never leaks its context
 * to unrelated code (ask_*() captured it before sleeping and re-binds it when the answer arrives).
 */
/proc/dispatch_call(datum/dispatch_context/ctx, datum/target, proc_ref, list/named, action_name, log, datum/runs_on)
	var/datum/dispatch_context/outer = GLOB.dispatch_context_now
	GLOB.dispatch_context_now = ctx
	ctx.returned = FALSE
	. = dispatch_call_inner(ctx, target, proc_ref, named, action_name, log, runs_on)
	ctx.returned = TRUE
	GLOB.dispatch_context_now = outer

/// runs_on: the datum the proc is called on when it isn't the target (a capability flyweight whose
/// handler takes the holder as `holder`); the target is still what gets marked, fingerprinted and logged.
/proc/dispatch_call_inner(datum/dispatch_context/ctx, datum/target, proc_ref, list/named, action_name, log, datum/runs_on)
	set waitfor = FALSE // ALLOW(scheduler): a capability handler may ask the user mid-action; the dispatcher must not block its caller
	var/result
	var/failed = FALSE
	try
		if(!runs_on && IS_GLOBAL_PROC_REF(proc_ref))
			// A global handler takes the holder as its `holder` argument (holder_call()).
			var/list/with_holder = named ? named.Copy() : list()
			with_holder["holder"] = target
			result = call(proc_ref)(arglist(with_holder))
		else
			result = call(runs_on || target, proc_ref)(arglist(named))
	catch(var/exception/e)
		failed = TRUE
		var/msg = "dispatch: [target.type].[proc_ref] ([action_name]) by [key_name(ctx.user)] failed: [e] ([e.file]:[e.line])"
		GLOB.dispatch_failures += msg
		if(!GLOB.dispatch_failure_expected)
			stack_trace(msg)
		else
			log_runtime(msg)
		if(ctx.user)
			refuse(ctx.user, "that didn't work")
	if(ctx.returned && GLOB.dispatch_context_now == ctx)
		// Resumed after a sleep: an ask_*() re-bound ctx; unbind it now the handler is done.
		GLOB.dispatch_context_now = null
	if(failed || QDELETED(target))
		return failed ? FALSE : result
	// Every dispatched call marks its target (it may have written plain vars); only a success
	// (truthy, not refused: a cancelled prompt returns null) is fingerprinted and logged.
	changed(target)
	if(dispatch_succeeded(result))
		dispatch_record(ctx.user, target, action_name, log, null)
		if(istype(ctx.entry, /datum/interaction/capability) && isatom(target))
			cap_entry_cooldown_start(target, ctx.entry)
	return result

/// Handler failures this round (the dispatch tests read them).
GLOBAL_LIST_EMPTY(dispatch_failures)
/// Set by a test around a deliberate failure: logged without a stack trace.
GLOBAL_VAR_INIT(dispatch_failure_expected, FALSE)
/// Test builds: "[action]|[fingerprinted]|[logged]" per dispatch_record() (the dispatch tests read it).
GLOBAL_LIST_EMPTY(dispatch_records)
/// The last dispatch_record() call (user, target, action, log). Only unit tests write and read it.
GLOBAL_LIST_EMPTY(dispatch_last_record)

/// Whether a handler's result counts as done: truthy and not UI_REFUSED.
/proc/dispatch_succeeded(result)
	return result && result != UI_REFUSED

/// Tells user why an action was refused; a ui_<action> or entry handler returns its result.
/proc/refuse(mob/user, text)
	if(user && text)
		to_chat(user, span_warning(text))
		#ifdef UNIT_TESTS
		var/list/capture = GLOB.refuse_capture
		capture?.Add(list(list(user, text)))
		#endif
	return UI_REFUSED

/// Test builds: while a test sets this to a list, refuse() also appends list(user, text) to it.
/// Declared in every build so the linter, which reads the tests without UNIT_TESTS, resolves it.
GLOBAL_VAR(refuse_capture)

/**
 * The fingerprint and the declared log line for a successful dispatch. log: LOG_GAME, LOG_ADMIN or
 * null. details: an assoc list rendered "k=v" after the line.
 */
/proc/dispatch_record(mob/user, datum/target, action, log, list/details)
#ifdef UNIT_TESTS
	GLOB.dispatch_last_record = list("user" = user, "target" = target, "action" = action, "log" = log)
#endif
	if(isatom(target) && isliving(user))
		var/atom/A = target
		A.add_fingerprint(user)
#if defined(UNIT_TESTS)
	GLOB.dispatch_records += "[action]|[isatom(target) && isliving(user)]|[log ? TRUE : FALSE]"
#endif
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

/**
 * Calls a holder proc ref with the arguments in `with` (the shape of after(owner, delay, PROC_REF, with = ...)): a type proc of
 * `holder` (call(holder, proc_ref)(with...)), or a global proc that takes the holder as its first argument (call(proc_ref)(holder, with...)).
 * Nothing is called, and null returned, when `holder` is gone. The proc is a PROC_REF()/TYPE_PROC_REF()/GLOBAL_PROC_REF() (or one stored
 * from them), never a string literal. Capability handlers, name procs and
 * predicates are global procs of that form rather than procs on /atom: BYOND gives every type a slot for every
 * proc it inherits, so a proc declared on /atom costs each of the ~22k atom types memory (about 0.55 MB a proc),
 * while a global proc costs one entry. dispatch_call() passes a global handler the holder as `holder`.
 */
/proc/holder_call(datum/holder, proc_ref, list/with = null)
	if(QDELETED(holder))
		return null
	if(IS_GLOBAL_PROC_REF(proc_ref))
		var/list/call_args = list(holder)
		if(with)
			call_args += with
		return call(proc_ref)(arglist(call_args))
	return call(holder, proc_ref)(arglist(with || list()))
