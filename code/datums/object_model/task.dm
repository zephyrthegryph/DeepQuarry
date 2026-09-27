/** Timed, guarded work. Hooks are synchronous; dm-health must verify no-sleep call paths. */
/datum/object_model/relation/task_actor
	from_type = /datum/object_model/task
	changes_revision = FALSE

/datum/object_model/relation/task_target
	from_type = /datum/object_model/task
	changes_revision = FALSE

/datum/object_model/relation/task_tool
	from_type = /datum/object_model/task
	changes_revision = FALSE

/datum/object_model/relation/task_extra
	from_type = /datum/object_model/task
	changes_revision = FALSE

/datum/object_model/check/task
	var/datum/object_model/task/task
	var/committing = FALSE
	var/observing = FALSE

/datum/object_model/check/task/unchanged(datum/subject, message = "The target changed.")
	if(!subject || QDELETED(subject))
		return require(FALSE, message)
	var/key = REF(subject)
	if(!committing && !observing)
		task.stamps[key] = om_revision(subject)
		return TRUE
	return require(task.stamps[key] == om_revision(subject), message)

/datum/object_model/task
	/// Deciseconds, as with the rest of DM's timing API.
	var/duration = 0
	var/awaits_answer = FALSE
	var/datum/user
	var/datum/target
	var/datum/tool
	var/list/extra
	var/list/stamps
	/// Typed events declared by the start check; observed on every task participant.
	var/list/dependency_events
	var/list/dependency_subscriptions
	var/list/dependency_rules
	var/datum/object_model/schedule_entry/timer_entry
	var/deadline
	var/state = "new"
	var/failure_reason
	/// Optional live guards. A task checks them when it starts, on relevant signals, and at commit.
	var/watch_actor_location = FALSE
	var/watch_target_location = FALSE
	var/watch_actor_hand = FALSE
	var/watch_actor_incapacitated = FALSE
	var/watch_distance = 0
	var/watch_zone
	var/atom/initial_actor_location
	var/atom/initial_target_location
	var/initial_held_item

/datum/object_model/task/proc/check(datum/object_model/check/task/C, datum/actor, datum/object, datum/implement, list/parameters)
	return

/datum/object_model/task/proc/complete(datum/actor, datum/object, datum/implement, list/parameters)
	return

/datum/object_model/task/proc/on_cancel(reason)
	return

/datum/object_model/task/proc/on_finished()
	return

/datum/object_model/task/proc/on_started()
	return

/datum/object_model/task/proc/live_guard_valid()
	var/atom/movable/actor = user
	var/mob/actor_mob = user
	if(watch_actor_location && istype(actor) && actor.loc != initial_actor_location)
		return FALSE
	var/atom/object = target
	if(watch_target_location && istype(object) && object != actor && object.loc != initial_target_location)
		return FALSE
	if(watch_actor_hand && istype(actor_mob) && actor_mob.get_active_hand() != initial_held_item)
		return FALSE
	if(watch_actor_incapacitated && istype(actor_mob) && HAS_TRAIT(actor_mob, TRAIT_INCAPACITATED))
		return FALSE
	if(watch_distance && istype(actor) && istype(object) && get_dist(actor, object) > watch_distance)
		return FALSE
	if(watch_zone && istype(actor_mob) && actor_mob.zone_sel?.selecting != watch_zone)
		return FALSE
	return TRUE

/datum/object_model/task/proc/start(datum/actor, datum/object, datum/implement, list/parameters)
	if(state != "new" || !actor || QDELETED(actor))
		return "The actor is unavailable."
	if(!isnum(duration) || duration < 0)
		return "The task has an invalid duration."
	user = actor
	target = object
	tool = implement
	var/mob/actor_mob = actor
	var/atom/movable/actor_atom = actor
	var/atom/target_atom = object
	if(istype(actor_atom))
		initial_actor_location = actor_atom.loc
	if(istype(actor_mob))
		initial_held_item = actor_mob.get_active_hand()
	if(istype(target_atom))
		initial_target_location = target_atom.loc
	if(!live_guard_valid())
		return "The action was interrupted."
	extra = parameters?.Copy()
	stamps = list()
	var/datum/object_model/check/task/C = new
	C.task = src
	check(C, user, target, tool, extra)
	if(C.failure)
		var/reason = C.failure
		qdel(C)
		return reason
	dependency_events = C.dependencies?.Copy()
	qdel(C)
	if(dependency_events)
		for(var/event_path in dependency_events)
			if(!ispath(event_path, /datum/object_model/event))
				return "The task has an invalid dependency [event_path]."
	if(!om_claim(user, "om:task", src))
		return "The actor cannot own this task."
	om_link(src, /datum/object_model/relation/task_actor, user)
	if(target)
		om_link(src, /datum/object_model/relation/task_target, target)
	if(tool)
		om_link(src, /datum/object_model/relation/task_tool, tool)
	RegisterSignal(user, COMSIG_QDELETING, PROC_REF(on_participant_deleting))
	if(istype(actor, /atom/movable) && (watch_actor_location || watch_distance))
		RegisterSignal(user, COMSIG_MOVABLE_MOVED, PROC_REF(on_guard_signal))
	if(istype(actor_mob) && (watch_actor_hand || watch_actor_incapacitated || watch_zone))
		RegisterSignals(user, list(COMSIG_MOB_EQUIPPED_ITEM, COMSIG_MOB_UNEQUIPPED_ITEM, COMSIG_MOB_STATCHANGE), PROC_REF(on_guard_signal))
		if(watch_actor_incapacitated)
			RegisterSignal(user, SIGNAL_ADDTRAIT(TRAIT_INCAPACITATED), PROC_REF(on_guard_signal))
	if(target && target != user)
		RegisterSignal(target, COMSIG_QDELETING, PROC_REF(on_participant_deleting))
		if(istype(target, /atom/movable) && (watch_target_location || watch_distance))
			RegisterSignal(target, COMSIG_MOVABLE_MOVED, PROC_REF(on_guard_signal))
	if(tool && tool != target && tool != user)
		RegisterSignal(tool, COMSIG_QDELETING, PROC_REF(on_participant_deleting))
	if(extra)
		for(var/entry in extra)
			if(istype(entry, /datum) && entry != user && entry != target && entry != tool)
				var/datum/participant = entry
				om_link(src, /datum/object_model/relation/task_extra, participant)
				RegisterSignal(participant, COMSIG_QDELETING, PROC_REF(on_participant_deleting))
	state = "running"
	if(!subscribe_dependencies())
		cancel("The task could not watch its dependencies.")
		return failure_reason
	on_started()
	if(state != "running")
		return failure_reason
	if(!awaits_answer || duration > 0)
		deadline = world.time + duration
		timer_entry = om_timer(src, duration, src, "complete")
		if(!timer_entry)
			cancel("The task could not be scheduled.")
			return failure_reason
	return src

/datum/object_model/task/proc/subscribe_dependencies()
	if(!length(dependency_events))
		return TRUE
	var/list/participants = list(user)
	if(target)
		participants |= target
	if(tool)
		participants |= tool
	if(extra)
		for(var/entry in extra)
			if(istype(entry, /datum))
				participants |= entry
	dependency_subscriptions = list()
	dependency_rules = list()
	for(var/event_path in dependency_events)
		var/datum/object_model/subscription_rule/R = new
		R.event_path = event_path
		R.handler = PROC_REF(on_dependency_event)
		dependency_rules += R
		for(var/datum/participant in participants)
			if(QDELETED(participant))
				return FALSE
			var/datum/object_model/subscription/S = om_subscribe(src, R, participant, FALSE)
			if(!S)
				return FALSE
			dependency_subscriptions += S
	return TRUE

/datum/object_model/task/proc/on_dependency_event(datum/source, datum/object_model/event/E, a, b, c, d)
	if(state != "running")
		return
	if(!live_guard_valid())
		cancel("The action was interrupted.")
		return
	var/datum/object_model/check/task/C = new
	C.task = src
	C.observing = TRUE
	check(C, user, target, tool, extra)
	var/reason = C.failure
	qdel(C)
	if(reason)
		cancel(reason)

/datum/object_model/task/proc/on_participant_deleting(datum/source)
	SIGNAL_HANDLER
	cancel("A participant is no longer available.")

/datum/object_model/task/proc/on_guard_signal(datum/source)
	SIGNAL_HANDLER
	if(state == "running" && !live_guard_valid())
		cancel("The action was interrupted.")

/datum/object_model/task/om_on_timer(datum/entity, key)
	if(state != "running" || key != "complete")
		return
	if(awaits_answer)
		cancel("The prompt expired.")
	else
		finish()

/datum/object_model/task/proc/finish()
	if(state != "running")
		return FALSE
	if(!awaits_answer && world.time < deadline)
		return FALSE
	if(QDELETED(user) || (target && QDELETED(target)) || (tool && QDELETED(tool)))
		cancel("A participant is no longer available.")
		return FALSE
	if(extra)
		for(var/entry in extra)
			if(istype(entry, /datum))
				var/datum/participant = entry
				if(QDELETED(participant))
					cancel("A participant is no longer available.")
					return FALSE
	if(!live_guard_valid())
		cancel("The action was interrupted.")
		return FALSE
	var/datum/object_model/check/task/C = new
	C.task = src
	C.committing = TRUE
	check(C, user, target, tool, extra)
	if(C.failure)
		var/reason = C.failure
		qdel(C)
		cancel(reason)
		return FALSE
	qdel(C)
	state = "committing"
	// No sleeps or deferred callbacks are permitted in complete or its transitive calls.
	complete(user, target, tool, extra)
	state = "finished"
	on_finished()
	qdel(src)
	return TRUE

/datum/object_model/task/proc/cancel(reason = "Cancelled.")
	if(state != "running" && state != "new")
		return FALSE
	state = "cancelled"
	failure_reason = reason
	on_cancel(reason)
	qdel(src)
	return TRUE

/datum/object_model/task/Destroy(force = FALSE)
	if(dependency_subscriptions)
		for(var/datum/object_model/subscription/S in dependency_subscriptions)
			if(!QDELETED(S))
				qdel(S)
	dependency_subscriptions = null
	if(dependency_rules)
		for(var/datum/object_model/subscription_rule/R in dependency_rules)
			qdel(R)
	dependency_rules = null
	dependency_events = null
	if(timer_entry && !QDELETED(timer_entry))
		qdel(timer_entry)
	timer_entry = null
	if(user && !QDELETED(user))
		UnregisterSignal(user, list(COMSIG_QDELETING, COMSIG_MOVABLE_MOVED, COMSIG_MOB_EQUIPPED_ITEM, COMSIG_MOB_UNEQUIPPED_ITEM, COMSIG_MOB_STATCHANGE))
		UnregisterSignal(user, SIGNAL_ADDTRAIT(TRAIT_INCAPACITATED))
	if(target && target != user && !QDELETED(target))
		UnregisterSignal(target, list(COMSIG_QDELETING, COMSIG_MOVABLE_MOVED))
	if(tool && tool != target && tool != user && !QDELETED(tool))
		UnregisterSignal(tool, COMSIG_QDELETING)
	if(extra)
		for(var/entry in extra)
			if(istype(entry, /datum) && entry != user && entry != target && entry != tool)
				var/datum/participant = entry
				if(!QDELETED(participant))
					UnregisterSignal(participant, COMSIG_QDELETING)
	user = null
	target = null
	tool = null
	extra = null
	stamps = null
	initial_actor_location = null
	initial_target_location = null
	initial_held_item = null
	return ..()

/// Returns the running task, or a user-facing failure reason.
/proc/om_start_task(task_type, datum/user, datum/target, datum/tool, list/extra)
	if(!ispath(task_type, /datum/object_model/task))
		return "Invalid task type."
	var/datum/object_model/task/T = new task_type
	var/result = T.start(user, target, tool, extra)
	if(result != T)
		qdel(T)
	return result

/// An asynchronous timed action with do_after's interruption rules and progress display.
/// Callers implement complete(); no sleeping caller is kept alive.
/datum/object_model/task/timed_action
	watch_actor_location = TRUE
	watch_target_location = TRUE
	watch_actor_hand = TRUE
	watch_actor_incapacitated = TRUE
	var/timed_action_flags = NONE
	var/show_progress = TRUE
	var/hidden = FALSE
	var/icon = 'icons/effects/progressbar.dmi'
	var/iconstate = "cog"
	var/datum/callback/extra_checks
	var/datum/progressbar/progbar
	var/datum/cogbar/cog
	var/datum/object_model/schedule_entry/progress_timer
	var/began = FALSE
	/// Unsignaled checks (active-hand selection, zone, callback) use this interval.
	var/guard_poll_period = 1 SECOND

/datum/object_model/task/timed_action/live_guard_valid()
	if(!..())
		return FALSE
	if(extra_checks && !extra_checks.Invoke())
		return FALSE
	return TRUE

/datum/object_model/task/timed_action/on_started()
	var/mob/actor = user
	if(!istype(actor))
		return
	if(show_progress && duration > 0 && actor.client)
		progbar = new(actor, duration, target || actor)
	if(show_progress && !hidden && duration >= 1 SECOND)
		cog = new(actor, icon, iconstate)
	if(progbar || extra_checks || watch_zone || watch_actor_hand)
		progress_timer = om_periodic(src, guard_poll_period, src)
	began = TRUE
	SEND_SIGNAL(actor, COMSIG_DO_AFTER_BEGAN)

/datum/object_model/task/timed_action/om_on_periodic(datum/entity, seconds)
	if(state != "running")
		return
	if(!live_guard_valid())
		cancel("The action was interrupted.")
		return
	if(progbar && !QDELETED(progbar))
		progbar.update(world.time - (deadline - duration))

/datum/object_model/task/timed_action/Destroy(force = FALSE)
	if(progress_timer && !QDELETED(progress_timer))
		qdel(progress_timer)
	progress_timer = null
	if(progbar && !QDELETED(progbar))
		if(state == "finished")
			progbar.update(duration)
		progbar.end_progress()
	progbar = null
	cog?.remove()
	cog = null
	if(began && user && !QDELETED(user))
		SEND_SIGNAL(user, COMSIG_DO_AFTER_ENDED)
	began = FALSE
	extra_checks = null
	return ..()

/// Starts a nonblocking do_after-style task. The task subtype owns the completion logic.
/proc/om_start_timed_action(task_type, mob/user, delay, atom/target, timed_action_flags = NONE, datum/callback/extra_checks, target_zone, max_distance = null)
	if(!ispath(task_type, /datum/object_model/task/timed_action) || !isnum(delay) || delay < 0)
		return "Invalid timed action."
	var/datum/object_model/task/timed_action/T = new task_type
	T.duration = delay
	T.timed_action_flags = timed_action_flags
	T.extra_checks = extra_checks
	T.watch_zone = target_zone
	T.watch_distance = max_distance
	T.watch_actor_location = !(timed_action_flags & IGNORE_USER_LOC_CHANGE)
	T.watch_target_location = !(timed_action_flags & IGNORE_TARGET_LOC_CHANGE)
	T.watch_actor_hand = !(timed_action_flags & IGNORE_HELD_ITEM)
	T.watch_actor_incapacitated = !(timed_action_flags & IGNORE_INCAPACITATED)
	var/result = T.start(user, target, null, null)
	if(result != T)
		qdel(T)
	return result

/// Migration bridge for a legacy caller that expects do_after's synchronous boolean.
/// The caller still yields in stoplag; all guards/progress are owned by the task.
/datum/object_model/task/timed_action/legacy
	var/list/result_box

/datum/object_model/task/timed_action/legacy/live_guard_valid()
	// The old do_after loop never checked guards for a zero-duration action.
	if(duration <= 0)
		return TRUE
	return ..()

/datum/object_model/task/timed_action/legacy/on_finished()
	if(result_box)
		result_box["done"] = TRUE
		result_box["success"] = TRUE

/datum/object_model/task/timed_action/legacy/on_cancel(reason)
	if(result_box)
		result_box["done"] = TRUE
		result_box["success"] = FALSE

/datum/object_model/task/timed_action/legacy/Destroy(force = FALSE)
	if(result_box && !result_box["done"])
		result_box["done"] = TRUE
		result_box["success"] = FALSE
	result_box = null
	return ..()

/proc/om_do_after_compat(mob/user, delay, atom/target, timed_action_flags = NONE, progress = TRUE, datum/callback/extra_checks, interaction_key, max_interact_count = 1, hidden = FALSE, icon = 'icons/effects/progressbar.dmi', iconstate = "cog", target_zone, max_distance = null)
	if(!user || QDELETED(user) || !isnum(delay))
		return FALSE
	if(!interaction_key && target)
		interaction_key = target
	if(interaction_key)
		var/current_count = LAZYACCESS(user.do_afters, interaction_key) || 0
		if(current_count >= max_interact_count)
			return FALSE
		LAZYSET(user.do_afters, interaction_key, current_count + 1)
	var/list/result_box = list("done" = FALSE, "success" = FALSE)
	var/datum/object_model/task/timed_action/legacy/T = new
	T.duration = max(0, delay)
	T.timed_action_flags = timed_action_flags
	T.extra_checks = extra_checks
	T.watch_zone = target_zone
	T.watch_distance = max_distance
	T.watch_actor_location = !(timed_action_flags & IGNORE_USER_LOC_CHANGE)
	T.watch_target_location = !(timed_action_flags & IGNORE_TARGET_LOC_CHANGE)
	T.watch_actor_hand = !(timed_action_flags & IGNORE_HELD_ITEM)
	T.watch_actor_incapacitated = !(timed_action_flags & IGNORE_INCAPACITATED)
	T.show_progress = progress
	T.hidden = hidden
	T.icon = icon
	T.iconstate = iconstate
	T.guard_poll_period = world.tick_lag
	T.result_box = result_box
	var/started = T.start(user, target, null, null)
	if(started != T)
		qdel(T)
	else if(delay <= 0)
		T.finish()
	while(!result_box["done"])
		stoplag(1)
	if(interaction_key && !QDELETED(user))
		var/remaining_count = (LAZYACCESS(user.do_afters, interaction_key) || 0) - 1
		if(remaining_count > 0)
			LAZYSET(user.do_afters, interaction_key, remaining_count)
		else
			LAZYREMOVE(user.do_afters, interaction_key)
	return !!result_box["success"]

/// A prompt uses the same start and commit validation as a timed task.
/datum/object_model/task/prompt
	awaits_answer = TRUE
	var/choice

/datum/object_model/task/prompt/proc/answered(datum/actor, datum/object, datum/implement, list/parameters, answer)
	return

/datum/object_model/task/prompt/proc/answer(answer)
	if(state != "running")
		return FALSE
	choice = answer
	return finish()

/datum/object_model/task/prompt/complete(datum/actor, datum/object, datum/implement, list/parameters)
	answered(actor, object, implement, parameters, choice)

/proc/om_revision(datum/subject)
	if(!subject || QDELETED(subject))
		return null
	var/datum/object_model/state/state = om_state_for(subject)
	state.revision_tracked = TRUE
	return state.revision

/proc/om_bump_revision_if_tracked(datum/subject)
	var/datum/object_model/state/state = subject?.om_state
	if(state?.revision_tracked)
		state.revision++
		return state.revision
	return null

/proc/om_bump_revision(datum/subject)
	if(!subject || QDELETED(subject))
		return null
	var/datum/object_model/state/state = om_state_for(subject)
	state.revision++
	return state.revision

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)
/// Test clock: drive a task's deadline without waiting for game time.
/proc/om_test_clock_finish(datum/object_model/task/T)
	if(!T)
		return FALSE
	T.deadline = world.time
	return T.finish()
#endif
