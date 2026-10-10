// Declared lifetimes (doc/rewrite/final_api.html section 6 "Lifecycle forms", form 8): owned, scoped and caused endings.
//
// Owned. owns_one/owns_many and their on_destroy = work on a plain datum as on an atom: a non-atom whose CAPABILITIES block declares a form or
// a starts = runs it from New() (analyze gen declare sets its lifeform_declared flag), and the destroy transaction disposes of what it owns.
//
// Scoped. lives_while(scope, watches =) ends the holder when its scope ends:
//
//	CAPABILITIES(/datum/tgui_module/crew_monitor)
//		lives_while(nameof(host))                                    // a window lives while its host does
//	CAPABILITIES(/datum/fusion_request)
//		lives_while(PROC_REF(still_wanted), watches = list(nameof(answered), nameof(deadline_passed)))
//	CAPABILITIES(/obj/effect/overlay/aiming)
//		lives_while(nameof(active))                                  // a condition (a truthy var)
//		on_ending(PROC_REF(stop_aiming))
//
// A scope is nameof(var) of a var holding a datum (the holder ends when that datum ends or the var stops naming a live one), nameof(var) of a
// truthy var, or a condition (PROC_REF(x), cond_not/all/any) re-checked when a var in `watches` is written. Each var it reads must publish
// its writes (TRACKED, or a setter calling tracked_changed()). The ending's cause is END_SCOPE, or END_OWNER when the scope datum ended.
//
// on_ending(PROC_REF(x)) runs x(cause, by) when the holder ends, however it ends, before the destroy transaction tears anything down.
//
// Caused endings. Content ends a thing through a verb that says why, never through qdel():
//
//	spent(item, by)               used up (a charge, a single-use tool, an empty pack)
//	consumed(item, by)            eaten, drunk, absorbed by `by`
//	destroyed(thing, by, cause)   broken, burnt, blown up (cause: a damage type or a short text)
//	dissolved(thing, by)          melted, dissolved, digested, washed away or decayed into nothing
//	lapsed(thing, by)             its time ran out (a duration, a history window, an animation): the immediate form of expire()
//	replaced_by(thing, successor) superseded by `successor` (a transformation, an evolution, a rebuilt part) that the caller already made;
//	                              replace_with() when the caller wants the successor made and slotted for it
//	ended_with(thing, owner)      ended because its owner or host is ending or gone (a teardown of what an owner held)
//	expire(after) · replace_with(path, ...) · consume(item, actor) · slot_clear(slot)   (kept, code/datums/lifecycle/verbs.dm)
//
// Every ending publishes /datum/notice/ended on the thing, with its cause and who caused it (when anything listens: on_notice(/datum/notice/ended)
// or observe()), and runs the thing's on_ending() hooks. qdel() is the engine's: the qdel lint hard-bans it in content once its count reaches 0
// (tools/analyze/src/lints/lifecycle_counts.rs; code/engine, code/library and code/datums/lifecycle are the engine).

/proc/lives_while(scope, watches = null)
	if(isnull(scope))
		declare_report("lives_while(): needs a scope")
		return null
	var/list/from = list()
	if(istext(scope))
		from += scope
	for(var/read in (islist(watches) ? watches : (isnull(watches) ? list() : list(watches))))
		from |= read
	return entry_make(ENTRY_LIVES_WHILE, istext(scope) ? "lives_while:[scope]" : null, list("scope" = scope, "from" = from))

/proc/on_ending(handler)
	return entry_make(ENTRY_ON_ENDING, null, list("handler" = handler))

/// The ended notice: the thing's cause (END_*) and the entity that caused it, if any.
/datum/notice/ended
	var/cause
	var/datum/by
	/// What destroyed() named as the cause (a damage type, "explosion"), or null.
	var/detail

/datum/notice/ended/fill(cause, datum/by, detail = null)
	src.cause = cause
	src.by = by // ALLOW(ownership): a pooled notice holds its entities for one delivery and is reset on release
	src.detail = detail

/// thing -> list(cause, by), set by a caused ending right before it calls qdel(), read once by ending_begin(). A real global: datums end
/// while the globals are still being made, and ending_begin() runs for every one.
GLOBAL_REAL_VAR(list/ending_causes)
/// scope datum -> the holders living while it does (lives_while(nameof(var)) of a var naming it).
GLOBAL_LIST_EMPTY(lives_in)
/// holder -> (var name -> the scope datum that var names).
GLOBAL_LIST_EMPTY(lives_scope_of)

/datum/var/tmp/lifeform_scoped = FALSE

// ---- the verbs ----

/// Records why `thing` is ending: what its ended notice and on_ending() hooks will say. The engine verbs call it before qdel().
/proc/ending_cause(datum/thing, cause, datum/by = null)
	if(!thing || QDELETED(thing))
		return
	if(!ending_causes)
		ending_causes = list()
	ending_causes[thing] = list(cause, by)

/// Ends `thing` with `cause`. The one place a caused ending deletes: returns TRUE when it ended it.
/proc/lifeform_end(datum/thing, cause, datum/by = null, force = FALSE)
	if(isnull(thing))
		return FALSE
	if(!isdatum(thing)) // an image, an icon: nothing to announce, qdel() hard-deletes it as before
		qdel(thing)
		return TRUE
	if(QDELETED(thing))
		return FALSE
	ending_cause(thing, cause, by)
	qdel(thing, force)
	return TRUE

/// Used up: a charge, a single-use tool, a spent cartridge. `force` is qdel()'s: a thing that refuses deletion (a lighting object) ends anyway.
/proc/spent(datum/thing, datum/by = null, force = FALSE)
	return lifeform_end(thing, END_SPENT, by, force)

/// Eaten, drunk or absorbed by `by`.
/proc/consumed(datum/thing, datum/by = null)
	return lifeform_end(thing, END_CONSUMED, by)

/// Broken, burnt or blown up; `cause` is what did it (a damage type, "explosion", "emp").
/proc/destroyed(datum/thing, datum/by = null, cause = null)
	if(isnull(thing))
		return FALSE
	if(!isdatum(thing))
		qdel(thing)
		return TRUE
	if(QDELETED(thing))
		return FALSE
	ending_cause(thing, END_DESTROYED, by)
	if(cause)
		ending_causes[thing] += cause
	qdel(thing)
	return TRUE

/// Melted, dissolved or decayed into nothing.
/proc/dissolved(datum/thing, datum/by = null)
	return lifeform_end(thing, END_DISSOLVED, by)

/// Its time ran out: a duration, a capped history, a one-shot animation. expire(after) arms the same ending for later.
/proc/lapsed(datum/thing, datum/by = null)
	return lifeform_end(thing, END_EXPIRED, by)

/// Superseded by `successor`, which the caller already made (a transformed mob, an evolved form, a rebuilt part). Only the cause is recorded:
/// replace_with() is the verb that also builds the successor and hands it the original's slot.
/proc/replaced_by(datum/thing, datum/successor = null)
	return lifeform_end(thing, END_REPLACED, successor)

/// Ended because `owner` is ending or has gone: the teardown of what an owner held, done by hand where no owns_one/lives_while declares it.
/proc/ended_with(datum/thing, datum/owner = null)
	return lifeform_end(thing, END_OWNER, owner)

// ---- the ending ----

/// The destroy transaction's first step (DESTROY_STEP_GUARD, code/datums/lifecycle/transaction.dm): the thing's on_ending() hooks run, the
/// things living in its scope end, and its ended notice is published, with the cause its verb recorded (END_ENGINE when none did).
/proc/ending_begin(datum/thing)
	var/list/why = ending_causes?[thing]
	if(why)
		ending_causes -= thing
	var/cause = why ? why[1] : END_ENGINE
	var/datum/by = why ? why[2] : null
	var/datum/type_table/T = type_table_cache()[thing.type]
	if(T && (T.hook_flags & ENGINE_HOOK_LIFEFORMS))
		var/datum/lifeform_plan/P = lifeform_plan_of(thing)
		for(var/datum/centry/C as anything in P.on_ending)
			var/datum/entry/E = C.item
			try
				call(thing, E.args["handler"])(cause, by)
			catch(var/exception/e)
				stack_trace("on_ending() of [thing.type]: [e] ([e.file]:[e.line])")
	if(thing.lifeform_scoped)
		lives_in_scope_ended(thing)
	// Something can listen only when the thing has reaction state (an observer) or its type a compiled table (an on_notice hook).
	if((thing.rx || type_table_cache()[thing.type]) && notice_wanted(thing, /datum/notice/ended))
		var/datum/notice/ended/N = notice_take(/datum/notice/ended)
		N.fill(cause, by, length(why) > 2 ? why[3] : null)
		notice_publish(thing, N)

/// The ended notice was already announced by ending_begin(); lifeform_destroy() calls this for the forms' own teardown only.
/proc/ending_announce(datum/holder, datum/lifeform_plan/P)
	GLOB.roll_rollers -= holder
	if(param_given)
		param_given -= holder
	if(param_drop_pending)
		param_drop_pending -= holder
	if(init_discard_pending)
		init_discard_pending -= holder

// ---- scopes ----

/proc/lives_while_init(datum/holder, datum/lifeform_plan/P)
	for(var/datum/centry/C as anything in P.lives_while)
		if(!lives_while_check(holder, C))
			return

/// Re-checks one scope: binds the holder to the scope datum a var names, and ends the holder when the scope is over. FALSE when it ended.
/proc/lives_while_check(datum/holder, datum/centry/C)
	if(QDELETED(holder))
		return FALSE
	var/datum/entry/E = C.item
	var/scope = E.args["scope"]
	var/alive = TRUE
	var/datum/scope_datum = null
	if(istext(scope) && (scope in holder.vars))
		var/value = holder.vars[scope]
		if(isdatum(value))
			scope_datum = value
			alive = !QDELETED(scope_datum)
		else
			alive = !!value
		lives_while_bind(holder, scope, scope_datum)
	else
		alive = !!condition_holds(holder, scope)
	if(alive)
		return TRUE
	lifeform_end(holder, scope_datum ? END_OWNER : END_SCOPE, scope_datum)
	return FALSE

/// `holder` lives in the scope of `scope_datum`, which its var `var_name` names (null: that var names none now).
/proc/lives_while_bind(datum/holder, var_name, datum/scope_datum)
	var/list/bound = GLOB.lives_scope_of[holder]
	var/datum/old = bound?[var_name]
	if(old == scope_datum)
		return
	if(old)
		bound -= var_name
		if(!(old in bound.Copy()))
			lives_in_drop(old, holder)
		if(!length(bound))
			GLOB.lives_scope_of -= holder
	if(!scope_datum || QDELETED(scope_datum))
		return
	if(!bound)
		bound = list()
		GLOB.lives_scope_of[holder] = bound
	bound[var_name] = scope_datum
	LAZYINITLIST(GLOB.lives_in[scope_datum])
	GLOB.lives_in[scope_datum] |= holder
	scope_datum.lifeform_scoped = TRUE

/proc/lives_in_drop(datum/scope_datum, datum/holder)
	var/list/living = GLOB.lives_in[scope_datum]
	if(!living)
		return
	living -= holder
	if(!length(living))
		GLOB.lives_in -= scope_datum
		scope_datum.lifeform_scoped = FALSE

/// A scope datum is ending: everything living in its scope ends with it.
/proc/lives_in_scope_ended(datum/scope_datum)
	var/list/living = GLOB.lives_in[scope_datum]
	GLOB.lives_in -= scope_datum
	scope_datum.lifeform_scoped = FALSE
	for(var/datum/holder as anything in living)
		GLOB.lives_scope_of -= holder
		if(!QDELETED(holder))
			lifeform_end(holder, END_OWNER, scope_datum)

/proc/lives_while_teardown(datum/holder)
	var/list/bound = GLOB.lives_scope_of[holder]
	GLOB.lives_scope_of -= holder
	for(var/var_name in bound)
		lives_in_drop(bound[var_name], holder)
