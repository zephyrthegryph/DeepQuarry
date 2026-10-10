// Tasks: "an actor does something to a target for a while" (doc/rewrite/final_api.html section 3, "A timed player action"; section 9,
// "Waits"). The kernel record of a wait that legacy procedural code starts: an op declares the same thing with a wait() part (the
// pending op, code/engine/parts/run.dm), and a site that becomes an op stops starting a task. Moved here from the object model
// (code/datums/om/task.dm) when it was retired: the record, its claims and its timer are engine pieces now (after(), the published
// reads a pending op watches, the datum teardown), with nothing of the OM scheduler, its relations or its change channels.
//
// A task is declared as a type; its state lives on the task:
//
//	/datum/task/timed/absorb
//		duration = 15 SECONDS
//		complete_proc = /mob/living/proc/absorb_done   // called on the receiver with the task
//		var/obj/item/grab/grab                          // state, set from task_begin()'s params
//		var/stage
//
//	task_begin(/datum/task/timed/absorb, user, list(victim, "grab" = G, "stage" = 2), src)
//
// task_begin()'s params set the task's typed vars (a name the type doesn't
// declare is a CRASH). The receiver defaults to whichever of the caller's src, the target or the actor has the complete_proc. A
// complete_proc/cancel_proc of the task's own type runs on the task with no arguments and reads the state as its own vars.
//
// It finishes by its timer (after() on the actor's clock, keyed per task), or by its `steps`; it is cancelled when its check_reason()
// or why_not_running() refuses (asked again whenever a read it watches is published: the actor's place, hands, consciousness and
// stuns, the target's place), or when the actor, the target or any datum in its state is deleted. Exclusivity is a claim: a target
// is claimed by at most one task (`claims`), and a worker that `claims_actor` (or a datum given as `busy`) is busy while it runs.

/// Every task type's compiled prototype: type -> /datum/task, built on first use.
GLOBAL_LIST_EMPTY(task_specs)
/// REF(target) -> the running task that claims it exclusively.
GLOBAL_LIST_EMPTY(task_target_claims)
/// REF(datum) -> the running task that holds it busy (its actor, a tool, a bot or machine).
GLOBAL_LIST_EMPTY(task_busy_claims)
/// Serial of the next task (its timer key).
GLOBAL_VAR_INIT(task_serial, 0)

/datum/task
	abstract_type = /datum/task
	// ---- declaration (the type's vars; named arguments may override any of them per run)
	var/name
	/// Deciseconds, or FROM_VAR("x") read from the actor.
	var/duration = 0
	/// TRUE: the target is claimed while the task runs (a second claiming task is refused).
	var/claims = FALSE
	/// TRUE: the actor is busy while the task runs (task_claiming()), and a second actor-claiming task is refused.
	var/claims_actor = FALSE
	/// Steps: list(/type/proc/x = delay, ...), in order. A step proc of the task's own type runs on the task with no arguments; any other
	/// runs on the receiver with the task. It returns STEP_NEXT, STEP_REPEAT(d), STEP_DONE or STEP_FAIL(reason). Past the last step the
	/// task completes. With steps, `duration` is unused.
	var/list/steps
	/// A proc called on the receiver with the task when it completes / is cancelled (a /proc/ path is called globally with the task).
	var/complete_proc
	var/cancel_proc
	/// TRUE: a zero duration completes at once, inside task_begin() (timed actions).
	var/instant_at_zero = FALSE
	/// State vars that are not held (a beam or effect that ends itself): deleting what they hold doesn't cancel the task.
	var/list/unheld

	// ---- run state
	var/datum/actor
	var/datum/target
	/// Whose complete_proc/cancel_proc run (the item or machine doing the work). Default: the actor.
	var/datum/receiver
	EXPIRY_DECLARE(started_at)
	EXPIRY_DECLARE(ends_at)
	var/state = TASK_RUNNING
	var/reason
	var/serial = 0
	/// Index of the next step (steps tasks), 1-based.
	var/step_no = 0
	/// REF texts of what this task claims busy (task_claim()), released with it.
	var/list/busy_refs
	/// TRUE while this task holds the exclusive claim on its target.
	var/claimed_target = FALSE
	/// State var name -> REF of the datum it held at the start: deleting one clears the var and cancels the task.
	var/list/held_state
	/// Every datum the task is registered on (rx_state.tasks_on): its deletion reaches datum_gone().
	var/list/ends
	/// The published (entity, key) reads the task re-checks on, as list(datum, key) rows.
	var/list/watching
	var/rechecking = FALSE

/// Extra start-time refusal: null, or the reason the task can't start or must stop (asked again on every watched read).
/datum/task/proc/check_reason()
	return null

/// Called once the task is claimed and its state set, before it is scheduled. Null, or a reason to refuse the start.
/datum/task/proc/on_starting()
	return null

/// Called once the task is running (UI, notices).
/datum/task/proc/on_started()
	return

/// A steps task's next step is due in `delay` (a repeat, or the next step).
/datum/task/proc/on_rescheduled(delay)
	return

/// Per-run conditions (the actor has not moved since the start, ...), asked on every watched read: null, or the reason to cancel.
/datum/task/proc/why_not_running()
	return null

/// The (entity, key) reads the task re-checks on. A timed action adds the actor's place, hands and consciousness.
/datum/task/proc/watched_reads()
	return null

/datum/task/proc/on_complete()
	if(complete_proc)
		task_call(src, complete_proc)

/datum/task/proc/on_cancel(reason)
	if(cancel_proc)
		task_call(src, cancel_proc)

/// The compiled prototype of `type`: its steps flattened (proc, delay, proc, delay...). Built once per type.
/proc/task_spec(type)
	var/datum/task/spec = GLOB.task_specs[type]
	if(spec)
		return spec
	spec = new type
	if(length(spec.steps))
		var/list/flat = list()
		for(var/step_proc in spec.steps)
			var/delay = spec.steps[step_proc]
			if(!isnum(delay) || delay < 0)
				stack_trace("task [type]: step [step_proc] needs a delay")
				delay = 0
			flat += list(step_proc, delay)
		spec.steps = flat
	GLOB.task_specs[type] = spec
	return spec

/// Calls `proc_ref` with the task: a /proc/ path globally, a proc of the task's own type on the task with no arguments, else on the
/// receiver (skipped once the receiver is gone).
/proc/task_call(datum/task/T, proc_ref)
	if(copytext("[proc_ref]", 1, 7) == "/proc/")
		return call(proc_ref)(T)
	if(task_own_proc(T, proc_ref))
		return call(T, proc_ref)()
	var/datum/R = T.receiver
	if(!R || QDELETED(R))
		return null
	return call(R, proc_ref)(T)

/// TRUE when `proc_ref` is a proc of the task's own type (a step or callback that runs on the task).
/proc/task_own_proc(datum/task/T, proc_ref)
	var/text = "[proc_ref]"
	var/at = findtext(text, "/proc/")
	if(!at)
		at = findtext(text, "/verb/")
	if(at <= 1)
		return FALSE
	var/owner = text2path(copytext(text, 1, at))
	return owner && istype(T, owner)

/**
 * Starts task `type` with `actor` working on the target (the first positional entry of `rest`, optional). The named entries of `rest`
 * set the run's vars: its state, and any declaration var to override (duration, receiver, ...). Every datum among them is held: deleting it cancels the task. `starter` is the caller's src. Returns the task, or a text reason
 * it can't start.
 */
/proc/task_begin(type, datum/actor, list/rest, datum/starter)
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
			CRASH("task [type] was given a positional argument ([entry]); name it (var = value)")
	return task_launch(type, actor, target, params, starter)

/// Starts a task from a built params list (var name -> value): task_begin() and the helpers that build their own (use_tool()).
/proc/task_launch(type, datum/actor, datum/target, list/params, datum/starter)
	if(!ispath(type, /datum/task))
		CRASH("unknown task [type]")
	var/datum/task/spec = task_spec(type)
	if(!actor || !own_guard(actor, target, "task [type]")) // the one teardown guard (guard.dm)
		return "gone"
	var/datum/task/T = new type
	T.steps = spec.steps
	T.actor = actor // ALLOW(ownership): a task holds its actor until it ends; the actor's deletion cancels it (datum_gone())
	T.target = target // ALLOW(ownership): a task holds its target until it ends; the target's deletion cancels it (datum_gone())
	for(var/key in params)
		if(!istext(key))
			CRASH("task [type] was given a positional argument ([key]); name it (var = value)")
		if(!(key in T.vars))
			CRASH("task [type] has no var [key]")
		var/value = params[key]
		var/datum/D = value
		if(isdatum(D) && QDELETED(D))
			return "gone"
		T.vars[key] = value // ALLOW(api): task_begin() params set the task's state by name
	if(!T.receiver)
		T.receiver = T.pick_receiver(starter) // ALLOW(ownership): the task kernel records who the task acts for; tasks end when that entity goes
	if(isnull(T.duration))
		T.duration = 0
	else if(!isnum(T.duration))
		T.duration = task_read(actor, T.duration)
#ifdef UNIT_TESTS
	if(T.instant_at_zero && GLOB.timed_actions_instant)
		T.duration = 0
#endif
	var/refused = T.check_reason()
	if(!isnull(refused))
		return refused
	if(T.instant_at_zero && T.duration <= 0 && !length(T.steps))
		return task_run_instantly(T)
	refused = task_claim_all(T)
	if(isnull(refused))
		refused = T.on_starting()
	if(!isnull(refused))
		T.state = TASK_CANCELLED
		task_release(T)
		return refused
	T.serial = ++GLOB.task_serial
	EXPIRY_SET(T, started_at, 0, null)
	if(length(T.steps))
		T.step_no = 1
		task_arm(T, T.steps[2])
	else
		task_arm(T, max(T.duration, 0))
	task_watch_begin(T)
	T.on_started()
	return T

/// FROM_VAR("x") read from the holder (a task's duration), anything else as it is.
/proc/task_read(datum/holder, spec)
	if(!islist(spec))
		return spec
	var/list/L = spec
	if(length(L) == 2 && L[1] == "var")
		return holder ? holder.vars[L[2]] : null
	return spec

/// The receiver of a task started without one: the first of `starter` (the caller's src), the target and the actor that has the task's
/// complete_proc, cancel_proc, check_proc or a step proc. Otherwise the starter (the caller asked for the work), else the actor.
/datum/task/proc/pick_receiver(datum/starter)
	var/list/procs = list(complete_proc, cancel_proc)
	procs += additional_receiver_procs()
	for(var/i in 1 to length(steps) step 2)
		procs += steps[i]
	for(var/proc_ref in procs)
		if(!proc_ref || copytext("[proc_ref]", 1, 7) == "/proc/" || task_own_proc(src, proc_ref))
			continue
		for(var/datum/candidate as anything in list(starter, target, actor))
			if(candidate && !QDELETED(candidate) && proc_fits(candidate, proc_ref))
				return candidate
	if(starter && !QDELETED(starter))
		return starter
	return actor

/// TRUE when `proc_ref` (a proc path, or a PROC_REF() name) can be called on `D`.
/datum/task/proc/proc_fits(datum/D, proc_ref)
	var/text = "[proc_ref]"
	var/at = findtext(text, "/proc/")
	if(!at)
		at = findtext(text, "/verb/")
	if(at > 1)
		var/owner = text2path(copytext(text, 1, at))
		return owner && istype(D, owner)
	return hascall(D, text)

/// A zero-duration task that completes at once (timed actions with no delay): its checks run, then on_complete, or on_cancel with the
/// reason (which is returned).
/proc/task_run_instantly(datum/task/T)
	var/reason = T.why_not_running()
	if(!isnull(reason))
		T.state = TASK_CANCELLED
		T.reason = reason
		T.on_cancel(reason)
		return reason
	T.state = TASK_DONE
	T.on_complete()
	return T

// ---- claims and holds ----

/// Claims the target (when the type claims), the actor (claims_actor) and registers the task on every datum in its state, so its
/// deletion ends the task. Null, or the reason it can't.
/proc/task_claim_all(datum/task/T)
	var/datum/target = T.target
	var/datum/actor = T.actor
	if(T.claims && target)
		var/datum/task/holder = task_claiming_target(target)
		if(holder && holder != T)
			return "[target] is in use"
		GLOB.task_target_claims["[REF(target)]"] = T
		T.claimed_target = TRUE
	if(T.claims_actor)
		var/claimed = task_claim(T, actor)
		if(istext(claimed))
			return claimed
	task_register_on(T, actor)
	if(target && target != actor)
		task_register_on(T, target)
	for(var/name in task_state_vars(T.type))
		var/datum/D = T.vars[name]
		if(!isdatum(D) || D == actor || D == target || D == T)
			continue
		LAZYSET(T.held_state, name, REF(D))
		task_register_on(T, D)
	return null

/// The task is told when `D` is deleted (datum_gone(), from the datum teardown).
/proc/task_register_on(datum/task/T, datum/D)
	if(!isdatum(D) || QDELETED(D) || (D in T.ends))
		return
	LAZYADD(T.ends, D)
	LAZYADD(rx_of(D).tasks_on, T)

/// The vars a task type adds for its state (and `receiver`): the ones held while it runs.
/proc/task_state_vars(path)
	var/static/list/by_type = list()
	var/list/names = by_type[path]
	if(names)
		return names
	var/static/list/base_vars
	if(!base_vars)
		base_vars = list()
		var/datum/task/base = new /datum/task
		for(var/name in base.vars)
			base_vars[name] = TRUE
	names = list("receiver")
	var/datum/task/proto = new path
	for(var/name in proto.vars)
		if(!base_vars[name] && !(name in proto.unheld))
			names += name
	by_type[path] = names
	return names

/// `T` also claims `D` (its actor, the tool it works with, the machine or bot it runs): `D` is busy until `T` completes, is cancelled or
/// either is deleted. Returns TRUE, or a text reason when something else already holds `D` busy.
/proc/task_claim(datum/task/T, datum/D)
	if(!D || T.state != TASK_RUNNING)
		return "invalid"
	var/key = "[REF(D)]"
	var/datum/task/holder = GLOB.task_busy_claims[key]
	if(holder && holder != T && holder.state == TASK_RUNNING)
		return "[D] is busy"
	GLOB.task_busy_claims[key] = T
	LAZYOR(T.busy_refs, key)
	task_register_on(T, D)
	return TRUE

/// Drops every claim, hold and watch of `T`.
/proc/task_release(datum/task/T)
	if(T.claimed_target && T.target)
		var/key = "[REF(T.target)]"
		if(GLOB.task_target_claims[key] == T)
			GLOB.task_target_claims -= key
	T.claimed_target = FALSE
	for(var/key in T.busy_refs)
		if(GLOB.task_busy_claims[key] == T)
			GLOB.task_busy_claims -= key
	T.busy_refs = null
	for(var/datum/D as anything in T.ends)
		var/datum/rx_state/S = D.rx
		if(S)
			LAZYREMOVE(S.tasks_on, T)
	T.ends = null
	task_watch_end(T)
	if(T.serial && T.actor && !QDELETED(T.actor))
		cancel_after(T.actor, "task:[T.serial]")

/// One of the datums the task names was deleted: the actor or target ends it; a datum in its state is cleared and ends it.
/datum/task/proc/datum_gone(datum/D)
	if(state != TASK_RUNNING)
		return
	for(var/name in held_state)
		if(held_state[name] == REF(D) && vars[name] == D)
			vars[name] = null // ALLOW(api): a held state var is cleared by name so on_cancel never sees a deleted datum
	if(D == target)
		task_cancel(src, "target gone")
	else
		task_cancel(src, "gone")

/// The running task that claims `D` exclusively as its target, or null.
/proc/task_claiming_target(datum/D)
	var/datum/task/T = GLOB.task_target_claims["[REF(D)]"]
	if(T && (T.state != TASK_RUNNING || T.target != D))
		GLOB.task_target_claims -= "[REF(D)]"
		return null
	return T

/// The running task that claims `D`, or null. This is what "busy" means: a bot, a tool or a machine is busy while a task claims it.
/proc/task_claiming(datum/D)
	if(!D)
		return null
	var/datum/task/T = GLOB.task_busy_claims["[REF(D)]"]
	if(T && T.state == TASK_RUNNING)
		return T
	return task_claiming_target(D)

/// Cancels the task that claims `D`, if any (it stopped early). TRUE if one was cancelled.
/proc/task_release_busy(datum/D, reason = "released")
	var/datum/task/T = task_claiming(D)
	return T ? task_cancel(T, reason) : FALSE

/// Holds `E` busy for `duration` (an action whose continuation is a timer, not a task step): a task on `E` claiming it, done at the end.
/// `on_end`, a proc on `E`, runs when the hold ends (done or cancelled). Returns the task, or a reason (already busy).
/proc/task_hold_busy(datum/E, duration, on_end)
	return task_launch(/datum/task/hold, E, null, list("duration" = max(duration, 0), "complete_proc" = on_end, "cancel_proc" = on_end), null)

/// See task_hold_busy().
/datum/task/hold
	name = "hold"
	claims_actor = TRUE

/datum/task/hold/on_complete()
	if(complete_proc && !QDELETED(actor))
		call(actor, complete_proc)()

/datum/task/hold/on_cancel(reason)
	on_complete()

// ---- time ----

/// The task's timer: `delay` deciseconds on the actor's clock.
/proc/task_arm(datum/task/T, delay)
	EXPIRY_SET(T, ends_at, delay, null)
	after(T.actor, delay, GLOBAL_PROC_REF(task_due), key = "task:[T.serial]", with = list(T))

/// The task's timer went off: the current step runs, or the task completes.
/proc/task_due(datum/task/T)
	if(!T || T.state != TASK_RUNNING)
		return
	if(T.step_no)
		task_run_step(T)
	else
		task_complete(T)

/// Runs the task's current step and acts on its result. Cancelling is always safe: no proc is suspended inside a step.
/proc/task_run_step(datum/task/T)
	var/list/S = T.steps
	var/i = T.step_no * 2 - 1
	var/result
	try
		var/step_proc = S[i]
		// A step that sleeps is cut loose and fails its task (it must not stall the kernel).
		if(task_own_proc(T, step_proc))
			result = deferred_guarded_call(T, step_proc, null)
		else if(QDELETED(T.receiver))
			result = STEP_FAIL("gone")
		else
			result = deferred_guarded_call(T.receiver, step_proc, list(T))
		if(result == OM_CALLEE_SLEPT)
			result = STEP_FAIL("slept")
	catch(var/exception/e)
		dq_report_caught(e, "task [T.name || T.type] step [S[i]]")
		result = STEP_FAIL("error")
	if(T.state != TASK_RUNNING)
		return // the step cancelled or finished its own task
	if(islist(result))
		var/list/R = result
		switch(R[1])
			if(TASK_STEP_REPEAT)
				task_arm(T, max(R[2], 0))
				T.on_rescheduled(max(R[2], 0))
				return
			if(TASK_STEP_FAIL)
				task_cancel(T, R[2] || "failed")
				return
	if(result == STEP_DONE)
		task_complete(T)
		return
	// STEP_NEXT (or null).
	T.step_no++
	if(T.step_no * 2 > length(S))
		task_complete(T)
		return
	task_arm(T, S[T.step_no * 2])
	T.on_rescheduled(S[T.step_no * 2])

// ---- ending ----

/proc/task_cancel(datum/task/T, reason = "cancelled")
	if(T.state != TASK_RUNNING)
		return FALSE
	T.state = TASK_CANCELLED
	T.reason = reason
	task_release(T)
	try
		T.on_cancel(reason)
	catch(var/exception/e)
		dq_report_caught(e, "task [T.name || T.type] on_cancel")
	return TRUE

/proc/task_complete(datum/task/T)
	if(T.state != TASK_RUNNING)
		return FALSE
	T.state = TASK_DONE
	task_release(T)
	try
		T.on_complete()
	catch(var/exception/e)
		dq_report_caught(e, "task [T.name || T.type] on_complete")
	return TRUE

// ---- re-checks: the reads a running task watches ----
//
// A running task subscribes to the published reads its checks depend on (watched_reads()), through the same index a pending op uses
// (GLOB.op_watchers, op_reads_changed()): the moment one is published the task asks check_reason() and why_not_running() again and is
// cancelled if either refuses. Nothing polls.

/proc/task_watch_begin(datum/task/T)
	var/list/pairs = T.watched_reads()
	if(!length(pairs))
		return
	T.watching = pairs
	for(var/list/pair as anything in pairs)
		var/datum/watched = pair[1]
		if(!isdatum(watched) || QDELETED(watched))
			continue
		rx_watch_adjust(watched, pair[2], 1)
		var/index = "[REF(watched)]|[pair[2]]"
		var/list/on = GLOB.op_watchers[index]
		if(!on)
			on = list()
			GLOB.op_watchers[index] = on
		on |= T

/proc/task_watch_end(datum/task/T)
	for(var/list/pair as anything in T.watching)
		var/datum/watched = pair[1]
		if(isdatum(watched) && !QDELETED(watched))
			rx_watch_adjust(watched, pair[2], -1)
		var/index = "[REF(watched)]|[pair[2]]"
		var/list/on = GLOB.op_watchers[index]
		if(!on)
			continue
		on -= T
		if(!length(on))
			GLOB.op_watchers -= index
	T.watching = null

/// A read the task watches was published: its checks run again now.
/datum/task/proc/reads_changed()
	if(state != TASK_RUNNING || rechecking)
		return
	rechecking = TRUE
	var/why = check_reason()
	if(isnull(why))
		why = why_not_running()
	rechecking = FALSE
	if(!isnull(why))
		task_cancel(src, why)

/// Policy-specific checks participate in automatic receiver selection.
/datum/task/proc/additional_receiver_procs()
	return null
