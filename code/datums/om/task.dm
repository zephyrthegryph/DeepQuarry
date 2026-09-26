// Object-model core: tasks (doc/rewrite/object_model_core.md section I).
//
// A task is "actor does something to target for a while": started with
// om_task_start(), finished by a deadline (no polling), cancelled when its
// requires fail (re-checked only when their channels change on the actor or
// target), when an interrupted_by event reaches the actor, or when either
// end is deleted. Exclusivity is a claim relation (target_single, refuse):
// a second claimant gets the reason back. Legacy sleeping procs wait with
// AWAIT(task, timeout); the timeout is mandatory.

/datum/om/task_def
	abstract_type = /datum/om/task_def
	var/name
	/// Deciseconds, or FROM_VAR("x") read from the actor. params["duration"] overrides.
	var/duration = 0
	/// Relation type used to claim the target (TRUE: /datum/om/relation/claim). Null: no claim.
	var/claims
	/// Check specs (actor, target).
	var/list/requires
	/// Event types that cancel the task when emitted on the actor.
	var/list/interrupted_by
	/// Extra channels on the actor that re-check requires.
	var/interrupt_on = 0
	/// /type/proc/x called on the actor with the task (table rows).
	var/complete_proc
	var/cancel_proc

	var/list/compiled_requires
	var/requires_mask = 0
	var/claim_rel

/datum/om/task_def/proc/compile(datum/om/registry/reg)
	compiled_requires = list()
	for(var/spec in om_spec_list(requires))
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

/// Extra requirements from start parameters (presets such as timed_tool).
/datum/om/task_def/proc/extra_requires(list/params)
	return null

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
	var/datum/om/task/T = new
	T.def = def
	T.actor = actor
	T.target = target
	T.params = params
	T.extra_requires = extra
	if(def.claim_rel && target)
		var/claimed = om_link(T, target, def.claim_rel)
		if(istext(claimed))
			return claimed
		T.claim = claimed
	var/t = rec.sched.now()
	var/dur = params?["duration"]
	if(isnull(dur))
		dur = om_read(actor, def.duration)
	T.started_at = t
	T.ends_at = t + max(dur, 0)
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
	if(T.claim)
		var/datum/om/edge/edge = T.claim
		T.claim = null
		om_unlink_edge(edge)
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
		om_after(rec.owner, max(soonest - rec.sched.now(), 0), B)

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
		if(T.ends_at <= t)
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
		if(!isnull(reason))
			om_task_cancel(T, reason)

/// Legacy procs that must sleep: waits for `T` with a mandatory timeout
/// (deciseconds). TRUE if it completed.
/proc/om_await(datum/om/task/T, timeout)
	if(isnull(timeout) || timeout <= 0)
		CRASH("om_await() needs a timeout")
	if(!istype(T))
		return FALSE
	var/end = world.time + timeout
	while(T.state == OM_TASK_RUNNING && world.time < end)
		sleep(world.tick_lag)
	if(T.state == OM_TASK_RUNNING)
		om_task_cancel(T, "timed out")
	return T.state == OM_TASK_DONE

/// The claim relation: a target is claimed by at most one task.
/datum/om/relation/claim
	name = "claim"
	target_single = TRUE
	conflict = OM_REL_REFUSE

/datum/om/relation/claim/on_unlink(datum/source, datum/target, datum/om/edge/edge)
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
