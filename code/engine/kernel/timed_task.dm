// Timed tasks: the task that replaced do_after (code/engine/kernel/tasks.dm), the procedural form of an op's wait() part.
//
// A timed task is a /datum/task/timed: `actor` works on `target` for its duration, with a progress bar the client animates (no per-tick
// updates) and a cog for others. Nothing sleeps and nothing polls: it completes by its timer, and it is cancelled when a read it watches
// is published and its checks now refuse:
//   - the user moves (OP_KEEP_MOVED on the user)              unless IGNORE_USER_LOC_CHANGE
//   - the user's active hand changes (OP_KEEP_HAND)            unless IGNORE_HELD_ITEM
//   - the user is knocked out or stunned (stat, stun, sleep)   unless IGNORE_INCAPACITATED
//   - the target moves (OP_KEEP_MOVED on the target)           unless IGNORE_TARGET_LOC_CHANGE
//   - the target, the receiver or any datum in the task's state is deleted
//   - the user leaves max_distance, or changes the aimed zone (target_zone, asked when the task ends)
//   - `check_proc` (on the receiver, with the task) returns FALSE, re-checked on the same reads and at the end
// On completion complete_proc runs on the receiver with the task; on cancel, cancel_proc.
//
//	/datum/task/timed/lockpick
//		complete_proc = /obj/item/lockpick/proc/pick_done
//		var/obj/structure/simple_door/door
//
//	task_start(/datum/task/timed/lockpick, user, src, duration = 5 SECONDS, door = D)
//
// task_timed() is the zero-state case: a proc and at most two plain arguments.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)
/// Unit tests that drive gameplay procs synchronously set this: every timed action completes at once.
GLOBAL_VAR_INIT(timed_actions_instant, FALSE)
#endif

/datum/task/timed
	abstract_type = /datum/task/timed
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
	/// A datum (or list) the action also claims: the bot, tool or machine doing the work. It is busy (task_busy()) until the action ends;
	/// if something already claims it, "busy".
	var/busy

	// ---- run state: what was where when it started (REF texts: plain data, nothing kept alive)
	var/user_loc_ref
	var/target_loc_ref
	var/holding_ref
	var/captured = FALSE
	var/counted = FALSE
	var/datum/progressbar/progbar
	var/datum/cogbar/cog

CAPABILITIES(/datum/task/timed)
	owns_one(nameof(progbar), /datum/progressbar)
	owns_one(nameof(cog), /datum/cogbar)

/datum/task/timed/on_starting()
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
		if(istext(task_claim(src, D)))
			return "busy"
	user_loc_ref = REF(user.loc)
	target_loc_ref = A ? REF(A.loc) : null
	holding_ref = REF(user.get_active_hand())
	captured = TRUE
	if(interaction_key)
		LAZYSET(user.do_afters, interaction_key, (LAZYACCESS(user.do_afters, interaction_key) || 0) + 1)
		counted = TRUE
	return null

/datum/task/timed/on_started()
	var/mob/user = actor
	if(progress)
		if(user.client)
			rel_set(src, nameof(progbar), new /datum/progressbar(user, duration, target || user))
			progbar.animate_fill(duration)
		if(!hidden && duration >= 1 SECONDS)
			rel_set(src, nameof(cog), new /datum/cogbar(user, icon, iconstate))
	PUBLISH_LEGACY(user, /datum/notice/do_after_began)

/// A repeating timed action (steps) shows a fresh bar for each step.
/datum/task/timed/on_rescheduled(delay)
	var/mob/user = actor
	if(!progress || !istype(user))
		return
	// The bar fades out on its own and deletes itself: handed off, not owned.
	var/datum/progressbar/old_bar = own_take(src, nameof(progbar))
	if(!QDELETED(old_bar))
		old_bar.end_progress(TRUE)
	if(user.client && delay > 0)
		rel_set(src, nameof(progbar), new /datum/progressbar(user, delay, target || user))
		progbar.animate_fill(delay)

/// The user's place, hands and consciousness, and the target's place: what can break the action.
/datum/task/timed/watched_reads()
	. = list()
	if(!(flags & IGNORE_USER_LOC_CHANGE))
		. += list(list(actor, OP_KEEP_MOVED))
	if(!(flags & IGNORE_HELD_ITEM))
		. += list(list(actor, OP_KEEP_HAND))
	if(!(flags & IGNORE_INCAPACITATED))
		. += list(list(actor, "stat"), list(actor, stat_def_of(STAT_STUNNED)?.stat_key), list(actor, stat_def_of(STAT_SLEEPING)?.stat_key))
	if(target && target != actor && !(flags & IGNORE_TARGET_LOC_CHANGE))
		. += list(list(target, OP_KEEP_MOVED))

/datum/task/timed/why_not_running()
	var/mob/user = actor
	var/atom/A = target != actor ? target : null // working on yourself has no separate target
	if(captured)
		if(!(flags & IGNORE_USER_LOC_CHANGE) && REF(user.loc) != user_loc_ref)
			return "moved"
		if(!(flags & IGNORE_HELD_ITEM) && REF(user.get_active_hand()) != holding_ref)
			return "hands changed"
		if(!(flags & IGNORE_INCAPACITATED) && user.incapacitated(INCAPACITATION_STUNNED | INCAPACITATION_KNOCKOUT))
			return "incapacitated"
		if(A)
			if(!(flags & IGNORE_TARGET_LOC_CHANGE) && REF(A.loc) != target_loc_ref)
				return "target moved"
			if(max_distance && get_dist(user, A) > max_distance)
				return "too far away"
		if(target_zone && user.zone_sel?.selecting != target_zone)
			return "aim changed"
	if(!timed_check())
		return "interrupted"
	return null

/datum/task/timed/on_complete()
	// The last change may have arrived in the same tick as the timer (a steps task's last step has already acted, so it isn't
	// second-guessed).
	var/why = length(steps) ? null : why_not_running()
	timed_action_end(isnull(why))
	if(!isnull(why))
		state = TASK_CANCELLED
		reason = why
		timed_failed()
		return
	timed_done()

/datum/task/timed/on_cancel(reason)
	timed_action_end(FALSE)
	timed_failed()

/// The action finished: complete_proc on the receiver.
/datum/task/timed/proc/timed_done()
	if(complete_proc)
		task_call(src, complete_proc)

/// The action was cancelled or failed its last check: cancel_proc on the receiver.
/datum/task/timed/proc/timed_failed()
	if(fail_message)
		to_chat(actor, fail_message)
	if(cancel_proc)
		task_call(src, cancel_proc)

/// FALSE cancels the action (check_proc on the receiver).
/datum/task/timed/proc/timed_check()
	if(!check_proc)
		return TRUE
	return task_call(src, check_proc) != FALSE

/datum/task/timed/proc/timed_action_end(success)
	// Both fade out and delete themselves: handed off, not owned.
	var/datum/progressbar/done_bar = own_take(src, nameof(progbar))
	if(!QDELETED(done_bar))
		done_bar.end_progress(success)
	var/datum/cogbar/done_cog = own_take(src, nameof(cog))
	done_cog?.remove()
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
		PUBLISH_LEGACY(user, /datum/notice/do_after_ended)

// ---------------------------------------------------------------- task_timed: the zero-state shape

/// task_timed()'s task: a proc on the receiver with a short argument list.
/datum/task/timed/simple
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
/datum/task/timed/simple/claiming
	name = "timed_action_claiming"
	claims = TRUE

/datum/task/timed/simple/timed_done()
	call_captured(receiver, done_proc, done_args, done_pos)

/datum/task/timed/simple/timed_failed()
	call_captured(receiver, fail_proc, fail_args, fail_pos, TRUE)

/datum/task/timed/simple/timed_check()
	return !call_check_proc || call_captured(receiver, call_check_proc, check_args, check_pos)

/// Calls a captured proc: FALSE if the callee or an argument is gone, else the proc's result (TRUE for a null result). `nulls_for_gone`:
/// a gone argument is passed as null instead (cleanup that must run).
/proc/call_captured(datum/callee, proc_ref, list/captured, list/positions, nulls_for_gone = FALSE)
	if(!proc_ref)
		return TRUE
	var/list/call_args = captured ? captured.Copy() : list()
	if(!resolve_captured(call_args, positions, nulls_for_gone))
		log_qdel("TASK: dropped timed-action call [proc_ref] on [callee]: a captured argument was deleted")
		return FALSE
	if(copytext("[proc_ref]", 1, 7) == "/proc/")
		. = call(proc_ref)(arglist(call_args))
		return isnull(.) ? TRUE : .
	if(!callee || QDELETED(callee))
		return FALSE
	. = call(callee, proc_ref)(arglist(call_args))
	return isnull(.) ? TRUE : .

/**
 * A timed action with no state of its own: `user` works on `target` for `delay` deciseconds, then `on_done` runs on `receiver` with
 * `done_args`. At most two arguments across done_args, fail_args and check_args: anything more is state, and belongs on a named task
 * type (see the top of this file). Returns the task, null when a zero delay completed at once, or a text reason it did not start
 * (on_fail does not run then).
 *
 * timed_action_flags: IGNORE_* (flags.dm). The named arguments are the timed task's vars.
 */
/proc/task_timed(mob/user, delay, atom/target, datum/receiver, on_done, list/done_args, timed_action_flags = NONE, on_fail, list/fail_args, check_proc, list/check_args, progress = TRUE, interaction_key, max_interact_count = 1, hidden = FALSE, icon = 'icons/effects/progressbar.dmi', iconstate = "cog", target_zone, max_distance, claims = FALSE, busy)
	if(!istype(user) || QDELETED(user))
		return "gone"
	if(!isnum(delay))
		CRASH("task_timed was passed a non-number delay: [delay || "null"].")
	var/list/done = capture_args(done_args)
	var/list/fail = capture_args(fail_args)
	var/list/check = capture_args(check_args)
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
	// The callbacks run on `receiver`, else the user.
	params["receiver"] = receiver || user
	var/datum/task/timed/T = task_launch(claims ? /datum/task/timed/simple/claiming : /datum/task/timed/simple, user, (target && target != user) ? target : null, params, null)
	if(istype(T) && T.state == TASK_DONE)
		return null
	return T

/// Calls `proc_ref` on `receiver` with `call_args` (a /proc/ path is called globally). No-op without a proc.
/proc/call_ref(datum/receiver, proc_ref, list/call_args)
	if(!proc_ref)
		return
	if(copytext("[proc_ref]", 1, 7) == "/proc/")
		return call(proc_ref)(arglist(call_args || list()))
	if(!receiver)
		return
	return call(receiver, proc_ref)(arglist(call_args || list()))

/// Running timed tasks of `user` (on `target`, when given).
/proc/timed_tasks_of(mob/user, atom/target)
	. = list()
	for(var/datum/task/timed/T in user?.rx?.tasks_on)
		if(T.actor == user && T.state == TASK_RUNNING && (!target || T.target == target))
			. += T
