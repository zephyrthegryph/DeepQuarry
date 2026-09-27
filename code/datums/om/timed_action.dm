// Object-model core: timed actions, the task that replaced do_after (object_model_core.md §4.11).
//
// om_do_after(user, delay, target, callee, on_done, done_args, ...) starts `user` working on
// `target` and returns at once. Nothing sleeps and nothing polls: the task completes by its
// deadline, and is cancelled on the change channels that can break it:
//   - the user moves (CHANGE_MOB_LOC)                          unless IGNORE_USER_LOC_CHANGE
//   - the user's active hand changes (CHANGE_MOB_HANDS)        unless IGNORE_HELD_ITEM
//   - the user is knocked out or stunned (STAT, STATUS)        unless IGNORE_INCAPACITATED
//   - the target moves (MOB_LOC / ITEM_LOC / EXPLICIT)         unless IGNORE_TARGET_LOC_CHANGE
//   - the target is deleted (the task_on / claim relation)
//   - the user leaves max_distance, or changes the aimed zone (target_zone)
//   - `check_proc` (was extra_checks) returns FALSE, re-checked on the same wakes and at the end
// On completion `on_done` runs as call(callee, on_done)(done_args...) (a /proc/ path is called
// globally); on cancel `on_fail` the same way. The callee and every datum argument are held as
// OM handles: if any is gone when the task ends, on_done is dropped; on_fail still runs (while
// the callee exists) with null for the gone arguments, so cleanup always happens.
// The user sees a progress bar that the client animates (no per-tick updates) and others a cog.

/// Re-check channels for a timed action: everything that can break one, on the user or the target.
#define TIMED_ACTION_CHANNELS (CHANGE_MOB_LOC | CHANGE_MOB_HANDS | CHANGE_MOB_STAT | CHANGE_MOB_STATUS | CHANGE_MOB_TARGETING | CHANGE_ITEM_LOC | CHANGE_EXPLICIT)

#ifdef UNIT_TESTS
/// Unit tests that drive gameplay procs synchronously set this: every timed action completes at once.
GLOBAL_VAR_INIT(timed_actions_instant, FALSE)
#endif

/datum/om/task_def/timed_action
	name = "timed_action"
	task_type = /datum/om/task/timed
	interrupt_on = TIMED_ACTION_CHANNELS

/datum/om/task/timed
	/// IGNORE_* flags.
	var/flags = NONE
	/// Handles (never references) of what was where when it started.
	var/user_loc_h
	var/target_loc_h
	var/holding_h
	var/max_distance
	var/target_zone
	var/callee_h
	var/done_proc
	var/list/done_args
	var/list/done_pos
	var/fail_proc
	var/list/fail_args
	var/list/fail_pos
	var/check_proc
	var/list/check_args
	var/list/check_pos
	/// Key into the user's do_afters counts.
	var/interaction_key
	var/datum/progressbar/progbar
	var/datum/cogbar/cog

/datum/om/task/timed/declared_owned_vars()
	return list("progbar", "cog")

/// Captures datum arguments as handles. Returns list(captured, positions), or null if one is gone.
/proc/om_capture_args(list/call_args)
	var/list/captured = call_args ? call_args.Copy() : null
	var/list/positions = null
	for(var/i in 1 to length(captured))
		var/datum/D = captured[i]
		if(!isdatum(D))
			continue
		var/h = om_handle(D)
		if(isnull(h))
			return null
		captured[i] = h
		LAZYADD(positions, i)
	return list(captured, positions)

/// Calls a captured proc: FALSE if the callee or an argument is gone, else the proc's result
/// (TRUE for a null result). `nulls_for_gone`: a gone argument is passed as null instead
/// (cleanup that must run).
/proc/om_call_captured(callee_h, proc_ref, list/captured, list/positions, nulls_for_gone = FALSE)
	if(!proc_ref)
		return TRUE
	var/list/call_args = captured ? captured.Copy() : list()
	if(nulls_for_gone)
		for(var/i in positions)
			call_args[i] = om_resolve(call_args[i])
	else if(!om_resolve_captured(call_args, positions))
		return FALSE
	if(copytext("[proc_ref]", 1, 7) == "/proc/")
		. = call(proc_ref)(arglist(call_args))
		return isnull(.) ? TRUE : .
	var/datum/target_datum = om_resolve(callee_h)
	if(!target_datum)
		return FALSE
	. = call(target_datum, proc_ref)(arglist(call_args))
	return isnull(.) ? TRUE : .

/**
 * Starts a timed action: `user` works on `target` (the progress bar sits there) for `delay`
 * deciseconds, then `on_done` runs on `callee` with `done_args`. Returns the task, or a text
 * reason it did not start (on_fail does not run then). A delay of 0 runs on_done at once.
 *
 * timed_action_flags: IGNORE_* (flags.dm). check_proc: called like on_done with check_args;
 * FALSE cancels. interaction_key / max_interact_count: at most that many running actions per
 * key (default: the target). max_distance: cancelled beyond it. target_zone: cancelled when the
 * user aims elsewhere. claims: the target is exclusive (a second action on it is refused).
 */
/proc/om_do_after(mob/user, delay, atom/target, datum/receiver, on_done, list/done_args, timed_action_flags = NONE, on_fail, list/fail_args, check_proc, list/check_args, progress = TRUE, interaction_key, max_interact_count = 1, hidden = FALSE, icon = 'icons/effects/progressbar.dmi', iconstate = "cog", target_zone, max_distance, claims = FALSE)
	if(!istype(user) || QDELETED(user))
		return "gone"
	if(!isnum(delay))
		CRASH("om_do_after was passed a non-number delay: [delay || "null"].")
#ifdef UNIT_TESTS
	if(GLOB.timed_actions_instant)
		delay = 0
#endif
	if(target && !isatom(target))
		CRASH("om_do_after was given a non-atom target! [target]")
	var/list/done = om_capture_args(done_args)
	var/list/fail = om_capture_args(fail_args)
	var/list/check = om_capture_args(check_args)
	var/callee_h = receiver ? om_handle(receiver) : null
	if((done_args && !done) || (fail_args && !fail) || (check_args && !check) || (receiver && !callee_h))
		return "gone"
	if(delay <= 0)
		if(check_proc && !om_call_captured(callee_h, check_proc, check[1], check[2]))
			om_call_captured(callee_h, on_fail, fail?[1], fail?[2], TRUE)
			return "interrupted"
		om_call_captured(callee_h, on_done, done?[1], done?[2])
		return null

	if(!interaction_key && target)
		interaction_key = "\ref[target]"
	if(interaction_key)
		var/count = LAZYACCESS(user.do_afters, interaction_key) || 0
		if(count >= max_interact_count)
			return "busy"

	var/def = claims ? /datum/om/task_def/timed_action/claiming : /datum/om/task_def/timed_action
	var/list/params = list("duration" = delay)
	var/datum/om/task/timed/T = om_task_start(user, def, (target && target != user) ? target : null, params)
	if(!istype(T))
		return T
	T.flags = timed_action_flags
	T.user_loc_h = om_handle(user.loc)
	T.target_loc_h = target ? om_handle(target.loc) : null
	T.holding_h = om_handle(user.get_active_hand())
	T.max_distance = max_distance
	T.target_zone = target_zone
	T.callee_h = callee_h
	T.done_proc = on_done
	T.done_args = done?[1]
	T.done_pos = done?[2]
	T.fail_proc = on_fail
	T.fail_args = fail?[1]
	T.fail_pos = fail?[2]
	T.check_proc = check_proc
	T.check_args = check?[1]
	T.check_pos = check?[2]
	T.interaction_key = interaction_key
	if(interaction_key)
		LAZYSET(user.do_afters, interaction_key, (LAZYACCESS(user.do_afters, interaction_key) || 0) + 1)
	if(progress)
		if(user.client)
			T.progbar = new(user, delay, target || user)
			T.progbar.animate_fill(delay)
		if(!hidden && delay >= 1 SECONDS)
			T.cog = new(user, icon, iconstate)
	SEND_SIGNAL(user, COMSIG_DO_AFTER_BEGAN)
	return T

/datum/om/task_def/timed_action/why_not_running(datum/om/task/timed/T)
	var/mob/user = T.actor
	var/atom/target = T.target
	var/flags = T.flags
	if(!(flags & IGNORE_USER_LOC_CHANGE) && om_handle(user.loc) != T.user_loc_h)
		return "moved"
	if(!(flags & IGNORE_HELD_ITEM) && om_handle(user.get_active_hand()) != T.holding_h)
		return "hands changed"
	if(!(flags & IGNORE_INCAPACITATED) && user.incapacitated(INCAPACITATION_STUNNED | INCAPACITATION_KNOCKOUT))
		return "incapacitated"
	if(target)
		if(!(flags & IGNORE_TARGET_LOC_CHANGE) && om_handle(target.loc) != T.target_loc_h)
			return "target moved"
		if(T.max_distance && get_dist(user, target) > T.max_distance)
			return "too far away"
	if(T.target_zone && user.zone_sel?.selecting != T.target_zone)
		return "aim changed"
	if(T.check_proc && !om_call_captured(T.callee_h, T.check_proc, T.check_args, T.check_pos))
		return "interrupted"
	return null

/datum/om/task_def/timed_action/on_complete(datum/om/task/timed/T)
	// The last change may have arrived in the same tick as the deadline.
	var/reason = why_not_running(T)
	timed_action_end(T, isnull(reason))
	if(!isnull(reason))
		T.state = OM_TASK_CANCELLED
		T.reason = reason
		om_call_captured(T.callee_h, T.fail_proc, T.fail_args, T.fail_pos, TRUE)
		return
	om_call_captured(T.callee_h, T.done_proc, T.done_args, T.done_pos)

/datum/om/task_def/timed_action/on_cancel(datum/om/task/timed/T, reason)
	timed_action_end(T, FALSE)
	om_call_captured(T.callee_h, T.fail_proc, T.fail_args, T.fail_pos, TRUE)

/datum/om/task_def/timed_action/proc/timed_action_end(datum/om/task/timed/T, success)
	if(!QDELETED(T.progbar))
		T.progbar.end_progress(success)
	T.progbar = null
	T.cog?.remove()
	T.cog = null
	var/mob/user = T.actor
	if(!istype(user))
		return
	if(T.interaction_key)
		var/left = (LAZYACCESS(user.do_afters, T.interaction_key) || 0) - 1
		if(left > 0)
			LAZYSET(user.do_afters, T.interaction_key, left)
		else
			LAZYREMOVE(user.do_afters, T.interaction_key)
	SEND_SIGNAL(user, COMSIG_DO_AFTER_ENDED)

/// The same, claiming its target: one timed action per target at a time.
/datum/om/task_def/timed_action/claiming
	name = "timed_action_claiming"
	claims = TRUE

/// Calls `proc_ref` on `receiver` with `call_args` (a /proc/ path is called globally). No-op without a proc.
/proc/om_call_ref(datum/receiver, proc_ref, list/call_args)
	if(!proc_ref)
		return
	if(copytext("[proc_ref]", 1, 7) == "/proc/")
		return call(proc_ref)(arglist(call_args || list()))
	if(!receiver)
		return
	return call(receiver, proc_ref)(arglist(call_args || list()))

/// A timed action's check_proc for a legacy /datum/callback extra check.
/proc/om_check_callback(datum/callback/C)
	return C.Invoke()

/// Running timed actions of `user` (on `target`, when given).
/proc/om_timed_actions(mob/user, atom/target)
	. = list()
	for(var/datum/om/task/timed/T in user?.om_rec?.tasks)
		if(T.state == OM_TASK_RUNNING && (!target || T.target == target))
			. += T

/// Cancels `user`'s timed actions (on `target`, when given). Returns how many.
/proc/om_cancel_timed_actions(mob/user, atom/target, reason = "cancelled")
	. = 0
	for(var/datum/om/task/timed/T as anything in om_timed_actions(user, target))
		if(om_task_cancel(T, reason))
			.++

#undef TIMED_ACTION_CHANNELS

// ---------------------------------------------------------------- staggered work

/**
 * Runs `proc_ref` over `items` a few at a time (was a loop with sleep() between items):
 * `per_step` items now, then the next batch every `delay` deciseconds on E's clock. A type
 * proc is called on E as (item, extra...); a /proc/ path as (E, item, extra...). Deleted items
 * are skipped, and the rest is dropped if E is deleted. `on_end` (called like proc_ref, with no
 * item) runs after the last batch.
 */
/proc/om_stagger(datum/E, list/items, delay, proc_ref, per_step = 1, list/extra, on_end)
	om_stagger_step(E, items ? items.Copy() : list(), 1, delay, proc_ref, per_step, extra, on_end)

/proc/om_stagger_step(datum/E, list/items, index, delay, proc_ref, per_step, list/extra, on_end)
	var/last = min(index + max(per_step, 1) - 1, length(items))
	var/global_proc = copytext("[proc_ref]", 1, 7) == "/proc/"
	for(var/i in index to last)
		var/datum/D = items[i]
		if(isdatum(D) && QDELETED(D))
			continue
		try
			if(global_proc)
				call(proc_ref)(arglist(list(E, D) + (extra || list())))
			else
				call(E, proc_ref)(arglist(list(D) + (extra || list())))
		catch(var/exception/e)
			stack_trace("om_stagger [proc_ref] on [E]: [e]")
	if(last < length(items))
		om_after(E, delay, /proc/om_stagger_step, E, items, last + 1, delay, proc_ref, per_step, extra, on_end)
	else if(on_end)
		if(copytext("[on_end]", 1, 7) == "/proc/")
			call(on_end)(arglist(list(E) + (extra || list())))
		else
			call(E, on_end)(arglist(extra || list()))

/// Deletes the datum: om_after(src, delay, TYPE_PROC_REF(/datum, om_delete_self)).
/datum/proc/om_delete_self()
	qdel(src)
