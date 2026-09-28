// Object-model core: tasks (doc/rewrite/object_model_core.md §11).
//
// A task is "actor does something to target for a while". It is declared as a type, and its
// state lives on the task:
//
//	/datum/om/task/timed/absorb
//		duration = 15 SECONDS
//		complete_proc = /mob/living/proc/absorb_done   // called on the receiver with the task
//		var/obj/item/grab/grab                          // state, set from om_task_start()'s params
//		var/stage
//
//	om_task_start(/datum/om/task/timed/absorb, user, victim, grab = G, stage = 2)
//
// om_task_start() is a macro (code/__defines/om.dm): its named arguments set the task's typed
// vars (a name the type doesn't declare is a CRASH on the first run, and
// tools/ci/api_lints.py's task_params_list counts the old list("grab" = G) form). The receiver
// defaults to whichever of the caller's src, the target or the actor has the complete_proc, so
// "receiver" = src is not repeated. A complete_proc/cancel_proc of the task's own type runs on
// the task with no arguments and reads the state as its own vars (no copying into locals).
//
// It is finished by a deadline (no polling), or by `steps`; cancelled when its requires fail
// (re-checked only when their channels change on the actor or target), when an interrupted_by
// event reaches the actor, or when the actor, the target or any datum in its state is deleted.
// Exclusivity is a claim relation (target_single, refuse): a second claimant gets the reason
// back. Nothing waits on a task: on_complete/on_cancel (or the steps) carry the rest.
//
// The registry keeps one compiled prototype per task type (`spec`); every run is a new
// instance of the type. A bundle's `tasks` rows are tasks declared as data: their prototype is
// a plain /datum/om/task with the row's values.

/datum/om/task
	abstract_type = /datum/om/task
	// ---- declaration (the type's vars; params may override any of them per run)
	var/name
	/// Deciseconds, or FROM_VAR("x") read from the actor.
	var/duration = 0
	/// Relation type used to claim the target (TRUE: /datum/om/relation/claim). Null: no claim.
	var/claims
	/// TRUE: the task also claims its actor. The actor is busy while it runs (om_busy()), and a
	/// second actor-claiming task is refused.
	var/claims_actor = FALSE
	/// Check specs (actor, target).
	var/list/requires
	/// Event types that cancel the task when emitted on the actor.
	var/list/interrupted_by
	/// Extra channels on the actor (and target) that re-check requires and why_not_running().
	var/interrupt_on = 0
	/// Steps (object_model_core.md §4.11): list(/type/proc/x = delay, ...), in order. A step
	/// proc of the task's own type runs on the task with no arguments; any other runs on the
	/// receiver (default: the actor) with the task. It returns STEP_NEXT, STEP_REPEAT(d), STEP_DONE or STEP_FAIL(reason).
	/// Past the last step the task completes. With steps, `duration` is unused.
	var/list/steps
	/// A proc called on the receiver with the task when it completes / is cancelled (a /proc/
	/// path is called globally with the task). Overriding on_complete()/on_cancel() instead is
	/// the same thing.
	var/complete_proc
	var/cancel_proc
	/// TRUE: a zero duration completes at once, inside om_task_start() (timed actions).
	var/instant_at_zero = FALSE
	/// State vars that are not held (a beam or effect that ends itself): deleting what they
	/// hold doesn't cancel the task, so read them with QDELETED() checks.
	var/list/unheld

	// ---- run state
	/// The compiled prototype of this task's type (or bundle row).
	var/datum/om/task/spec
	var/datum/actor
	var/datum/target
	/// Whose complete_proc/cancel_proc run (the item or machine doing the work). Default: the actor.
	var/datum/receiver
	var/started_at = 0
	var/ends_at = 0
	var/state = OM_TASK_RUNNING
	var/reason
	var/list/extra_requires
	var/datum/om/edge/claim
	/// Further claim edges (the actor, a tool, a holder: om_task_claim()), released with the task.
	var/list/extra_claims
	/// Edges to the datums in the task's state (edge = var name): deleting one cancels the task.
	var/list/held_edges
	/// Index of the next step (steps tasks), 1-based over spec.compiled_steps' pairs.
	var/step_no = 0

	// ---- compiled (on the prototype only)
	/// Flat: proc, delay, proc, delay...
	var/list/compiled_steps
	var/list/compiled_requires
	var/requires_mask = 0
	var/claim_rel
	/// Every event type (interrupted_by and their subtypes) that cancels this task: path -> TRUE.
	var/list/compiled_interrupts

/datum/om/task/proc/compile(datum/om/registry/reg)
	compiled_requires = list()
	for(var/check_spec in (isnull(requires) ? list() : om_spec_list(requires)))
		var/datum/om/check/C = om_check_get(check_spec, reg)
		if(!C)
			reg.error("task [name]: malformed requires entry")
			continue
		compiled_requires += C
		requires_mask |= C.depends_on
	if(claims)
		claim_rel = (claims == TRUE) ? /datum/om/relation/claim : claims
		if(!reg.relation_by_type[claim_rel])
			reg.error("task [name]: unknown claim relation [claim_rel]")
			claim_rel = null
	for(var/path in interrupted_by)
		if(!ispath(path, /datum/om/event))
			reg.error("task [name]: interrupted_by [path] is not an event")
			continue
		for(var/event_path in reg.event_types)
			if(ispath(event_path, path))
				LAZYSET(compiled_interrupts, event_path, TRUE)
	if(length(steps))
		compiled_steps = list()
		for(var/step_proc in steps)
			var/delay = steps[step_proc]
			if(!isnum(delay) || delay < 0)
				reg.error("task [name]: step [step_proc] needs a delay")
				delay = 0
			compiled_steps += list(step_proc, delay)

/// Extra requirements for this run (presets such as timed_tool read their state here).
/datum/om/task/proc/extra_requires()
	return null

/// Called once the task is claimed and its state set, before it is scheduled. Returns null, or
/// a reason to refuse the start (nothing else runs then).
/datum/om/task/proc/on_starting()
	return null

/// Called once the task is running (UI, signals).
/datum/om/task/proc/on_started()
	return

/// A steps task's next step is due in `delay` (a repeat, or the next step).
/datum/om/task/proc/on_rescheduled(delay)
	return

/// Per-run conditions that aren't table checks (the actor has not moved since the start, ...):
/// re-checked with the requires on every wake. Null, or the reason to cancel.
/datum/om/task/proc/why_not_running()
	return null

/datum/om/task/proc/on_complete()
	if(complete_proc)
		om_task_call(src, complete_proc)

/datum/om/task/proc/on_cancel(reason)
	if(cancel_proc)
		om_task_call(src, cancel_proc)

/// Calls `proc_ref` with the task: a /proc/ path globally, a proc of the task's own type on the
/// task with no arguments, else on the receiver (skipped once the receiver is gone).
/proc/om_task_call(datum/om/task/T, proc_ref)
	if(copytext("[proc_ref]", 1, 7) == "/proc/")
		return call(proc_ref)(T)
	if(om_task_own_proc(T, proc_ref))
		return call(T, proc_ref)()
	var/datum/R = T.receiver
	if(!R || QDELETED(R))
		return null
	return call(R, proc_ref)(T)

/**
 * Starts task `task` (a /datum/om/task type, or a name from a bundle's `tasks`) with `actor`
 * working on `target`. Called through the om_task_start() macro:
 *
 *	om_task_start(/datum/om/task/timed/tome_scribe, user, src, chosen_rune = rune, word1 = w1)
 *
 * `rest` is everything after the actor: the target (optional, positional), then the named
 * arguments, which set the run's vars: its state, and any declaration var to override
 * (duration, receiver, ...). Every datum among them is held: deleting it cancels the task.
 * `starter` is the caller's src (the macro passes it): without an explicit receiver, the
 * receiver is the first of starter, target and actor that has the complete_proc (or
 * cancel_proc/check_proc/a step proc). A positional params list is refused (name each
 * argument). Returns the task, or a text reason it can't start.
 */
/proc/om_task_begin(task, datum/actor, list/rest, datum/starter)
	var/datum/target
	var/list/params = list()
	var/positional = 0
	for(var/i in 1 to length(rest))
		var/entry = rest[i]
		if(istext(entry))
			params[entry] = rest[entry]
			continue
		positional++
		if(positional == 1)
			target = entry
		else
			CRASH("om: task [task] was given a positional argument ([entry]); name it (var = value)")
	return om_task_launch(task, actor, target, params, starter)

/// Starts a task from a built params list (var name -> value): om_task_begin() and the helpers
/// that build their own (om_task_timed(), flows, use_tool()).
/proc/om_task_launch(task, datum/actor, datum/target, list/params, datum/starter)
	var/datum/om/registry/reg = om_registry()
	var/datum/om/task/spec = ispath(task) ? reg.task_by_type[task] : reg.task_by_name[task]
	if(!spec)
		CRASH("om: unknown task [task]")
	if(!actor || QDELETED(actor))
		return "gone"
	if(target && QDELETED(target))
		return "gone"
	var/datum/om/task/T = new spec.type
	T.spec = spec
	if(spec.type == /datum/om/task)
		// A bundle row: its declaration is on the prototype.
		T.name = spec.name
		T.duration = spec.duration
		T.complete_proc = spec.complete_proc
		T.cancel_proc = spec.cancel_proc
	T.actor = actor
	T.target = target
	for(var/key in params)
		if(!istext(key))
			CRASH("om: task [spec.name] was given a positional argument ([key]); name it (var = value)")
		if(!(key in T.vars))
			CRASH("om: task [spec.name] has no var [key]")
		var/value = params[key]
		var/datum/D = value
		if(isdatum(D) && QDELETED(D))
			return "gone"
		T.vars[key] = value // ALLOW(api): om_task_start() params and task_holds clearing: task state by name
	if(!T.receiver)
		T.receiver = T.pick_receiver(starter)
	if(isnull(T.duration))
		T.duration = 0
	else if(!isnum(T.duration))
		T.duration = om_read(actor, T.duration)
#ifdef UNIT_TESTS
	if(T.instant_at_zero && GLOB.timed_actions_instant)
		T.duration = 0
#endif
	var/list/extra = T.extra_requires()
	for(var/datum/om/check/C as anything in spec.compiled_requires)
		var/reason = C.why_not(actor, target)
		if(!isnull(reason))
			return reason
	var/extra_mask = 0
	for(var/check_spec in extra)
		var/datum/om/check/C = om_check_get(check_spec)
		var/reason = C ? C.why_not(actor, target) : "malformed check"
		if(!isnull(reason))
			return reason
		extra_mask |= C.depends_on
	T.extra_requires = extra
	if(T.instant_at_zero && T.duration <= 0 && !spec.compiled_steps)
		return om_task_run_instantly(T)
	var/datum/om/rec/rec = om_rec_of(actor)
	if(!rec)
		return "gone"
	var/refused = om_task_claim_all(T)
	if(isnull(refused))
		refused = T.on_starting()
	if(!isnull(refused))
		T.state = OM_TASK_CANCELLED
		om_task_release_claims(T)
		if(T.om_rec)
			om_teardown_rest(T)
		return refused
	var/t = rec.sched.now()
	T.started_at = t
	T.ends_at = t + max(T.duration, 0)
	if(spec.compiled_steps)
		T.step_no = 1
		T.ends_at = t + spec.compiled_steps[2]
	LAZYADD(rec.tasks, T)
	om_task_interrupts_add(rec, spec)
	var/datum/om/behaviour/B = reg.task_behaviour
	om_attach(actor, B)
	var/mask = spec.requires_mask | T.interrupt_on | extra_mask
	if(mask)
		om_watch(actor, actor, mask, B)
		if(target && target != actor)
			om_watch(actor, target, mask, B)
	om_recompute_listen(rec)
	om_tasks_reschedule(rec)
	T.on_started()
	return T

/// The receiver of a task started without one: the first of `starter` (the caller's src), the
/// target and the actor that has the task's complete_proc, cancel_proc, check_proc or a step
/// proc. Otherwise the starter (the caller asked for the work), else the actor.
/datum/om/task/proc/pick_receiver(datum/starter)
	var/datum/om/task/T = src
	var/list/procs = list(T.complete_proc, T.cancel_proc)
	if(istype(T, /datum/om/task/timed))
		var/datum/om/task/timed/timed = T
		procs += timed.check_proc
	for(var/step_proc in T.steps)
		procs += step_proc
	for(var/proc_ref in procs)
		if(!proc_ref || copytext("[proc_ref]", 1, 7) == "/proc/" || om_task_own_proc(T, proc_ref))
			continue
		for(var/datum/candidate as anything in list(starter, T.target, T.actor))
			if(candidate && !QDELETED(candidate) && proc_fits(candidate, proc_ref))
				return candidate
	if(starter && !QDELETED(starter))
		return starter
	return T.actor

/// TRUE when `proc_ref` (a proc path, or a PROC_REF() name) can be called on `D`.
/datum/om/task/proc/proc_fits(datum/D, proc_ref)
	var/text = "[proc_ref]"
	var/at = findtext(text, "/proc/")
	if(!at)
		at = findtext(text, "/verb/")
	if(at > 1)
		var/owner = text2path(copytext(text, 1, at))
		return owner && istype(D, owner)
	return hascall(D, text)

/// A zero-duration task that completes at once (timed actions with no delay): its checks run,
/// then on_complete, or on_cancel with the reason (which is returned).
/proc/om_task_run_instantly(datum/om/task/T)
	var/reason = T.why_not_running()
	if(!isnull(reason))
		T.state = OM_TASK_CANCELLED
		T.reason = reason
		T.on_cancel(reason)
		return reason
	T.state = OM_TASK_DONE
	T.on_complete()
	return T

/// Claims the target (or links to it) and holds every datum in the task's state. Null, or the
/// reason it can't.
/proc/om_task_claim_all(datum/om/task/T)
	var/datum/om/task/spec = T.spec
	var/datum/target = T.target
	var/datum/actor = T.actor
	if(spec.claim_rel && target)
		var/claimed = om_link(T, target, spec.claim_rel)
		if(istext(claimed))
			return claimed
		T.claim = claimed
	else if(target && target != actor)
		// Not exclusive, but the task still ends when its target is deleted.
		var/linked = om_link(T, target, /datum/om/relation/task_on)
		if(istext(linked))
			return linked
		T.claim = linked
	if(spec.claims_actor)
		var/claimed_actor = om_task_claim(T, actor)
		if(istext(claimed_actor))
			return claimed_actor
	for(var/name in om_task_state_vars(T.type))
		var/datum/D = T.vars[name]
		if(!isdatum(D) || D == actor || D == target || D == T)
			continue
		var/datum/om/edge/edge = om_link(T, D, /datum/om/relation/task_holds)
		if(istext(edge))
			return "gone"
		LAZYSET(T.held_edges, edge, name)
	return null

/// The vars a task type adds for its state (and `receiver`): the ones held while it runs.
/proc/om_task_state_vars(path)
	var/static/list/by_type = list()
	var/list/names = by_type[path]
	if(names)
		return names
	var/static/list/base_vars
	if(!base_vars)
		base_vars = list()
		var/datum/om/task/base = new /datum/om/task
		for(var/name in base.vars)
			base_vars[name] = TRUE
	names = list("receiver")
	var/datum/om/task/proto = new path
	for(var/name in proto.vars)
		if(!base_vars[name] && !(name in proto.unheld))
			names += name
	by_type[path] = names
	return names

/proc/om_task_cancel(datum/om/task/T, reason = "cancelled")
	if(T.state != OM_TASK_RUNNING)
		return FALSE
	T.state = OM_TASK_CANCELLED
	T.reason = reason
	om_task_finish(T)
	try
		T.on_cancel(reason)
	catch(var/exception/e)
		dq_report_caught(e, "om task [T.name] on_cancel")
	return TRUE

/proc/om_task_complete(datum/om/task/T)
	if(T.state != OM_TASK_RUNNING)
		return FALSE
	T.state = OM_TASK_DONE
	om_task_finish(T)
	try
		T.on_complete()
	catch(var/exception/e)
		dq_report_caught(e, "om task [T.name] on_complete")
	return TRUE

/proc/om_task_finish(datum/om/task/T)
	var/datum/om/rec/rec = T.actor?.om_rec
	om_task_release_claims(T)
	if(T.om_rec)
		om_teardown_rest(T)
	if(!rec)
		return
	if(T in rec.tasks)
		om_task_interrupts_remove(rec, T.spec)
	LAZYREMOVE(rec.tasks, T)
	var/datum/om/behaviour/B = om_registry().task_behaviour
	if(!rec.tasks && !rec.torn_down)
		if(T.target && T.target != T.actor)
			om_unwatch(T.actor, T.target, B)
		om_unwatch(T.actor, T.actor, B)
		om_detach(T.actor, B)
	om_recompute_listen(rec)
	if(!rec.torn_down)
		om_tasks_reschedule(rec)

/proc/om_tasks_reschedule(datum/om/rec/rec)
	var/soonest = null
	for(var/datum/om/task/T as anything in rec.tasks)
		if(isnull(soonest) || T.ends_at < soonest)
			soonest = T.ends_at
	var/datum/om/behaviour/B = om_registry().task_behaviour
	if(isnull(soonest))
		om_cancel_after(rec.owner, B)
	else
		om_deadline(rec.owner, max(soonest - rec.sched.now(), 0), B)

/// Internal: completes due tasks (deadline) and re-checks requires (watch wakes).
/datum/om/behaviour/internal/tasks
	name = "om: tasks"
	lane = LANE_URGENT

/datum/om/behaviour/internal/tasks/on_deadline(datum/E)
	var/datum/om/rec/rec = E.om_rec
	if(!rec)
		return
	var/t = rec.sched.now()
	for(var/datum/om/task/T as anything in rec.tasks?.Copy())
		if(T.state != OM_TASK_RUNNING || T.ends_at > t)
			continue
		if(T.step_no)
			om_task_run_step(T, t)
		else
			om_task_complete(T)
	if(rec.owner)
		om_tasks_reschedule(rec)

/datum/om/behaviour/internal/tasks/on_wake(datum/E, changes)
	var/datum/om/rec/rec = E.om_rec
	for(var/datum/om/task/T as anything in rec?.tasks?.Copy())
		var/reason = null
		for(var/datum/om/check/C as anything in T.spec.compiled_requires)
			reason = C.why_not(T.actor, T.target)
			if(!isnull(reason))
				break
		if(isnull(reason))
			for(var/check_spec in T.extra_requires)
				reason = om_why_not(check_spec, T.actor, T.target)
				if(!isnull(reason))
					break
		if(isnull(reason) && T.state == OM_TASK_RUNNING)
			reason = T.why_not_running()
		if(!isnull(reason))
			om_task_cancel(T, reason)

/// Runs the task's current step and acts on its result. Cancelling is always safe: no
/// proc is suspended inside a step.
/proc/om_task_run_step(datum/om/task/T, t)
	var/list/S = T.spec.compiled_steps
	var/i = T.step_no * 2 - 1
	var/result
	try
		var/step_proc = S[i]
		if(om_task_own_proc(T, step_proc))
			result = om_guarded_call(T, step_proc, null)
		else if(QDELETED(T.receiver))
			result = STEP_FAIL("gone")
		else
			result = om_guarded_call(T.receiver, step_proc, list(T))
		if(result == OM_CALLEE_SLEPT)
			result = STEP_FAIL("slept")
	catch(var/exception/e)
		dq_report_caught(e, "om task [T.name] step [S[i]]")
		result = STEP_FAIL("error")
	if(T.state != OM_TASK_RUNNING)
		return // the step cancelled or finished its own task
	if(islist(result))
		var/list/R = result
		switch(R[1])
			if(OM_STEP_REPEAT)
				T.ends_at = t + max(R[2], 0)
				T.on_rescheduled(max(R[2], 0))
				return
			if(OM_STEP_FAIL)
				om_task_cancel(T, R[2] || "failed")
				return
	if(result == STEP_DONE)
		om_task_complete(T)
		return
	// STEP_NEXT (or null).
	T.step_no++
	if(T.step_no * 2 > length(S))
		om_task_complete(T)
		return
	T.ends_at = t + S[T.step_no * 2]
	T.on_rescheduled(S[T.step_no * 2])

/// TRUE when `proc_ref` is a proc of the task's own type (a step that runs on the task).
/proc/om_task_own_proc(datum/om/task/T, proc_ref)
	var/text = "[proc_ref]"
	var/at = findtext(text, "/proc/")
	if(!at)
		at = findtext(text, "/verb/")
	if(at <= 1)
		return FALSE
	var/owner = text2path(copytext(text, 1, at))
	return owner && istype(T, owner)

/// Drops every claim and hold `T` has (its target's, the extra ones, its state's).
/proc/om_task_release_claims(datum/om/task/T)
	if(T.claim)
		var/datum/om/edge/edge = T.claim
		T.claim = null
		om_unlink_edge(edge)
	if(T.extra_claims)
		var/list/edges = T.extra_claims
		T.extra_claims = null
		for(var/datum/om/edge/edge as anything in edges)
			om_unlink_edge(edge)
	if(T.held_edges)
		var/list/edges = T.held_edges
		T.held_edges = null
		for(var/datum/om/edge/edge as anything in edges)
			om_unlink_edge(edge)

/// `T` also claims `D` (its actor, the tool it works with, the machine or bot it runs): `D` is
/// busy until `T` completes, is cancelled or either is deleted. Returns the edge, or a text
/// reason when something else already claims `D`.
/proc/om_task_claim(datum/om/task/T, datum/D)
	if(!D || T.state != OM_TASK_RUNNING)
		return "invalid"
	if(T.claim?.target == D)
		return T.claim
	var/claimed = om_link(T, D, /datum/om/relation/claim/busy)
	if(istext(claimed))
		return claimed == "[D] is in use" ? "[D] is busy" : claimed
	LAZYOR(T.extra_claims, claimed)
	return claimed

/// The running task that claims `D`, or null. This is what "busy" means: a bot, a tool or a
/// machine is busy while a task claims it.
/proc/om_claiming_task(datum/D)
	var/datum/om/task/T = om_source_of(D, /datum/om/relation/claim/busy)
	if(istype(T) && T.state == OM_TASK_RUNNING)
		return T
	T = om_source_of(D, /datum/om/relation/claim)
	return (istype(T) && T.state == OM_TASK_RUNNING) ? T : null

/// TRUE while a running task claims `D`: as the thing doing the work (its actor, tool or
/// machine) or as the exclusive target of someone's work.
/proc/om_busy(datum/D)
	return !isnull(om_claiming_task(D))

/// TRUE while a running task claims `D` as its exclusive target (someone is working on it),
/// whatever `D` itself is doing.
/proc/om_in_use(datum/D)
	var/datum/om/task/T = om_source_of(D, /datum/om/relation/claim)
	return istype(T) && T.state == OM_TASK_RUNNING

/// Cancels the task that claims `D`, if any (it stopped early). TRUE if one was cancelled.
/proc/om_release_busy(datum/D, reason = "released")
	var/datum/om/task/T = om_claiming_task(D)
	return T ? om_task_cancel(T, reason) : FALSE

/// Holds `E` busy for `duration` (an action whose continuation is a timer, not a task step):
/// a task on `E` claiming it, done at the deadline. `on_end`, a proc on `E`, runs when the hold
/// ends (done or cancelled). Returns the task, or a reason (already busy).
/proc/om_hold_busy(datum/E, duration, on_end)
	return om_task_begin(/datum/om/task/hold, E, list(null, duration = max(duration, 0), complete_proc = on_end, cancel_proc = on_end), null) // global proc: no caller src

/// See om_hold_busy().
/datum/om/task/hold
	name = "hold"
	claims_actor = TRUE

/datum/om/task/hold/on_complete()
	if(complete_proc && !QDELETED(actor))
		call(actor, complete_proc)()

/datum/om/task/hold/on_cancel(reason)
	on_complete()

/// The claim relation: a target is claimed by at most one task.
/datum/om/relation/claim
	name = "claim"
	target_single = TRUE
	conflict = OM_REL_REFUSE

/// A task's claim on what does the work (its actor, a tool, a bot or machine): the worker is
/// busy. Its own relation, so a busy worker can still be the target of someone else's task.
/datum/om/relation/claim/busy
	name = "busy"

/datum/om/relation/claim/on_unlink(datum/source, datum/target, datum/om/edge/edge)
	var/datum/om/task/T = source
	if(!istype(T) || T.state != OM_TASK_RUNNING)
		return
	if(T.claim == edge)
		T.claim = null
		om_task_cancel(T, "target gone")
	else if(edge in T.extra_claims)
		LAZYREMOVE(T.extra_claims, edge)
		om_task_cancel(T, "gone")

/// A running task's link to a target it works on without claiming it: deleting the target
/// cancels the task.
/datum/om/relation/task_on
	name = "task on"

/datum/om/relation/task_on/on_unlink(datum/source, datum/target, datum/om/edge/edge)
	var/datum/om/task/T = source
	if(istype(T) && T.state == OM_TASK_RUNNING && T.claim == edge)
		T.claim = null
		om_task_cancel(T, "target gone")

/// A running task's hold on a datum in its state (a tool, a grab, a second target): deleting
/// it clears the var and cancels the task, so on_cancel sees null, never a deleted datum.
/datum/om/relation/task_holds
	name = "task holds"

/datum/om/relation/task_holds/on_unlink(datum/source, datum/target, datum/om/edge/edge)
	var/datum/om/task/T = source
	if(!istype(T) || T.state != OM_TASK_RUNNING || !(edge in T.held_edges))
		return
	var/name = T.held_edges[edge]
	T.held_edges -= edge
	if(T.vars[name] == target)
		T.vars[name] = null // ALLOW(api): om_task_start() params and task_holds clearing: task state by name
	om_task_cancel(T, "gone")

/// Preset: a timed tool use. State: tool (TOOL_* quality).
/datum/om/task/timed_tool
	name = "timed_tool"
	duration = 3 SECONDS
	claims = TRUE
	requires = list(/datum/om/check/adjacent, /datum/om/check/conscious, /datum/om/check/target_exists)
	var/tool

/datum/om/task/timed_tool/extra_requires()
	if(tool)
		return list(CHECK(/datum/om/check/holding_tool, tool))
	return null

/// A mob's timed work on a turf (spinning a web, laying eggs, building): it stays within one tile,
/// conscious; the claim keeps a second worker off the turf; death or deletion cancels it. The
/// actor's procs finish or clean up.
/datum/om/task/mob_work
	abstract_type = /datum/om/task/mob_work
	duration = 5 SECONDS
	claims = TRUE
	claims_actor = TRUE // the worker is busy: its AI stays still, and it can't start a second job
	requires = list(/datum/om/check/conscious, /datum/om/check/in_range, /datum/om/check/target_exists)

/datum/om/task/mob_work/spider_web
	name = "spider_web"
	complete_proc = /mob/living/simple_mob/animal/giant_spider/nurse/proc/web_done
	cancel_proc = /mob/living/simple_mob/animal/giant_spider/nurse/proc/work_interrupted

/datum/om/task/mob_work/spider_eggs
	name = "spider_eggs"
	complete_proc = /mob/living/simple_mob/animal/giant_spider/nurse/proc/eggs_done
	cancel_proc = /mob/living/simple_mob/animal/giant_spider/nurse/proc/work_interrupted

/datum/om/task/mob_work/ant_build
	name = "ant_build"
	complete_proc = /mob/living/simple_mob/animal/tyr/mineral_ants/proc/build_done
	cancel_proc = /mob/living/simple_mob/animal/tyr/mineral_ants/proc/build_interrupted

/datum/om/task/mob_work/cloak
	name = "cloak"
	duration = 1 SECOND
	claims = null
	requires = list(/datum/om/check/alive)
	complete_proc = /mob/living/simple_mob/animal/space/mouse_army/stealth/proc/cloak_done
	cancel_proc = /mob/living/simple_mob/animal/space/mouse_army/stealth/proc/cloak_interrupted
