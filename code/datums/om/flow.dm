// Object-model core: flows, multi-step actions as one type (doc/rewrite/object_model_core.md §11).
//
// A flow is an action made of steps (take time, ask someone, then act) declared as one type.
// Its typed vars are the state every step shares; each step is a proc on the flow; `requires`
// and valid() are re-checked before every step after the first, so no step re-checks by hand.
//
//	/datum/om/flow/leash
//		requires = list(/datum/om/check/adjacent)       // actor next to target, every step
//		var/obj/item/leash/leash
//
//	/datum/om/flow/leash/start()                        // step 1 (runs inside om_flow_start())
//		wait(3.5 SECONDS, PROC_REF(offer))
//
//	/datum/om/flow/leash/proc/offer()                    // step 2: after the timed action
//		om_ask(target, /datum/om/prompt/confirm/leash_offer, PROC_REF(accepted))
//
//	/datum/om/flow/leash/proc/accepted(datum/om/prompt/confirm/leash_offer/ask)   // step 3
//		leash.attach(target, actor)
//
//	om_flow_start(/datum/om/flow/leash, user, pet, leash = src)
//
// A step goes on with one of:
//   wait(duration, next, ...)   a timed action (actor on target, progress bar, cancelled on
//                               move etc. like any /datum/task/timed), then `next(task)`
//   om_ask(answerer, prompt, next, ...)   a typed prompt (ask.dm); `next(prompt)` gets the
//                               answer. The prompt's asker defaults to the actor and its
//                               subject to the target.
// A step that does neither ends the flow. A step that fails (the timed action is cancelled,
// the prompt is declined, cancelled or refused, a re-check fails, a datum in the state is
// deleted) calls ended(reason) once and the flow is dropped.
//
// Between steps the flow's datum vars are held as handles (never keeping anything alive); the
// flow itself is held by the task or the prompt it waits on, and nothing else.

/datum/om/flow
	var/name
	/// Who does it (a timed step's actor, a prompt's default asker).
	var/datum/actor
	/// What it's done to (a timed step's target, a prompt's default subject).
	var/datum/target
	/// Check specs (actor, target), re-checked before every step after the first.
	var/list/requires
	/// TRUE once the flow finished or failed.
	var/done = FALSE
	/// TRUE while a step waits on a task or a prompt.
	var/waiting = FALSE
	/// name -> wrapped handle of the state held between steps.
	var/list/parked
	/// State var names held strongly (not as handles) between steps: datums the flow made
	/// and nothing else owns.
	var/list/hold_strong

/// Step 1: runs inside om_flow_start(), after the requires hold.
/datum/om/flow/proc/start()
	return

/// The flow's own re-check before each step: null, or the reason to stop.
/datum/om/flow/proc/valid()
	return null

/// Called once when a step fails or a re-check stops the flow (not on a normal finish). The
/// state is resolved; a var whose datum was deleted is null.
/datum/om/flow/proc/ended(reason)
	return

/// Starts a flow: the om_flow_start() macro's body. `params` (var name -> value) set its vars.
/// Returns the flow, or a text reason it didn't start.
/proc/om_flow_begin(flow, datum/actor, datum/target, list/params)
	var/datum/om/flow/F = ispath(flow) ? new flow : flow
	if(!istype(F))
		CRASH("om_flow_start: [flow] is not a /datum/om/flow")
	for(var/key in params)
		if(!istext(key))
			CRASH("om_flow_start: [F.type] was given a positional argument ([key]); name it (var = value)")
		if(!(key in F.vars))
			CRASH("om_flow_start: [F.type] has no var [key]")
		F.vars[key] = params[key] // ALLOW(api): om_flow_start() named arguments: flow state by name
	F.actor = actor
	F.target = target
	var/reason = F.why_not_continuing()
	if(!isnull(reason))
		F.done = TRUE
		return reason
	F.run_step(TYPE_PROC_REF(/datum/om/flow, start), null) // by name: a raw proc path would skip the subtype override
	return F

/// Null while the flow may go on, else the reason: its actor or target is gone, a requires or valid() fails.
/datum/om/flow/proc/why_not_continuing()
	if(!actor || QDELETED(actor) || (target && QDELETED(target)))
		return "gone"
	for(var/check_spec in om_spec_list(requires))
		var/reason = om_why_not(check_spec, actor, target)
		if(!isnull(reason))
			return reason
	return valid()

/// A task or prompt finished: restore the state, re-check, and run the next step.
/datum/om/flow/proc/resume(next, datum/source)
	if(done)
		return
	if(!unpark())
		stop("gone")
		return
	var/reason = why_not_continuing()
	if(!isnull(reason))
		stop(reason)
		return
	run_step(next, source)

/datum/om/flow/proc/run_step(next, datum/source)
	waiting = FALSE
	try
		call(src, next)(source)
	catch(var/exception/e)
		stack_trace("om flow [type] step [next]: [e]")
		stop("error")
		return
	if(!waiting && !done)
		// The step went on to nothing: the flow is finished.
		done = TRUE
		om_handle_release(src)

/// Ends the flow early: ended(reason) runs once.
/datum/om/flow/proc/stop(reason = "stopped")
	if(done)
		return
	done = TRUE
	waiting = FALSE
	unpark()
	try
		ended(reason)
	catch(var/exception/e)
		stack_trace("om flow [type] ended([reason]): [e]")
	om_handle_release(src)

/// Holds the state as handles while a step waits. FALSE (the flow stops) if a datum is gone.
/datum/om/flow/proc/park()
	if(parked)
		return TRUE
	var/list/names = state_var_names(/datum/om/flow, list("actor", "target"))
	if(length(hold_strong))
		names = names - hold_strong
	parked = park_state(names)
	if(isnull(parked))
		stop("gone")
		return FALSE
	waiting = TRUE
	return TRUE

/datum/om/flow/proc/unpark()
	if(!parked)
		return TRUE
	var/list/held = parked
	parked = null
	return unpark_state(held)

/**
 * The step takes time: a timed action by the actor on the target (or `on`, instead), then
 * `next` runs with the task. The IGNORE_* `flags`, `max_distance`, `progress` and
 * `fail_message` are the timed action's. A cancelled action stops the flow with its reason.
 * Returns null, or the reason it didn't start (the flow is stopped then).
 */
/datum/om/flow/proc/wait(duration, next, flags = NONE, max_distance, progress = TRUE, fail_message, datum/on)
	var/datum/doer = actor
	var/datum/work_on = on || target
	if(work_on == doer)
		work_on = null
	if(!park())
		return "gone"
	var/result = task_launch(/datum/task/timed/flow_wait, doer, work_on, list(
		"duration" = duration,
		"flow" = src,
		"next_step" = next,
		"flags" = flags,
		"max_distance" = max_distance,
		"progress" = progress,
		"fail_message" = fail_message,
	), null)
	if(istext(result))
		stop(result)
		return result
	return null

/// A flow's timed step. The flow is held by this var (unheld: it's not a thing to watch).
/datum/task/timed/flow_wait
	name = "flow_wait"
	unheld = list("flow")
	var/datum/om/flow/flow
	var/next_step

/datum/task/timed/flow_wait/timed_done()
	var/datum/om/flow/F = flow
	flow = null
	F?.resume(next_step, src)

/datum/task/timed/flow_wait/timed_failed()
	..()
	var/datum/om/flow/F = flow
	flow = null
	F?.stop(reason || "interrupted")

// ---------------------------------------------------------------- question sequences
//
// om_ask_sequence(sequence, answerer, subject, steps = list(...), on_done = PROC_REF(cb), ...)
// asks a list of typed prompts one after another as a flow. `sequence` is
// /datum/om/flow/ask_sequence or a subtype declaring the sequence's typed state:
//
//	/datum/om/flow/ask_sequence/pin_value
//		var/type_name          // the answer of the prompt with key = "type_name"
//		var/value
//		var/datum/integrated_io/pin   // caller state, set by name; held as a handle between steps
//
//	om_ask_sequence(/datum/om/flow/ask_sequence/pin_value, user, null, steps = list(type_ask, PROC_REF(value_ask)), on_done = PROC_REF(value_entered), pin = src)
//
// Each step is a typed prompt (a type, or an instance with its vars set), null (skipped), or a
// proc on the owner called as (sequence) that returns a prompt, null to skip, or ASK_STOP to
// end there. Each answer (answer_value()) lands in the sequence var named by its prompt's
// `key` when the type declares one, else in `answers` under the key (default: the step's
// index), read with get(key); later steps can depend on earlier answers. A prompt whose
// `answerer` is set asks that mob instead (consent from the other party). An optional prompt's
// cancel stores null and goes on; any other cancel, a "no" or a failed re-check ends the
// sequence and calls on_stop on the owner as (sequence, reason). When the last step is
// answered, on_done runs on the owner as (sequence). The owner is the caller's src (`owner = X`
// instead); a /proc/ path is called globally with the same arguments.

/datum/om/flow/ask_sequence
	name = "ask_sequence"
	var/list/steps
	var/step_index = 0
	/// key -> answer, for keys the type declares no var for.
	var/list/answers
	/// What step procs, on_done and on_stop run on.
	var/datum/owner
	var/on_done
	var/on_stop

/// An answer so far, by key: the declared var, else from `answers`.
/datum/om/flow/ask_sequence/proc/get(key)
	if(answers && (key in answers))
		return answers[key]
	if(sequence_var(key))
		return vars[key]
	return null

/// Stores an answer: in the declared var named `key`, else in `answers`.
/datum/om/flow/ask_sequence/proc/put(key, value)
	if(sequence_var(key))
		vars[key] = value
		return
	LAZYINITLIST(answers)
	answers[key] = value

/// TRUE when `key` names a var the sequence type declares (its typed state).
/datum/om/flow/ask_sequence/proc/sequence_var(key)
	return istext(key) && (key in state_var_names(/datum/om/flow/ask_sequence, null))

/datum/om/flow/ask_sequence/start()
	next_step()

/datum/om/flow/ask_sequence/proc/call_owner(proc_ref, ...)
	var/list/call_args = list(src) + args.Copy(2)
	if(copytext("[proc_ref]", 1, 7) == "/proc/")
		return call(proc_ref)(arglist(call_args))
	if(!owner)
		return null
	return call(owner, proc_ref)(arglist(call_args))

/datum/om/flow/ask_sequence/proc/next_step()
	while(step_index < length(steps))
		step_index++
		var/step = steps[step_index]
		if(isnull(step))
			continue
		var/datum/om/prompt/P = step
		if(!istype(P) && !ispath(step, /datum/om/prompt))
			var/result = call_owner(step)
			if(result == ASK_STOP)
				stop("stopped")
				return
			if(isnull(result))
				continue
			P = result
		if(ispath(P))
			P = new P
		if(isnull(P.key))
			P.key = "[step_index]"
		var/mob/asked = P.answerer || actor
		if(!om_ask_begin(src, asked, P, PROC_REF(step_answered), null) && !done)
			stop("not asked")
		return
	if(on_done)
		call_owner(on_done)

/datum/om/flow/ask_sequence/proc/step_answered(datum/om/prompt/P)
	put(P.key, P.answer_value())
	next_step()

/datum/om/flow/ask_sequence/ended(reason)
	if(on_stop)
		call_owner(on_stop, reason)

/// om_ask_sequence()'s body. `owner` is the caller's src. Returns the flow, or the text reason
/// it didn't start.
/proc/om_ask_sequence_begin(datum/owner, sequence, mob/answerer, datum/subject, list/params)
	if(istype(answerer, /client))
		var/client/C = answerer
		answerer = C.mob
	var/datum/om/flow/ask_sequence/F = ispath(sequence) ? new sequence : sequence
	if(!istype(F))
		CRASH("om_ask_sequence: [sequence] is not a /datum/om/flow/ask_sequence")
	F.owner = owner
	return om_flow_begin(F, answerer, subject, params)
