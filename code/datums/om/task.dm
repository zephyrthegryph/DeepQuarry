// Object-model core: tasks (doc/rewrite/object_model_core.md section I).
//
// A task is "actor does something to target for a while": started with
// om_task_start(), finished by a deadline (no polling), cancelled when its
// requires fail (re-checked only when their channels change on the actor or
// target), when an interrupted_by event reaches the actor, or when either
// end is deleted. Exclusivity is a claim relation (target_single, refuse):
// a second claimant gets the reason back. Nothing waits on a task: its
// on_complete/on_cancel (or steps) carry the rest.

/datum/om/task_def
	abstract_type = /datum/om/task_def
	var/name
	/// Deciseconds, or FROM_VAR("x") read from the actor. params["duration"] overrides.
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
	/// Extra channels on the actor that re-check requires.
	var/interrupt_on = 0
	/// /type/proc/x called on the actor with the task (table rows).
	var/complete_proc
	var/cancel_proc
	/// Steps (object_model_core.md §4.11): list(/type/proc/x = delay, ...), in order. Each
	/// runs on the actor with the task after its delay and returns STEP_NEXT, STEP_REPEAT(d),
	/// STEP_DONE or STEP_FAIL(reason). Past the last step the task completes. With steps,
	/// `duration` is unused.
	var/list/steps
	/// The running-task type this def makes (a subtype keeps per-run state).
	var/task_type = /datum/om/task

	/// Flat: proc, delay, proc, delay...
	var/list/compiled_steps
	var/list/compiled_requires
	var/requires_mask = 0
	var/claim_rel

/datum/om/task_def/proc/compile(datum/om/registry/reg)
	compiled_requires = list()
	for(var/spec in (isnull(requires) ? list() : om_spec_list(requires)))
		var/datum/om/check/C = om_check_get(spec, reg)
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
	if(length(steps))
		compiled_steps = list()
		for(var/step_proc in steps)
			var/delay = steps[step_proc]
			if(!isnum(delay) || delay < 0)
				reg.error("task [name]: step [step_proc] needs a delay")
				delay = 0
			compiled_steps += list(step_proc, delay)

/// Extra requirements from start parameters (presets such as timed_tool).
/datum/om/task_def/proc/extra_requires(list/params)
	return null

/// Per-run conditions that aren't table checks (the actor has not moved since the start, ...):
/// re-checked with the requires on every wake. Null, or the reason to cancel.
/datum/om/task_def/proc/why_not_running(datum/om/task/T)
	return null

/// Called once the task is running (UI, signals).
/datum/om/task_def/proc/on_started(datum/om/task/T)
	return

/datum/om/task_def/proc/on_complete(datum/om/task/T)
	if(complete_proc)
		call(T.actor, complete_proc)(T)

/datum/om/task_def/proc/on_cancel(datum/om/task/T, reason)
	if(cancel_proc)
		call(T.actor, cancel_proc)(T, reason)

/// One running task.
/datum/om/task
	var/datum/om/task_def/def
	var/datum/actor
	var/datum/target
	var/list/params
	var/started_at = 0
	var/ends_at = 0
	var/state = OM_TASK_RUNNING
	var/reason
	var/list/extra_requires
	var/datum/om/edge/claim
	/// Further claim edges (the actor, a tool, a holder: om_task_claim()), released with the task.
	var/list/extra_claims
	/// Index of the next step (steps tasks), 1-based over def.compiled_steps' pairs.
	var/step_no = 0
	/// params keys whose datum values are held as OM handles (weak capture).
	var/list/param_handles

/// The datum a param names, resolved from its handle (null once deleted).
/datum/om/task/proc/param(key)
	if(param_handles && (key in param_handles))
		return om_resolve(params[key])
	return params?[key]

/// Starts task `task` (a name from a bundle's `tasks` or a /datum/om/task_def
/// type). Returns the task, or a text reason it can't start.
/proc/om_task_start(datum/actor, task, datum/target, list/params)
	var/datum/om/registry/reg = om_registry()
	var/datum/om/task_def/def = ispath(task) ? reg.task_by_type[task] : reg.task_by_name[task]
	if(!def)
		CRASH("om: unknown task [task]")
	var/datum/om/rec/rec = om_rec_of(actor)
	if(!rec)
		return "gone"
	var/list/extra = def.extra_requires(params)
	for(var/datum/om/check/C as anything in def.compiled_requires)
		var/reason = C.why_not(actor, target)
		if(!isnull(reason))
			return reason
	var/extra_mask = 0
	for(var/spec in extra)
		var/datum/om/check/C = om_check_get(spec)
		var/reason = C ? C.why_not(actor, target) : "malformed check"
		if(!isnull(reason))
			return reason
		extra_mask |= C.depends_on
	var/datum/om/task/T = new def.task_type
	T.def = def
	T.actor = actor
	T.target = target
	if(params)
		params = params.Copy()
		for(var/key in params)
			var/datum/D = params[key]
			if(!isdatum(D))
				continue
			var/h = om_handle(D)
			if(isnull(h))
				return "gone"
			params[key] = h
			LAZYADD(T.param_handles, key)
	T.params = params
	T.extra_requires = extra
	if(def.claim_rel && target)
		var/claimed = om_link(T, target, def.claim_rel)
		if(istext(claimed))
			return claimed
		T.claim = claimed
	else if(target && target != actor)
		// Not exclusive, but the task still ends when its target is deleted.
		var/linked = om_link(T, target, /datum/om/relation/task_on)
		if(istext(linked))
			return linked
		T.claim = linked
	if(def.claims_actor)
		var/claimed_actor = om_task_claim(T, actor)
		if(istext(claimed_actor))
			om_task_release_claims(T)
			return claimed_actor
	var/t = rec.sched.now()
	var/dur = params?["duration"]
	if(isnull(dur))
		dur = om_read(actor, def.duration)
	T.started_at = t
	T.ends_at = t + max(dur, 0)
	if(def.compiled_steps)
		T.step_no = 1
		T.ends_at = t + def.compiled_steps[2]
	LAZYADD(rec.tasks, T)
	var/datum/om/behaviour/B = reg.task_behaviour
	om_attach(actor, B)
	var/mask = def.requires_mask | def.interrupt_on | extra_mask
	if(mask)
		om_watch(actor, actor, mask, B)
		if(target && target != actor)
			om_watch(actor, target, mask, B)
	om_recompute_listen(rec)
	om_tasks_reschedule(rec)
	def.on_started(T)
	return T

/proc/om_task_cancel(datum/om/task/T, reason = "cancelled")
	if(T.state != OM_TASK_RUNNING)
		return FALSE
	T.state = OM_TASK_CANCELLED
	T.reason = reason
	om_task_finish(T)
	try
		T.def.on_cancel(T, reason)
	catch(var/exception/e)
		stack_trace("om task [T.def.name] on_cancel: [e]")
	return TRUE

/proc/om_task_complete(datum/om/task/T)
	if(T.state != OM_TASK_RUNNING)
		return FALSE
	T.state = OM_TASK_DONE
	om_task_finish(T)
	try
		T.def.on_complete(T)
	catch(var/exception/e)
		stack_trace("om task [T.def.name] on_complete: [e]")
	return TRUE

/proc/om_task_finish(datum/om/task/T)
	var/datum/om/rec/rec = T.actor?.om_rec
	om_task_release_claims(T)
	if(T.om_rec)
		om_teardown_rest(T)
	if(!rec)
		return
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
		if(!om_task_params_alive(T))
			om_task_cancel(T, "gone")
		else if(T.step_no)
			om_task_run_step(T, t)
		else
			om_task_complete(T)
	if(rec.owner)
		om_tasks_reschedule(rec)

/datum/om/behaviour/internal/tasks/on_wake(datum/E, changes)
	var/datum/om/rec/rec = E.om_rec
	for(var/datum/om/task/T as anything in rec?.tasks?.Copy())
		var/reason = null
		for(var/datum/om/check/C as anything in T.def.compiled_requires)
			reason = C.why_not(T.actor, T.target)
			if(!isnull(reason))
				break
		if(isnull(reason))
			for(var/spec in T.extra_requires)
				reason = om_why_not(spec, T.actor, T.target)
				if(!isnull(reason))
					break
		if(isnull(reason) && T.state == OM_TASK_RUNNING)
			reason = T.def.why_not_running(T)
		if(!isnull(reason))
			om_task_cancel(T, reason)

/proc/om_task_params_alive(datum/om/task/T)
	for(var/key in T.param_handles)
		if(!om_resolve(T.params[key]))
			return FALSE
	return TRUE

/// Runs the task's current step and acts on its result. Cancelling is always safe: no
/// proc is suspended inside a step.
/proc/om_task_run_step(datum/om/task/T, t)
	var/list/S = T.def.compiled_steps
	var/i = T.step_no * 2 - 1
	var/result
	try
		result = om_guarded_call(T.actor, S[i], list(T))
		if(result == OM_CALLEE_SLEPT)
			result = STEP_FAIL("slept")
	catch(var/exception/e)
		stack_trace("om task [T.def.name] step [S[i]]: [e]")
		result = STEP_FAIL("error")
	if(T.state != OM_TASK_RUNNING)
		return // the step cancelled or finished its own task
	if(islist(result))
		var/list/R = result
		switch(R[1])
			if(OM_STEP_REPEAT)
				T.ends_at = t + max(R[2], 0)
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

/// Drops every claim `T` holds (its target's and the extra ones).
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
	return om_task_start(E, /datum/om/task_def/hold, null, list("duration" = max(duration, 0), "on_end" = on_end))

/// See om_hold_busy().
/datum/om/task_def/hold
	name = "hold"
	claims_actor = TRUE

/datum/om/task_def/hold/on_complete(datum/om/task/T)
	var/on_end = T.params?["on_end"]
	if(on_end && !QDELETED(T.actor))
		call(T.actor, on_end)()

/datum/om/task_def/hold/on_cancel(datum/om/task/T, reason)
	on_complete(T)

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

/// Preset: a timed tool use. params: tool (TOOL_* quality), duration.
/datum/om/task_def/timed_tool
	name = "timed_tool"
	duration = 3 SECONDS
	claims = TRUE
	requires = list(/datum/om/check/adjacent, /datum/om/check/conscious, /datum/om/check/target_exists)

/datum/om/task_def/timed_tool/extra_requires(list/params)
	if(params?["tool"])
		return list(CHECK(/datum/om/check/holding_tool, params["tool"]))
	return null

/// A mob's timed work on a turf (spinning a web, laying eggs, building): it stays within one tile,
/// conscious; the claim keeps a second worker off the turf; death or deletion cancels it. The
/// actor's procs finish or clean up.
/datum/om/task_def/mob_work
	abstract_type = /datum/om/task_def/mob_work
	duration = 5 SECONDS
	claims = TRUE
	claims_actor = TRUE // the worker is busy: its AI stays still, and it can't start a second job
	requires = list(/datum/om/check/conscious, /datum/om/check/in_range, /datum/om/check/target_exists)

/datum/om/task_def/mob_work/spider_web
	name = "spider_web"
	complete_proc = /mob/living/simple_mob/animal/giant_spider/nurse/proc/web_done
	cancel_proc = /mob/living/simple_mob/animal/giant_spider/nurse/proc/work_interrupted

/datum/om/task_def/mob_work/spider_eggs
	name = "spider_eggs"
	complete_proc = /mob/living/simple_mob/animal/giant_spider/nurse/proc/eggs_done
	cancel_proc = /mob/living/simple_mob/animal/giant_spider/nurse/proc/work_interrupted

/datum/om/task_def/mob_work/ant_build
	name = "ant_build"
	complete_proc = /mob/living/simple_mob/animal/tyr/mineral_ants/proc/build_done
	cancel_proc = /mob/living/simple_mob/animal/tyr/mineral_ants/proc/build_interrupted

/datum/om/task_def/mob_work/cloak
	name = "cloak"
	duration = 1 SECOND
	claims = null
	requires = list(/datum/om/check/alive)
	complete_proc = /mob/living/simple_mob/animal/space/mouse_army/stealth/proc/cloak_done
	cancel_proc = /mob/living/simple_mob/animal/space/mouse_army/stealth/proc/cloak_interrupted
