// modes(nameof(var)): exclusive state capabilities (doc/rewrite/final_api.html, section 11 "Modes"; doc/rewrite/ai_packs.md A2).
//
//	CAPABILITIES(/obj/machinery/thing)
//		modes(nameof(mode))                                  // `mode` is a TRACKED var holding a capability type
//	TRACKED(/obj/machinery/thing, mode)
//
//	CAPABILITY_TYPE(thing_working, CAP_THING_WORKING, /datum/capability/thing_working, key = NONE)
//	/datum/capability/thing_working/entries()
//		return list(
//			every(2 SECONDS, then(CAP_PROC(work))),
//			on_notice(/datum/notice/jammed, then(CAP_PROC(jammed))),
//			after_in_state(5 MINUTES, go(/datum/capability/thing_idle)))
//
// The mode var holds the type of the capability that is active. The engine grants it to the holder with the holder as the source and revokes the
// previous one when the var changes, then publishes /datum/notice/mode_changed (old_mode, new_mode, mode_var) on the holder. A state is an ordinary
// capability: its every(), on_notice(), on_change(), coalesce() and contributes() entries live exactly while it is the mode, by the one teardown
// path, and its transitions are declared in the state that owns them.
//
// - go(/datum/capability/x): a part. Sets the mode now (through the var's setter, so on_change and the notice both see it) and the previous state
//   ends at once: the handler that ran go() finishes, nothing of its state runs again, and the parts after go() in that entry do not run.
//   `go(type, var = nameof(v))` names the var when the holder has several modes(); inside a state it defaults to the var the state is the mode of.
// - after_in_state(delay, parts...): a timer the state owns. It is armed when the state starts and cancelled when the state ends, whatever ended it.
//   `delay` is deciseconds of the holder's clock, or a PROC_REF answering them.
// - A write of the var by its setter (not through go()) is picked up at the next drain point and follows the same path.
//
// A var that holds anything but a capability type (or null: no mode) is rejected: go() and modes() check at declaration, and a bad value of the var
// is reported and put back. Transitions inside one sync run one after the other (a state's activation that goes on to another state), at most
// MODES_MAX_CHAIN deep. GLOB.forms_trace logs every transition.

/// modes(nameof(var)): the declaration.
/proc/modes(var_name)
	if(!istext(var_name) || !length(var_name))
		declare_report("modes(): the argument is nameof(var), the TRACKED var that holds the capability type, got [isnull(var_name) ? "null" : "[var_name]"]")
		return null
	return entry_make(ENTRY_MODES, null, list("var" = var_name))

/// go(/datum/capability/x, var = null): the part that sets the mode.
/proc/go(mode_type, var_name = null)
	if(!modes_valid_type(mode_type))
		declare_report("go(): [isnull(mode_type) ? "null" : "[mode_type]"] is not a declared capability type (a CAPABILITY_TYPE / CAPABILITY_DEF capability)")
		return null
	return entry_make(ENTRY_GO, null, list("mode" = mode_type, "var" = var_name))

/// after_in_state(delay, parts...): the state-owned timer.
/proc/after_in_state(delay, p1, p2, p3, p4)
	if(!(istext(delay) && length(delay)) && (!isnum(delay) || delay <= 0))
		declare_report("after_in_state(): the delay must be a positive number of deciseconds or a PROC_REF, got [isnull(delay) ? "null" : "[delay]"]")
		return null
	return entry_make(ENTRY_AFTER_IN_STATE, null, list("interval" = delay), entry_flatten(list(p1, p2, p3, p4)))

/// TRUE when `mode_type` is a capability type a mode can be: a /datum/capability path that a CAPABILITY_TYPE or CAPABILITY_DEF declared.
/proc/modes_valid_type(mode_type)
	if(!ispath(mode_type, /datum/capability))
		return FALSE
	if(!islist(GLOB?.capability_infos))
		return TRUE // the globals are still being built: the transition checks again
	return !!capability_info_of_type(mode_type)

/datum/rx_state
	/// modes() var name -> the capability type the engine has granted for it now.
	var/list/modes
	/// The modes() vars with a sync running: a nested write waits for the running one to finish its transition.
	var/list/modes_busy

/// The modes() vars a holder's type declares.
/proc/modes_vars(datum/holder)
	. = list()
	for(var/datum/centry/C as anything in compiled_entries(table_of(holder), ENTRY_MODES))
		var/datum/entry/E = C.item
		. |= E.args["var"]

/// The mode capability the holder has now for `var_name`, or null.
/proc/mode_now(datum/holder, var_name)
	return holder?.rx?.modes?[var_name]

/// Checks the modes() and after_in_state() entries of a compiled table (called by table_validate).
/proc/modes_validate_table(datum/type_table/T)
	for(var/datum/centry/C as anything in T.items)
		var/datum/entry/E = C.item
		if(!istype(E))
			continue
		if(E.kind == ENTRY_AFTER_IN_STATE && isnull(C.owner))
			table_error(T, C.origin, declare_rule("modes"), "after_in_state() sits in the type's own list", "it is an entry of a state capability: its timer belongs to the state")
		else if(E.kind == ENTRY_GO && isnull(C.owner))
			table_error(T, C.origin, declare_rule("modes"), "go() sits directly in the type's own list", "go() is a part: put it inside on_notice(), on_change(), every() or after_in_state()")

// ---- the hook that follows the var ----

/// The on_change hook a type-level modes(var) makes: a write of the var marks it, and at the drain the mode follows.
/proc/modes_watch_entry(datum/entry/E)
	var/static/list/made = list()
	var/datum/entry/known = made[E.sig]
	if(!known)
		known = entry_make(ENTRY_ON_CHANGE, null, list("cond" = E.args["var"], "edge" = ANY), list(then(GLOBAL_PROC_REF(modes_changed_hook))))
		made[E.sig] = known
	return known

/proc/modes_changed_hook(datum/act/A)
	var/datum/holder = A.holder
	if(!holder || QDELETED(holder))
		return
	for(var/var_name in modes_vars(holder))
		modes_sync(holder, var_name)

/// The holder initializes: the capability its var names starts as the mode.
/proc/modes_init(datum/holder, datum/type_table/T)
	for(var/datum/centry/C as anything in compiled_entries(T, ENTRY_MODES))
		var/datum/entry/E = C.item
		var/var_name = E.args["var"]
		if(!(var_name in holder.vars))
			declare_report("modes([var_name]) on [holder.type]: the type has no such var")
			continue
		if(!hascall(holder, "set_[var_name]"))
			declare_report("modes([var_name]) on [holder.type]: the var is not TRACKED (no set_[var_name]()), so a write of it could not be seen")
			continue
		modes_sync(holder, var_name)

// ---- the transition ----

/// Makes the granted mode follow the var: revokes what was granted, grants what the var names, publishes mode_changed. TRUE when it changed.
/proc/modes_sync(datum/holder, var_name)
	if(!holder || QDELETED(holder))
		return FALSE
	var/datum/rx_state/rx = rx_of(holder)
	if(var_name in rx.modes_busy)
		return FALSE // the transition running now re-reads the var when it ends
	LAZYADD(rx.modes_busy, var_name)
	. = FALSE
	var/links = 0
	while(!QDELETED(holder))
		var/want = holder.vars[var_name]
		var/have = rx.modes?[var_name]
		if(want == have)
			break
		if(++links > MODES_MAX_CHAIN)
			log_world("MODES: [holder.type] [var_name] went through [MODES_MAX_CHAIN] transitions in one sync (a state keeps handing over to another); stopped at [have] -> [want]")
			break
		if(!isnull(want) && !modes_valid_type(want))
			declare_report("modes([var_name]) on [holder.type]: [want] is not a declared capability type; the mode stays [isnull(have) ? "null" : "[have]"]")
			call(holder, "set_[var_name]")(have)
			break
		modes_transition(holder, rx, var_name, have, want)
		. = TRUE
	LAZYREMOVE(rx.modes_busy, var_name)
	if(!length(rx.modes_busy))
		rx.modes_busy = null

/proc/modes_transition(datum/holder, datum/rx_state/rx, var_name, have, want)
	forms_trace("mode", "[holder.type] [var_name]: [isnull(have) ? "(none)" : "[have]"] -> [isnull(want) ? "(none)" : "[want]"]")
	if(have)
		revoke(holder, have, holder)
	if(want)
		LAZYSET(rx.modes, var_name, want)
	else
		LAZYREMOVE(rx.modes, var_name)
		if(!length(rx.modes))
			rx.modes = null
	if(want)
		grant(holder, want, holder)
	PUBLISH(holder, mode_change, have, want, var_name)

/// Sets the mode of `var_name` on holder to `mode_type` now. TRUE when it changed.
/proc/mode_enter(datum/holder, var_name, mode_type)
	if(!holder || QDELETED(holder))
		return FALSE
	if(!isnull(mode_type) && !modes_valid_type(mode_type))
		declare_report("mode_enter([holder.type], [var_name]): [mode_type] is not a declared capability type")
		return FALSE
	if(!hascall(holder, "set_[var_name]"))
		declare_report("mode_enter([holder.type], [var_name]): the var is not TRACKED (no set_[var_name]())")
		return FALSE
	call(holder, "set_[var_name]")(mode_type)
	return modes_sync(holder, var_name)

/// The go() part running: resolves which modes() var it sets, then sets it.
/proc/modes_go(datum/act/A, datum/entry/part)
	var/datum/holder = A.holder
	if(!holder || QDELETED(holder))
		return
	var/var_name = part.args["var"]
	if(isnull(var_name))
		var_name = modes_var_for(holder, A.activation)
	if(isnull(var_name))
		declare_report("go([part.args["mode"]]) on [holder.type]: no modes() var to set (name it with var =, or run it inside a state)")
		return
	mode_enter(holder, var_name, part.args["mode"])

/// The modes() var `state` (a state's activation) is the mode of, else the holder's only modes() var, else null.
/proc/modes_var_for(datum/holder, datum/activation/state)
	var/list/vars_of = modes_vars(holder)
	if(state && !QDELETED(holder))
		for(var/var_name in vars_of)
			if(mode_now(holder, var_name) == state.def.type)
				return var_name
	if(length(vars_of) == 1)
		return vars_of[1]
	return null

// ---- after_in_state ----

/datum/entry_engine/after_in_state
	kind = ENTRY_AFTER_IN_STATE

/datum/entry_engine/after_in_state/validate(datum/activation/A, datum/entry/E)
	if(!length(E.children))
		return "after_in_state() has no parts: give it go(/datum/capability/x) or then(CAP_PROC(x))"
	return null

/datum/entry_engine/after_in_state/apply(datum/activation/A, datum/entry/E, datum/centry/C)
	var/datum/holder = A.holder
	if(!holder || QDELETED(holder) || A.dead)
		return FALSE
	after(holder, every_interval(holder, E, A), GLOBAL_PROC_REF(state_after_fire), key = state_after_key(A, E), with = list(A, E))
	return TRUE

/datum/entry_engine/after_in_state/remove(datum/activation/A, datum/entry/E)
	var/datum/holder = A.holder
	if(holder && !QDELETED(holder))
		cancel_after(holder, state_after_key(A, E))
		forms_trace("mode", "state-owned timer of [A.def.type] on [holder.type] cancelled with the state")

/proc/state_after_key(datum/activation/A, datum/entry/E)
	return "state_after:[A.serial]:[copytext(md5(E.sig), 1, 9)]"

/// The state-owned timer went off: its parts run unless the state ended (it cannot have: the end cancels it, and this checks anyway).
/proc/state_after_fire(datum/activation/A, datum/entry/E)
	if(!A || !E || A.dead)
		return
	var/datum/holder = A.holder
	if(!holder || QDELETED(holder))
		return
	var/datum/act/timer/T = every_context(holder, A, A.source, isnum(E.args["interval"]) ? E.args["interval"] : 0)
	var/depth = GLOB.act_depth
	try
		hook_run_parts(null, T, E.children)
	catch(var/exception/fault)
		dq_report_caught(fault, "after_in_state() of [A.def.key] on [holder.type]")
	GLOB.act_depth = depth
	T.release()
