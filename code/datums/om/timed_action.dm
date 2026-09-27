// Object-model core: timed actions, the task that replaced do_after (object_model_core.md §11).
//
// A timed action is a task type under /datum/om/task/timed: `actor` works on `target` for its
// duration, with a progress bar the client animates (no per-tick updates) and a cog for
// others. Nothing sleeps and nothing polls: it completes by its deadline and is cancelled on
// the change channels that can break it:
//   - the user moves (CHANGE_MOB_LOC)                          unless IGNORE_USER_LOC_CHANGE
//   - the user's active hand changes (CHANGE_MOB_HANDS)        unless IGNORE_HELD_ITEM
//   - the user is knocked out or stunned (STAT, STATUS)        unless IGNORE_INCAPACITATED
//   - the target moves (MOB_LOC / ITEM_LOC / EXPLICIT)         unless IGNORE_TARGET_LOC_CHANGE
//   - the target, the receiver or any datum in the task's state is deleted
//   - the user leaves max_distance, or changes the aimed zone (target_zone)
//   - `check_proc` (on the receiver, with the task) returns FALSE, re-checked on the same
//     wakes and at the end
// On completion complete_proc runs on the receiver with the task; on cancel, cancel_proc.
//
// Declaring one:
//
//	/datum/om/task/timed/lockpick
//		complete_proc = /obj/item/lockpick/proc/pick_done
//		var/obj/structure/simple_door/door
//
//	om_task_start(/datum/om/task/timed/lockpick, user, src, list("duration" = 5 SECONDS, "receiver" = src, "door" = D))
//
// Every declaration var below (flags, progress, interaction_key, max_distance, busy, ...) can
// be set per run through params. om_do_after() remains for the zero-state case: a proc and at
// most two plain arguments.

/// Re-check channels for a timed action: everything that can break one, on the user or the target.
#define TIMED_ACTION_CHANNELS (CHANGE_MOB_LOC | CHANGE_MOB_HANDS | CHANGE_MOB_STAT | CHANGE_MOB_STATUS | CHANGE_MOB_TARGETING | CHANGE_ITEM_LOC | CHANGE_EXPLICIT)

#ifdef UNIT_TESTS
/// Unit tests that drive gameplay procs synchronously set this: every timed action completes at once.
GLOBAL_VAR_INIT(timed_actions_instant, FALSE)
#endif

/datum/om/task/timed
	abstract_type = /datum/om/task/timed
	interrupt_on = TIMED_ACTION_CHANNELS
	instant_at_zero = TRUE
	/// IGNORE_* flags (flags.dm).
	var/flags = NONE
	/// A proc on the receiver called with the task on every re-check: FALSE cancels.
	var/check_proc
	/// Told to the user when the action is cancelled or fails (before cancel_proc runs).
	var/fail_message
	/// FALSE: no progress bar or cog.
	var/progress = TRUE
	/// TRUE: no cog for onlookers.
	var/hidden = FALSE
	var/icon = 'icons/effects/progressbar.dmi'
	var/iconstate = "cog"
	/// At most max_interact_count running actions per key on the user (default: the target).
	var/interaction_key
	var/max_interact_count = 1
	/// Cancelled beyond this distance from the target.
	var/max_distance
	/// Cancelled when the user aims at another zone.
	var/target_zone
	/// A datum (or list) the action also claims: the bot, tool or machine doing the work. It is
	/// busy (om_busy()) until the action ends; if something already claims it, "busy".
	var/busy

	// ---- run state: handles (never references) of what was where when it started
	var/user_loc_h
	var/target_loc_h
	var/holding_h
	var/captured = FALSE
	var/counted = FALSE
	var/datum/progressbar/progbar
	var/datum/cogbar/cog

/datum/om/task/timed/declared_owned_vars()
	return list("progbar", "cog")

/datum/om/task/timed/on_starting()
	var/mob/user = actor
	if(!istype(user))
		return "gone"
	var/atom/A = target != actor ? target : null // working on yourself has no separate target
	if(A && !isatom(A))
		CRASH("timed action [name] was given a non-atom target! [A]")
	if(!interaction_key && A)
		interaction_key = "\ref[A]"
	if(interaction_key && (LAZYACCESS(user.do_afters, interaction_key) || 0) >= max_interact_count)
		return "busy"
	for(var/datum/D as anything in (islist(busy) ? busy : (busy ? list(busy) : null)))
		if(istext(om_task_claim(src, D)))
			return "busy"
	user_loc_h = om_handle(user.loc)
	target_loc_h = A ? om_handle(A.loc) : null
	holding_h = om_handle(user.get_active_hand())
	captured = TRUE
	if(interaction_key)
		LAZYSET(user.do_afters, interaction_key, (LAZYACCESS(user.do_afters, interaction_key) || 0) + 1)
		counted = TRUE
	return null

/datum/om/task/timed/on_started()
	var/mob/user = actor
	if(progress)
		if(user.client)
			progbar = new(user, duration, target || user)
			progbar.animate_fill(duration)
		if(!hidden && duration >= 1 SECONDS)
			cog = new(user, icon, iconstate)
	SEND_SIGNAL(user, COMSIG_DO_AFTER_BEGAN)

/// A repeating timed action (steps) shows a fresh bar for each step.
/datum/om/task/timed/on_rescheduled(delay)
	var/mob/user = actor
	if(!progress || !istype(user))
		return
	if(!QDELETED(progbar))
		progbar.end_progress(TRUE)
	progbar = null
	if(user.client && delay > 0)
		progbar = new(user, delay, target || user)
		progbar.animate_fill(delay)

/datum/om/task/timed/why_not_running()
	var/mob/user = actor
	var/atom/A = target != actor ? target : null // working on yourself has no separate target
	if(captured)
		if(!(flags & IGNORE_USER_LOC_CHANGE) && om_handle(user.loc) != user_loc_h)
			return "moved"
		if(!(flags & IGNORE_HELD_ITEM) && om_handle(user.get_active_hand()) != holding_h)
			return "hands changed"
		if(!(flags & IGNORE_INCAPACITATED) && user.incapacitated(INCAPACITATION_STUNNED | INCAPACITATION_KNOCKOUT))
			return "incapacitated"
		if(A)
			if(!(flags & IGNORE_TARGET_LOC_CHANGE) && om_handle(A.loc) != target_loc_h)
				return "target moved"
			if(max_distance && get_dist(user, A) > max_distance)
				return "too far away"
		if(target_zone && user.zone_sel?.selecting != target_zone)
			return "aim changed"
	if(!timed_check())
		return "interrupted"
	return null

/datum/om/task/timed/on_complete()
	// The last change may have arrived in the same tick as the deadline (a steps task's last
	// step has already acted, so it isn't second-guessed).
	var/why = spec.compiled_steps ? null : why_not_running()
	timed_action_end(isnull(why))
	if(!isnull(why))
		state = OM_TASK_CANCELLED
		reason = why
		timed_failed()
		return
	timed_done()

/datum/om/task/timed/on_cancel(reason)
	timed_action_end(FALSE)
	timed_failed()

/// The action finished: complete_proc on the receiver.
/datum/om/task/timed/proc/timed_done()
	if(complete_proc)
		om_task_call(src, complete_proc)

/// The action was cancelled or failed its last check: cancel_proc on the receiver.
/datum/om/task/timed/proc/timed_failed()
	if(fail_message)
		to_chat(actor, fail_message)
	if(cancel_proc)
		om_task_call(src, cancel_proc)

/// FALSE cancels the action (check_proc on the receiver).
/datum/om/task/timed/proc/timed_check()
	if(!check_proc)
		return TRUE
	return om_task_call(src, check_proc) != FALSE

/datum/om/task/timed/proc/timed_action_end(success)
	if(!QDELETED(progbar))
		progbar.end_progress(success)
	progbar = null
	cog?.remove()
	cog = null
	var/mob/user = actor
	if(!istype(user))
		return
	if(counted)
		counted = FALSE
		var/left = (LAZYACCESS(user.do_afters, interaction_key) || 0) - 1
		if(left > 0)
			LAZYSET(user.do_afters, interaction_key, left)
		else
			LAZYREMOVE(user.do_afters, interaction_key)
	if(captured)
		SEND_SIGNAL(user, COMSIG_DO_AFTER_ENDED)

// ---------------------------------------------------------------- om_do_after: the zero-state shape

/// om_do_after()'s task: a proc on the receiver with a short argument list.
/datum/om/task/timed/simple
	name = "timed_action"
	var/done_proc
	var/list/done_args
	var/list/done_pos
	var/fail_proc
	var/list/fail_args
	var/list/fail_pos
	var/call_check_proc
	var/list/check_args
	var/list/check_pos

/// The same, claiming its target: one timed action per target at a time.
/datum/om/task/timed/simple/claiming
	name = "timed_action_claiming"
	claims = TRUE

/datum/om/task/timed/simple/timed_done()
	om_call_captured(receiver, done_proc, done_args, done_pos)

/datum/om/task/timed/simple/timed_failed()
	om_call_captured(receiver, fail_proc, fail_args, fail_pos, TRUE)

/datum/om/task/timed/simple/timed_check()
	return !call_check_proc || om_call_captured(receiver, call_check_proc, check_args, check_pos)

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
/proc/om_call_captured(datum/callee, proc_ref, list/captured, list/positions, nulls_for_gone = FALSE)
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
	if(!callee || QDELETED(callee))
		return FALSE
	. = call(callee, proc_ref)(arglist(call_args))
	return isnull(.) ? TRUE : .

/**
 * A timed action with no state of its own: `user` works on `target` for `delay` deciseconds,
 * then `on_done` runs on `receiver` with `done_args`. At most two arguments across done_args,
 * fail_args and check_args: anything more is state, and belongs on a named task type (see the
 * top of this file; tools/ci/api_lints.py counts the rest). Returns the task, null when a zero
 * delay completed at once, or a text reason it did not start (on_fail does not run then).
 *
 * timed_action_flags: IGNORE_* (flags.dm). The named arguments are the timed task's vars.
 */
/proc/om_do_after(mob/user, delay, atom/target, datum/receiver, on_done, list/done_args, timed_action_flags = NONE, on_fail, list/fail_args, check_proc, list/check_args, progress = TRUE, interaction_key, max_interact_count = 1, hidden = FALSE, icon = 'icons/effects/progressbar.dmi', iconstate = "cog", target_zone, max_distance, claims = FALSE, busy)
	if(!istype(user) || QDELETED(user))
		return "gone"
	if(!isnum(delay))
		CRASH("om_do_after was passed a non-number delay: [delay || "null"].")
	var/list/done = om_capture_args(done_args)
	var/list/fail = om_capture_args(fail_args)
	var/list/check = om_capture_args(check_args)
	if((done_args && !done) || (fail_args && !fail) || (check_args && !check))
		return "gone"
	var/list/params = list(
		"duration" = delay,
		"flags" = timed_action_flags,
		"progress" = progress,
		"interaction_key" = interaction_key,
		"max_interact_count" = max_interact_count,
		"hidden" = hidden,
		"icon" = icon,
		"iconstate" = iconstate,
		"target_zone" = target_zone,
		"max_distance" = max_distance,
		"busy" = busy,
		"done_proc" = on_done,
		"done_args" = done?[1],
		"done_pos" = done?[2],
		"fail_proc" = on_fail,
		"fail_args" = fail?[1],
		"fail_pos" = fail?[2],
		"call_check_proc" = check_proc,
		"check_args" = check?[1],
		"check_pos" = check?[2])
	if(receiver)
		params["receiver"] = receiver
	var/datum/om/task/timed/T = om_task_start(claims ? /datum/om/task/timed/simple/claiming : /datum/om/task/timed/simple, user, (target && target != user) ? target : null, params)
	if(istype(T) && T.state == OM_TASK_DONE)
		return null
	return T

/// Calls `proc_ref` on `receiver` with `call_args` (a /proc/ path is called globally). No-op without a proc.
/proc/om_call_ref(datum/receiver, proc_ref, list/call_args)
	if(!proc_ref)
		return
	if(copytext("[proc_ref]", 1, 7) == "/proc/")
		return call(proc_ref)(arglist(call_args || list()))
	if(!receiver)
		return
	return call(receiver, proc_ref)(arglist(call_args || list()))

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
/// Steps `A` `steps` times in `direction`, one step every `delay` deciseconds
/// (the old `for(...) sleep(delay); step(A, dir)` drift). Stops if A is deleted.
/proc/om_drift(atom/movable/A, direction, steps, delay)
	if(steps <= 0 || QDELETED(A))
		return
	om_after(A, delay, /proc/om_drift_step, A, direction, steps, delay)

/proc/om_drift_step(atom/movable/A, direction, steps, delay)
	step(A, direction)
	if(steps > 1)
		om_after(A, delay, /proc/om_drift_step, A, direction, steps - 1, delay)

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

// ---------------------------------------------------------------- lane work

/**
 * Long work as lane work (object_model_core.md §4.11: what a stoplag()/sleep(-1) loop was).
 * `slice_proc`, a proc on E called as (cursor), does one bounded slice and returns the next
 * cursor (lists pass as they are), or null when the work is done. Slices run back to back while the OM scheduler's budget
 * lasts; the rest resumes by its cursor on a later pass, on E's clock. `on_done`, a proc on E or
 * a /datum/callback, runs after the last slice. Before the live scheduler runs (world init), or with `now`, every
 * slice runs at once. Deleting E drops the rest.
 */
/proc/om_lane_work(datum/E, slice_proc, cursor, on_done, now = FALSE)
	if(now || !SSbehaviours?.initialized || !Master?.processing)
		while(!isnull(cursor) && !QDELETED(E))
			cursor = call(E, slice_proc)(cursor)
		if(!QDELETED(E))
			om_lane_work_done(E, on_done)
		return
	// on_done travels in a list: a callback passed to om_after() on its own is held weakly.
	om_after(E, 0, /proc/om_lane_work_run, E, slice_proc, cursor, list(on_done))

/proc/om_lane_work_run(datum/E, slice_proc, cursor, list/done_box)
	var/datum/om/scheduler/sched = E.om_rec?.sched || om_scheduler()
	do
		cursor = call(E, slice_proc)(cursor)
	while(!isnull(cursor) && !sched.out_of_budget())
	if(!isnull(cursor))
		om_after(E, world.tick_lag, /proc/om_lane_work_run, E, slice_proc, cursor, done_box)
		return
	om_lane_work_done(E, done_box[1])

/// `on_done`: a proc on E, or a /datum/callback.
/proc/om_lane_work_done(datum/E, on_done)
	if(istype(on_done, /datum/callback))
		var/datum/callback/C = on_done
		C.Invoke()
	else if(on_done)
		call(E, on_done)()
