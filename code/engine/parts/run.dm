// The op engine (doc/rewrite/final_api.html, section 9 "Four stages", "Do is a commit", "Waiting and asking", "The pipeline, every time"; section 13
// "Requests, prompts and workflows (X3)"; section 19 "E2, parts").
//
// An op runs through four stages, always in this order:
//
//   Match    is this what the actor is doing?   silent on failure: the op is not a candidate (resolve.dm).
//   Require  is it allowed now?                 needs(), at(), the require half of costs, the pre-checks of the actions the effects will start.
//                                               The reason is shown and the input does not fall through. Re-checked after the wait and right before Do.
//   Wait     how long does it take?             wait(t) and every asks() and confirms(), in declaration order: the op's workflow. Cancelled when a
//                                               keep breaks or a re-checked requirement now refuses.
//   Do       what happens?                      reserve the costs, chance(), the effects in order (each reports OP_*), commit or release, feedback.
//
// Do is a commit: Require and the pre-checks of the world actions the effects start run before irreversible work; resources are reserved after the
// last answer, committed after the effects succeed and released on refusal or failure; the outcome is the first effect that is not OK, else
// committed; only a committed op whose roll succeeded publishes its op_done notice, its messages and its log line; there is no general rollback.
//
// While an op waits it holds its holder, target, held item and actor through relations (deleting one cancels it, with feedback); from the
// reservation until it ends the act holds them strongly. perform_op() and the test driver's forms return a plain /datum/op_result that the engine fills
// as the op ends; an op still waiting comes back with a null outcome and the same record is filled in later.

/datum/act/op
	/// The op's compiled plan and the binding it came through.
	var/datum/op_plan/oplan
	var/datum/entry/part/bind/binding
	/// The /datum/op_result the engine fills as the op ends.
	var/datum/op_result/result
	/// Reservations made for the op, in order.
	var/list/reservations
	/// Extra log text effects add (act_log()).
	var/list/log_lines
	/// The pending op while it waits.
	var/datum/pending_op/pending
	/// The validated UI or topic arguments, in the order the op declared them (they follow the context into a handler).
	var/list/ordered_args
	/// TRUE once the op passed Match and Require and started its Wait or Do: refusals after this point are logged.
	var/started = FALSE
	/// The slot units a put_in() moved, and the reservation they came from.
	var/list/moved_units
	/// TRUE once an effect answered OP_PASS: the op commits and the click goes on to the next candidate.
	var/passed = FALSE

/// A handler reads the value of a captured field here, never off the live holder (resume policies: CAPTURE the snapshot, LATEST the live value).
/datum/act/op/proc/captured(name)
	return LAZYACCESS(captured_values, name)

/// The window action that reached the op (a ui_act("*") op answers many: the embedded controller's program command), or null for any other input.
/datum/act/op/proc/window_action()
	return LAZYACCESS(src.args, OP_UI_WINDOW_ACTION)

/// The datum whose window forwarded the button that reached the op (interface(forwards =): a remote console's panel), or null when the button
/// was the holder's own window's.
/// The tgui window the button was pressed in, or null (a driver-built press, any other input).
/datum/act/op/proc/window_ui()
	RETURN_TYPE(/datum)
	return LAZYACCESS(src.args, OP_UI_TGUI)

/datum/act/op/proc/window_forwarder()
	return LAZYACCESS(src.args, OP_UI_FORWARDED_BY)

/// The answer of the workflow step called `name` (default: the kind's last path segment): the design's A.step("name"), spelled step_answer() because `step` is a DM keyword.
/datum/act/op/proc/step_answer(name)
	return LAZYACCESS(step_answers, name)

/// The value the step called `name` was answered with (the prompt's `value`), or null when that step was not asked or not answered.
/datum/act/op/proc/step_value(name)
	var/datum/prompt/P = LAZYACCESS(step_answers, name)
	return P?.value

/datum/act/op
	/// step name -> the answered request (a handler reads it as A.step("name")).
	var/list/step_answers

/// An effect adds a line to the op's log text.
/proc/act_log(datum/act/op/A, text)
	LAZYADD(A.log_lines, text)

// ---- perform_op and its relatives ----

/// The final perform_op(): runs the op named `key` on `target` through whichever binding accepts `origin` (default ORIGIN_AI) and returns a
/// /datum/op_result. An op that still waits comes back with a null outcome and the same record is filled in later. `authority` is an AUTH_*
/// (AUTH_ADMIN with an authority datum for an admin call); `trace` prints the resolution. The legacy perform_op(user, target, text, route, held)
/// keeps its own implementation for the ops that still are legacy cap_op() entries.
/proc/perform_op(mob/actor, datum/target, key, held_or_route = null, origin = ORIGIN_AI, authority = null, trace = FALSE)
	// The legacy shape names a ROUTE_* text as the fourth argument.
	if(!isnull(held_or_route) && !isobj(held_or_route))
		return operation_compatibility().perform(actor, target, key, held_or_route, isobj(origin) ? origin : null)
	var/obj/held = held_or_route
	if(!isatom(target) && !isdatum(target))
		return null
	if(!istext(key) || !op_known_anywhere(actor, target, held, key))
		// a legacy op named by its key or text keeps running the legacy way
		if(isatom(target) && istext(key) && operation_compatibility().named(actor, target, key))
			return operation_compatibility().perform(actor, target, key, ROUTE_PHYSICAL, held)
		var/datum/op_result/unknown = new
		unknown.key = key
		unknown.origin = origin
		unknown.outcome = ACT_REFUSED
		unknown.reason = /datum/msg/op/unknown
		TEST_REC_OUTCOME(key, ACT_REFUSED, unknown.reason, actor) // an AI behaviour calls ops speculatively: an op nobody here has is a refusal with a reason, not an error
		log_game("perform_op(): [target?.type] has no op \"[key]\" (refused: no such op here)")
		return unknown
	return op_perform_by_key(actor, target, held, key, origin, authority || AUTH_PHYSICAL, trace)

/// Does the target, the held item or the actor have an op of that key?
/proc/op_known_anywhere(mob/actor, datum/target, obj/held, key)
	var/list/activation_out = list()
	if(op_plan_for(target, key, activation_out))
		return TRUE
	if(held && op_plan_for(held, key, activation_out))
		return TRUE
	if(actor && op_plan_for(actor, key, activation_out))
		return TRUE
	return FALSE

/// Resolution by key, then the run.
/proc/op_perform_by_key(mob/actor, atom/target, obj/held, key, origin, authority, trace, list/arg_values = null)
	RETURN_TYPE(/datum/op_result)
	OP_PURE_GUARD("perform_op(\"[key]\") on [target?.type] was run")
	var/datum/op_resolution/R = op_resolve(actor, target, held, origin, authority, null, key, FALSE)
	if(trace)
		op_trace_print(R, "perform_op [key]")
	var/datum/op_cand/winner = op_resolution_winner(R)
	if(!winner)
		var/datum/op_result/refused = new
		refused.key = key
		refused.origin = origin
		refused.outcome = ACT_REFUSED
		refused.reason = op_resolution_refusal(R)
		op_tell(actor, refused.reason)
		TEST_REC_OUTCOME(key, ACT_REFUSED, refused.reason, actor)
		return refused
	return op_begin(winner, R, arg_values, trace)

/// The refusal reason of a resolution with no runnable candidate: the best near-miss's, else why a gate dropped them.
/proc/op_resolution_refusal(datum/op_resolution/R)
	if(R.gate_reason)
		return R.gate_reason
	if(R.near_miss)
		return R.near_miss.dropped_reason || /datum/msg/op/no_binding
	for(var/datum/op_cand/C as anything in R.all)
		if(C.dropped_by == GATE_MATCH && !length(C.dropped_reason))
			continue
		if(C.dropped_reason)
			return C.dropped_reason
	return /datum/msg/op/not_available

/// perform_intent(actor, target, INTENT_X, held): the same path through the ops with a physical binding; returns the key of the op that ran,
/// or null.
/proc/perform_intent(mob/actor, atom/target, intent, obj/held)
	var/datum/op_resolution/R = op_resolve(actor, target, held, ORIGIN_AI, AUTH_AI | AUTH_PHYSICAL, null, null, FALSE)
	for(var/datum/op_cand/C as anything in R.all)
		if(C.dropped_by || !C.binding.physical())
			continue
		if(!(intent in op_answers(C.oplan, C.binding)))
			continue
		if(!op_cand_when(R, C))
			continue
		op_begin(C, R, null, FALSE)
		return C.oplan.key
	return null

/// Prints a resolution's trace.
/proc/op_trace_print(datum/op_resolution/R, header)
	log_world("[header]: [jointext(op_explain_lines(R), "\n")]")

/// Tells the actor `reason` (a /datum/msg type or text), if there is an actor that can hear.
/proc/op_tell(mob/actor, reason)
	if(!actor || QDELETED(actor) || isnull(reason))
		return
	OP_PURE_GUARD("the actor was told something")
	var/text = reason_text(reason)
	if(text)
		actor.op_notify(text)

// ---- starting an op ----

/// The act and result of a candidate that won: Require, then Wait or Do. Returns the op's /datum/op_result (null outcome while it waits).
/proc/op_begin(datum/op_cand/C, datum/op_resolution/R, list/arg_values = null, trace = FALSE)
	RETURN_TYPE(/datum/op_result)
	var/mob/actor = R.actor
	var/datum/op_result/result = new
	result.key = C.oplan.key
	result.origin = R.origin
	if(C.legacy)
		return op_run_compatibility(C, R, result)
	// A second input while busy: the actor's policy decides. The game acting for itself (ORIGIN_SYSTEM) neither waits on the actor's own wait nor
	// ends it: it is not the actor deciding something else.
	if(actor && R.origin != ORIGIN_SYSTEM)
		var/datum/pending_op/busy = op_pending_of(actor)
		if(busy)
			if(R.origin in list(ORIGIN_AI, ORIGIN_SYSTEM))
				result.outcome = ACT_REFUSED
				result.reason = /datum/msg/op/busy
				TEST_REC_OUTCOME(C.oplan.key, ACT_REFUSED, result.reason, actor)
				return result
			busy.cancel(/datum/msg/op/stopped)
	var/datum/act/op/A = op_act_for(C, actor, R.target, R.held, R.origin, R.authority)
	A.oplan = C.oplan // ALLOW(ownership): a pooled transient: reset on release
	A.binding = C.binding // ALLOW(ownership): a pooled transient: reset on release
	A.result = result // ALLOW(ownership): a pooled transient: reset on release
	A.held_name = R.held ? "[R.held]" : null
	A.target_name = A.target ? "[A.target]" : null
	A.actor_name = actor ? "[actor]" : null
	// UI and topic arguments cross the schema boundary before anything else.
	if(!isnull(arg_values))
		A.args = arg_values
		A.ordered_args = op_ordered_args(C.oplan, C.binding, arg_values)
	// Match is re-checked here too (a perform_op by key meets it for the first time): a failed when() refuses by key.
	for(var/cond in C.oplan.conds)
		if(!op_cond(A, cond))
			return op_end(A, ACT_REFUSED, /datum/msg/op/not_available)
	var/why = op_require_reason(A, C.oplan, C.binding)
	if(why)
		return op_end(A, ACT_REFUSED, why)
	if(C.oplan.claims && length(C.oplan.steps) && op_claimed(A.target))
		return op_end(A, ACT_REFUSED, /datum/msg/op/claimed)
	A.started = TRUE
	if(length(C.oplan.steps))
		return op_wait_begin(A, C)
	return op_do(A)

/// The arguments of an op in the order its ui_act() or topic() binding declared them.
/proc/op_ordered_args(datum/op_plan/P, datum/entry/part/bind/B, list/arg_values)
	. = list()
	var/list/declared = (B.bind_kind == BIND_TOPIC) ? P.topic_args : P.ui_args
	for(var/datum/entry/part/ui_arg/arg_part as anything in declared)
		. += list(arg_values[arg_part.args["name"]])

// ---- Require ----

/// The reason Require refuses the op now, or null: the implicit req_capable() of a physical binding, the bay, needs(), the require half of costs
/// and the pre-checks of the actions the effects start. Nothing is reserved and nothing is written.
/proc/op_require_reason(datum/act/op/A, datum/op_plan/P, datum/entry/part/bind/B)
	op_pure_begin()
	. = op_require_reason_inner(A, P, B)
	op_pure_end()

/// What a hand() op on this atom must pass first, as a refusal reason (a /datum/msg type), or null. The base asks nothing; a machine asks its hand gate.
/atom/proc/op_hand_refusal(datum/act/op/A)
	return null

/proc/op_require_reason_inner(datum/act/op/A, datum/op_plan/P, datum/entry/part/bind/B)
	if(B && B.physical() && A.origin != ORIGIN_SYSTEM && !(A.authority & AUTH_ADMIN))
		var/mob/L = A.actor
		if(L?.op_uses_actor_stats() && !stat_value(L, STAT_CAN_ACT) && !LAZYACCESS(P.selects, "capable_ignoring"))
			return stat_hold_reason(L, STAT_CAN_ACT) || /datum/msg/req_not_capable
	// The hand gate: a hand() op needs a hand that works (conscious, not stunned), and on a machine what the old attack_hand passed first (power,
	// posture, dexterity) unless it says ungated(): the old interactions that never called ..() (INTERACT_HAND_UNGATED) skipped hand_gate(), not the actor.
	// A tk() op has the actor half of it and never the machine half: a mind has no posture or dexterity, and the old attack_tk never ran hand_gate().
	if(B && (B.bind_kind == BIND_HAND || B.bind_kind == BIND_TK) && A.origin != ORIGIN_SYSTEM && !(A.authority & AUTH_ADMIN))
		var/mob/toucher = A.actor
		if(toucher && !toucher.op_hand_capable())
			return /datum/msg/req_not_capable
		var/atom/gated = A.target
		if(B.bind_kind == BIND_HAND && istype(gated) && !LAZYACCESS(P.selects, "ungated"))
			var/why_hand = gated.op_hand_refusal(A)
			if(why_hand)
				return why_hand
	if(P.space)
		var/atom/T = A.target
		var/why_space = istype(T) ? T.space_reason(P.space, A.authority, A.actor) : null
		if(why_space)
			return why_space
	for(var/requirement in P.needs)
		if(!op_req_holds(A, requirement))
			return op_req_refusal(A, requirement)
	for(var/id in P.cost_order)
		var/datum/resource/RS = resource_of(text2num(id))
		var/n = op_cost_amount(P, B, text2num(id), A)
		if(RS && RS.available(A) - reserved_total(RS.holder_of(A), RS.res_id) < n)
			return RS.refusal(A, n)
	for(var/id in op_implied_costs(P, B))
		var/datum/resource/RS = resource_of(id)
		var/n = op_cost_amount(P, B, id, A)
		if(RS && RS.available(A) - reserved_total(RS.holder_of(A), RS.res_id) < n)
			return RS.refusal(A, n)
	for(var/datum/entry/part/effect/F as anything in P.effects)
		var/why = F.precheck(A)
		if(why)
			return why
	return null

/// The cost an op declares for one resource (the explicit costs(), or what a binding implies). A costs() amount that is a handler (PROC_REF or
/// CAP_PROC, x(datum/act/A) returning a number) is asked in the act's context, so a cost can be what the holder's own state says (a transfer
/// amount): a handler that returns no number costs 0, which no adapter can reserve.
/proc/op_cost_amount(datum/op_plan/P, datum/entry/part/bind/B, res_id, datum/act/op/A = null)
	var/declared = LAZYACCESS(P.costs, "[res_id]")
	if(istext(declared))
		var/amount = A ? op_call(A, declared) : null
		return isnum(amount) ? amount : 0
	if(!isnull(declared))
		return declared
	if(res_id == RES_STACK && B?.bind_kind == BIND_STACK)
		return B.args["n"] || 1
	return 1

/// The resource ids an op's binding and parts imply beyond its costs(): stack units, the consumed item, the cooldown.
/proc/op_implied_costs(datum/op_plan/P, datum/entry/part/bind/B)
	. = list()
	if(B?.bind_kind == BIND_STACK && isnull(LAZYACCESS(P.costs, "[RES_STACK]")))
		. += RES_STACK
	if(P.consumes)
		. += RES_ITEM
	if(!isnull(P.cooldown_t))
		. += RES_COOLDOWN

/// Part-level pre-check of an effect (the insert action's pre-check, the resource's availability): a reason, or null.
/datum/entry/part/effect/proc/precheck(datum/act/op/A)
	return null

// ---- Wait: the workflow ----

/// The record of an op that is waiting: its act (the references nulled, the relations holding them), the step it is at, its open request.
/datum/pending_op
	var/datum/op_plan/oplan
	var/datum/entry/part/bind/binding
	var/datum/op_result/result
	var/datum/act/op/act
	/// The step the workflow is at (index into oplan.steps); the next one to start.
	var/cursor = 1
	var/origin
	var/authority
	var/provider_is_held = FALSE
	var/datum/activation/activation
	var/datum/capability/cap
	/// The keeps the current step runs under, and where the target was when the op started.
	var/keeps = 0
	/// What the actor held when the op started (REF text: a keep compares it, nothing is kept alive).
	var/start_hand_ref
	var/turf/target_turf
	/// Where the actor stood when the op started (the STAY keep).
	var/turf/start_loc
	/// The progress bar and the cog of the wait now running, and whether this wait was meant to draw one (a headless actor draws none).
	var/datum/progress_view/progbar
	var/datum/cog_view/cog
	var/progress_planned = FALSE
	var/steps_done = 0
	/// The actor's pending slot, and whether the pending ended.
	var/active = TRUE
	var/key
	/// The request the current asks() opened.
	var/datum/request/request
	var/started_at = 0
	/// REF text of the target a claims() op holds while it waits.
	var/claim_ref
	/// TRUE once the begins() message has been told (it is told at the first wait only).
	var/began = FALSE
	/// The first suspension happened: captured fields are snapshotted.
	var/captured_taken = FALSE
	var/list/args_saved
	var/list/ordered_args_saved
	var/list/log_saved
	var/list/step_answers_saved
	var/list/captured_saved

CAPABILITIES(/datum/pending_op)
	ref_one(nameof(holder), /datum, on_other_deleted = OTHER_DELETE_ME)
	ref_one(nameof(target), /datum, on_other_deleted = OTHER_DELETE_ME)
	ref_one(nameof(actor), /mob, on_other_deleted = OTHER_DELETE_ME)
	ref_one(nameof(held), /atom/movable, on_other_deleted = OTHER_DELETE_ME)
	ref_one(nameof(request), /datum/request, on_other_deleted = OTHER_CLEAR) // the open question: it ends first when its owner (this record) is deleted, so it must not hold it back
	owns_one(nameof(progbar), /datum/progress_view)
	owns_one(nameof(cog), /datum/cog_view)

/datum/pending_op
	var/datum/holder
	var/datum/target
	var/mob/actor
	var/atom/movable/held

/// actor ref text -> its pending op: an actor has one wait at a time.
GLOBAL_LIST_EMPTY(op_pending_by_actor)
/// REF(pending op) -> every pending op that is waiting, the system-origin ones too ("List Pending Ops").
GLOBAL_LIST_EMPTY(op_pending_all)

/// Is `target` claimed by an op that is waiting on it (claims())?
/proc/op_claimed(datum/target)
	if(!target)
		return FALSE
	var/datum/pending_op/P = target.rx?.claimed_by
	return !!P && P.active && !QDELETED(P)

/proc/op_pending_of(mob/actor)
	RETURN_TYPE(/datum/pending_op)
	var/datum/pending_op/P = GLOB.op_pending_by_actor["[REF(actor)]"]
	if(P && P.active && !QDELETED(P))
		return P
	return null

/// Starts the workflow of an op that has wait()/asks()/confirms() steps. The act's references go into the pending op's relations.
/proc/op_wait_begin(datum/act/op/A, datum/op_cand/C)
	var/datum/pending_op/P = new
	P.oplan = A.oplan // ALLOW(ownership): an engine record owned by its own end path (a flyweight, or a record the framework tears down)
	P.binding = A.binding // ALLOW(ownership): an engine record owned by its own end path (a flyweight, or a record the framework tears down)
	P.result = A.result // ALLOW(ownership): the caller's plain record: the pending op fills it in later
	P.origin = A.origin
	P.authority = A.authority
	P.activation = C.activation // ALLOW(ownership): an engine record owned by its own end path (a flyweight, or a record the framework tears down)
	P.cap = C.cap
	P.key = A.key
	P.provider_is_held = !isnull(A.provider) && A.provider == A.held_provider()
	P.started_at = op_now()
	P.keeps = op_default_keeps(A, A.binding)
	P.start_hand_ref = REF(A.actor?.held_for_ops())
	var/atom/T = A.target
	P.start_loc = A.actor?.loc // ALLOW(ownership): a turf or container: plain location data, never deleted by the op
	P.target_turf = istype(T) ? get_turf(T) : null // ALLOW(ownership): a turf: plain location data, never deleted by the op
	rel_set(P, nameof(P.holder), A.holder)
	rel_set(P, nameof(P.target), A.target)
	rel_set(P, nameof(P.actor), A.actor)
	rel_set(P, nameof(P.held), A.held_provider())
	P.act = A // ALLOW(handlers, ownership): the pending op carries its act across a wait on purpose, and the act is released when the op ends (end_pending)
	A.pending = P // ALLOW(ownership): a pooled transient: reset on release
	if(A.actor && A.origin != ORIGIN_SYSTEM)
		GLOB.op_pending_by_actor["[REF(A.actor)]"] = P
	GLOB.op_pending_all["[REF(P)]"] = P
	if(A.oplan.claims && A.target)
		P.claim_target(A.target)
	P.watch_begin(A)
	P.suspend_act()
	P.advance()
	return P.result

/// The keeps an op's waits run under by default: all four where they apply (no HELD without a held item, no ADJACENT without a spatial reach).
/proc/op_default_keeps(datum/act/op/A, datum/entry/part/bind/B)
	. = WAIT_KEEPS_DEFAULT
	if(A.origin == ORIGIN_SYSTEM || !A.actor)
		. &= ~STAY
	if(isnull(A.held_provider()))
		. &= ~HELD
	if(!B || B.reach_policy() != REACH_ADJACENT || A.origin == ORIGIN_SYSTEM || !A.actor)
		. &= ~ADJACENT

/// The act's entity references move to the relations: the act holds nothing strongly while the op waits.
/datum/pending_op/proc/suspend_act()
	var/datum/act/op/A = act
	args_saved = A.args
	ordered_args_saved = A.ordered_args
	log_saved = A.log_lines
	step_answers_saved = A.step_answers
	captured_saved = A.captured_values
	A.holder = null // ALLOW(ownership): a pooled transient: reset on release
	A.target = null
	A.target_atom = null // ALLOW(ownership): a pooled transient: reset on release
	A.actor = null
	A.set_held_provider(null)
	A.provider = null
	A.source = null // ALLOW(ownership): a pooled transient: reset on release
	A.activation = null // ALLOW(ownership): a pooled transient: reset on release
	A.cap = null

/// Restores the act's references from the relations (a wait ended, an answer arrived). False when one was lost.
/datum/pending_op/proc/resume_act()
	var/datum/act/op/A = act
	if(!A || !active)
		return FALSE
	if(QDELETED(holder) || QDELETED(target) || (!isnull(actor) && QDELETED(actor)))
		return FALSE
	A.holder = holder // ALLOW(ownership): a pooled transient: reset on release
	A.target = target
	A.actor = actor
	A.set_held_provider(held)
	A.cap = cap
	A.activation = activation // ALLOW(ownership): a pooled transient: reset on release
	A.source = activation ? activation.source : holder // ALLOW(ownership): a pooled transient: reset on release
	A.provider = provider_is_held ? held : actor
	if(istype(target, /atom))
		A.target_atom = target // ALLOW(ownership): a pooled transient: reset on release
	A.args = args_saved
	A.ordered_args = ordered_args_saved
	A.log_lines = log_saved
	A.step_answers = step_answers_saved
	A.captured_values = captured_saved
	return TRUE

/// Runs the workflow from the cursor: starts the next wait or prompt and returns, or finishes the steps and goes on to Do.
/datum/pending_op/proc/advance()
	if(!active)
		return
	var/datum/act/op/A = act
	while(cursor <= length(oplan.steps))
		var/step_part = oplan.steps[cursor]
		if(istype(step_part, /datum/entry/part/wait))
			var/datum/entry/part/wait/W = step_part
			cursor++
			if(!resume_act())
				return cancel(/datum/msg/op/target_gone)
			var/delay = W.wait_time(A)
			if(!began && oplan.begins && delay > 0)
				began = TRUE
				oplan.begins.feedback(A)
			keeps = W.args["keeps"] & op_default_keeps(A, binding)
			suspend_act()
			if(delay > 0)
				progress_begin(delay)
				after(src, delay, TYPE_PROC_REF(/datum/pending_op, step_done), key = "op_wait")
				return
			continue
		if(istype(step_part, /datum/entry/part/asks))
			var/datum/entry/part/asks/Q = step_part
			cursor++
			if(!resume_act())
				return cancel(/datum/msg/op/target_gone)
			if(!isnull(Q.args["when"]) && !op_cond(A, Q.args["when"]))
				suspend_act()
				continue // the step's own condition does not hold: no prompt, on to the next step
			take_capture(A)
			keeps = Q.args["keeps"] & op_default_keeps(A, binding) & ~STAY // an open question outlives a step the actor takes
			var/list/fields = op_request_fields(A, Q)
			var/datum/request/R = request_open(src, Q.args["type"], TYPE_PROC_REF(/datum/pending_op, request_done), fields, A)
			if(!R)
				suspend_act()
				return cancel(/datum/msg/op/failed)
			rel_set(src, nameof(request), R)
			R.waiting = result // ALLOW(ownership): the caller's plain record: the request hands it back to test_answer()
			R.step_name = Q.args["step"]
			suspend_act()
			return
		cursor++
	// every step done: back into the op's context for the last checks, then Do
	if(!resume_act())
		return cancel(/datum/msg/op/target_gone)
	finish()

/datum/pending_op/proc/progress_begin(delay)
	return

/datum/pending_op/proc/progress_end(success)
	return

/// A timed wait ended.
/datum/pending_op/proc/step_done()
	if(!active)
		return
	progress_end(TRUE)
	if(!resume_act())
		return cancel(/datum/msg/op/target_gone)
	var/why = recheck_reason()
	if(why)
		suspend_act()
		return cancel(why)
	suspend_act()
	advance()

/// A prompt ended (answered, cancelled, timed out): the request layer calls this with the finished request.
/datum/pending_op/proc/request_done(datum/act/request/RA)
	if(!active)
		return
	var/datum/request/R = RA.request
	rel_clear(src, nameof(request))
	if(R.outcome != REQ_ANSWERED)
		return cancel(R.outcome == REQ_TIMED_OUT ? /datum/msg/op/timed_out : (R.outcome == REQ_CANCELLED ? /datum/msg/op/answer_no : /datum/msg/op/failed))
	if(!resume_act())
		return cancel(/datum/msg/op/target_gone)
	var/datum/act/op/A = act
	// A confirms() answered "no" ends the op and nothing is spent.
	var/datum/entry/part/asks/Q = oplan.steps[cursor - 1]
	if(Q.args["confirms"] && !R.value)
		suspend_act()
		return cancel(/datum/msg/op/answer_no)
	A.request = R // ALLOW(ownership): a pooled transient: reset on release
	A.answer = R // ALLOW(ownership): a pooled transient: reset on release
	LAZYSET(A.step_answers, R.step_name || "answer", R) // ALLOW(ownership): a pooled transient: reset on release
	// the resume rule: restore the captured fields, then re-check when and Require
	var/why = op_resume_captured(A)
	if(!why)
		why = recheck_reason()
	if(why)
		suspend_act()
		return cancel(why)
	suspend_act()
	advance()

/// The fields the op declared are restored from the capture (CAPTURE), refreshed (LATEST) or compared (CANCEL_IF_CHANGED). Returns a reason when the op ends.
/proc/op_resume_captured(datum/act/op/A)
	var/datum/op_plan/P = A.oplan
	for(var/name in P.captured)
		var/policy = P.captured[name]
		var/live = op_key_value(A.holder, name)
		switch(policy)
			if(LATEST)
				LAZYSET(A.captured_values, name, live)
			if(CANCEL_IF_CHANGED)
				if(A.captured_values?[name] != live)
					return /datum/msg/op/changed
	return null

/// The first time the op suspends at an asks(): the fields it declares are snapshotted into the act.
/datum/pending_op/proc/take_capture(datum/act/op/A)
	if(captured_taken)
		return
	captured_taken = TRUE
	var/list/names = list()
	for(var/name in oplan.captured)
		names |= name
	for(var/step_part in oplan.steps)
		if(istype(step_part, /datum/entry/part/asks))
			var/datum/entry/part/asks/Q = step_part
			for(var/field in Q.args["fields"])
				var/value = Q.args["fields"][field]
				if(istext(value) && A.holder && (value in A.holder.vars))
					names |= value
	for(var/name in names)
		LAZYSET(A.captured_values, name, op_key_value(A.holder, name))

/// The request's named fields for an asks(): a field whose value names a var of the holder reads the capture (nameof(v)), the rest are literals.
/proc/op_request_fields(datum/act/op/A, datum/entry/part/asks/Q)
	var/list/out = list()
	var/list/declared = Q.args["fields"]
	for(var/field in declared)
		var/value = declared[field]
		if(islist(value) && length(value) == 2 && value[1] == "computed")
			value = op_call(A, value[2])
		else if(istext(value) && A.holder && (value in A.holder.vars))
			value = A.captured_values?[value]
		out[field] = value
	out["answerer"] = A.actor
	return out

/// The checks after a wait or an answer: the op's when and Require are asked again, and the keeps hold. A reason when the op ends.
/datum/pending_op/proc/recheck_reason()
	var/datum/act/op/A = act
	var/why = keeps_reason(A)
	if(why)
		return why
	// A window button's op answers in its window: it stops when the window is gone or no longer interactive (the legacy prompts asked
	// their window after every answer).
	var/datum/pressed_in = A.window_ui()
	if(pressed_in && (QDELETED(pressed_in) || !pressed_in.op_window_interactive()))
		return /datum/msg/op/stopped
	for(var/cond in oplan.conds)
		if(!op_cond(A, cond))
			return /datum/msg/op/not_available
	return op_require_reason(A, oplan, binding)

/// The reason a keep broke, or null: HELD, ADJACENT, TARGET_PRESENT and ALIVE.
/datum/pending_op/proc/keeps_reason(datum/act/op/A)
	var/mob/M = A.actor
	if((keeps & HELD) && M && REF(M.held_for_ops()) != start_hand_ref)
		return /datum/msg/op/stopped
	if((keeps & ADJACENT) && M && A.target_atom && !M.Adjacent(A.target_atom))
		return /datum/msg/op/stopped
	if((keeps & TARGET_PRESENT) && A.target_atom && target_turf && get_turf(A.target_atom) != target_turf)
		return /datum/msg/op/stopped
	if((keeps & ALIVE) && M && M.stat != CONSCIOUS)
		return /datum/msg/op/stopped
	if((keeps & STAY) && M && M.loc != start_loc)
		return /datum/msg/op/stopped
	return null

/// While waiting: the keeps and the requirements are checked again; the op is cancelled only if one now refuses.
/datum/pending_op/proc/recheck()
	if(!active)
		return
	if(!resume_act())
		return cancel(/datum/msg/op/target_gone)
	var/why = recheck_reason()
	suspend_act()
	if(why)
		return cancel(why)

// ---- watching: a wait re-checks when something it reads is published ----
//
// While an op waits it subscribes to the reads of its conditions and requirements (the generated reads of the declared keys and procs) and to the
// keeps (the hands of the actor, where it is and its stat, where the target is): the moment one is published the op re-checks and is cancelled if
// one now refuses. Nothing polls. The subscription is the dynamic-reader count of rx_watch_adjust() plus the shared watch index of op_reads_changed().

/datum/pending_op
	/// The (entity, key) reads the op watches, as list(datum, key) rows, while it waits.
	var/list/watching
	/// TRUE while a re-check runs, so a read published by the re-check itself does not start another.
	var/rechecking = FALSE

/// Subscribes to everything the op plan and keeps read. Called once, when the wait begins and the act still holds its entities.
/datum/pending_op/proc/watch_begin(datum/act/op/A)
	if(watching)
		return
	watching = op_watch_reads(A)
	for(var/list/pair as anything in watching)
		var/datum/watched = pair[1]
		rx_watch_adjust(watched, pair[2], 1)
		var/index = "[REF(watched)]|[pair[2]]"
		var/list/on = GLOB.op_watchers[index]
		if(!on)
			on = list()
			GLOB.op_watchers[index] = on
		on |= src

/// Drops the subscription.
/datum/pending_op/proc/watch_end()
	for(var/list/pair as anything in watching)
		var/datum/watched = pair[1]
		if(!QDELETED(watched))
			rx_watch_adjust(watched, pair[2], -1)
		var/index = "[REF(watched)]|[pair[2]]"
		var/list/on = GLOB.op_watchers[index]
		if(!on)
			continue
		on -= src
		if(!length(on))
			GLOB.op_watchers -= index
	watching = null

/// A read the op watches was published: the keeps and requirements are asked again now.
/datum/pending_op/proc/reads_changed()
	if(!active || rechecking)
		return
	rechecking = TRUE
	recheck()
	rechecking = FALSE

/// The (entity, key) rows an op wait watches: the reads of its conditions, requirements and resource costs, and the keeps.
/proc/op_watch_reads(datum/act/op/A)
	var/datum/op_plan/P = A.oplan
	var/list/pairs = list()
	for(var/cond in P.conds)
		op_reads_of(A, cond, pairs)
	for(var/requirement in P.needs)
		op_reads_of(A, requirement, pairs)
	for(var/id in P.cost_order)
		var/datum/resource/RS = resource_of(text2num(id))
		RS?.watch_reads(A, pairs)
	if(A.actor)
		pairs += list(list(A.actor, OP_KEEP_HAND), list(A.actor, OP_KEEP_MOVED), list(A.actor, "stat"))
	if(A.target)
		pairs += list(list(A.target, OP_KEEP_MOVED))
	return pairs

/// Adds the reads of one condition or requirement to `pairs`. A condition is a var name, a stat or capability key id, a proc of the holder (its
/// generated own-var reads), a not/all/any tree or a requirement entry.
/proc/op_reads_of(datum/act/op/A, cond, list/pairs)
	if(isnull(cond))
		return
	if(islist(cond))
		var/list/tree = cond
		for(var/i in 2 to length(tree))
			op_reads_of(A, tree[i], pairs)
		return
	if(istype(cond, /datum/entry/part/req))
		var/datum/entry/part/req/R = cond
		for(var/list/pair as anything in R.read_keys(A))
			pairs += list(pair)
		return
	if(isnum(cond) || (istext(cond) && copytext(cond, 1, 5) != "cap:"))
		for(var/key in change_read_keys(A.holder, cond))
			pairs += list(list(A.holder, key))

/// All steps answered: the last checks, then Do.
/datum/pending_op/proc/finish()
	var/datum/act/op/A = act
	var/why = recheck_reason()
	if(why)
		return end_with(ACT_REFUSED, why)
	end_pending()
	op_do(A)
	drop_record()

/// The op ends before Do: the result and the act are closed.
/datum/pending_op/proc/end_with(outcome, reason)
	var/datum/act/op/A = act
	end_pending()
	op_end(A, outcome, reason)
	drop_record()

/// The record has done its work: it is deleted (the relations it held and its own record go with it).
/datum/pending_op/proc/drop_record()
	if(!QDELETED(src))
		qdel(src) // ALLOW(lifecycle): the pending op is a plain record that ends with its op: it holds nothing the op still needs

/// The target is claimed for the length of the wait: a claim is in the registry under the target's ref, and the target is told it changed.
/datum/pending_op/proc/claim_target(datum/claimed)
	claim_ref = "[REF(claimed)]"
	rx_of(claimed).claimed_by = src
	op_changed(claimed)
	var/atom/A = claimed
	if(istype(A))
		A.op_claim_changed()

/// The claim ends with the wait.
/datum/pending_op/proc/release_claim()
	if(!claim_ref)
		return
	var/datum/claimed = locate(claim_ref)
	if(claimed?.rx?.claimed_by == src)
		claimed.rx.claimed_by = null // ALLOW(ownership): the claim ends with the waiting op that made it
	claim_ref = null
	if(claimed)
		op_changed(claimed)
		var/atom/A = claimed
		if(istype(A) && !QDELETED(A))
			A.op_claim_changed()

/// The pending record is done: it leaves the actor's slot, its timers go, the request is closed.
/datum/pending_op/proc/end_pending()
	if(!active)
		return
	active = FALSE
	release_claim()
	progress_end(FALSE)
	var/datum/act/op/A = act
	if(A)
		A.pending = null // ALLOW(ownership): a pooled transient: reset on release
	if(actor && GLOB.op_pending_by_actor["[REF(actor)]"] == src)
		GLOB.op_pending_by_actor -= "[REF(actor)]"
	GLOB.op_pending_all -= "[REF(src)]"
	watch_end()
	// what the act carried across the wait is the act's own again (or gone with it): the pending op keeps nothing of it
	args_saved = null
	ordered_args_saved = null
	log_saved = null
	step_answers_saved = null
	captured_saved = null
	cancel_after(src, "op_wait")
	if(request)
		var/datum/request/R = request
		rel_clear(src, nameof(request))
		R.waiting = null // ALLOW(ownership): an engine record owned by its own end path (a flyweight, or a record the framework tears down)
		request_end(R, REQ_CANCELLED, null)
	// The op is over: the record lets go of the four entities (their reverse links go with the relations) and of the act; its caller deletes it.
	rel_clear(src, nameof(holder))
	rel_clear(src, nameof(target))
	rel_clear(src, nameof(actor))
	rel_clear(src, nameof(held))
	act = null // ALLOW(ownership): a pooled act the pending op no longer carries

/// Cancels the op with feedback: the actor is told, the result carries the reason, nothing was spent (costs are reserved after the last step).
/datum/pending_op/proc/cancel(reason)
	if(!active)
		return
	var/datum/act/op/A = act
	if(!A || QDELETED(A))
		active = FALSE
		return
	var/mob/M = actor
	if(oplan.interrupted && resume_act())
		A.reason = reason
		op_call(A, oplan.interrupted)
		suspend_act()
	end_pending()
	// the actor's relation may already be gone: the act's snapshot names carry the feedback
	op_end(A, ACT_REFUSED, reason, M)
	drop_record()

/// The pending op is deleted: one of its four entities is gone (OTHER_DELETE_ME) or the record is dropped. Before the reservation that cancels the op.
/datum/pending_op/on_destroy(force)
	if(active)
		var/datum/act/op/A = act
		active = FALSE
		release_claim()
		if(actor && GLOB.op_pending_by_actor["[REF(actor)]"] == src)
			GLOB.op_pending_by_actor -= "[REF(actor)]"
		GLOB.op_pending_all -= "[REF(src)]"
		watch_end()
		if(request)
			var/datum/request/R = request
			R.waiting = null // ALLOW(ownership): an engine record owned by its own end path (a flyweight, or a record the framework tears down)
			request_end(R, REQ_CANCELLED, null)
		if(A && !QDELETED(A))
			A.pending = null // ALLOW(ownership): a pooled transient: reset on release
			op_end(A, ACT_REFUSED, /datum/msg/op/target_gone, actor)
	..()

// ---- Do ----

/// Do: reserve the costs, chance, the effects in order, commit or release, feedback and the notice. Returns the op's result.
/proc/op_do(datum/act/op/A)
	var/datum/op_plan/P = A.oplan
	// The holder may take the op over (extend(/datum/act/op, instead(...))): a live door shocks whoever touches it instead of doing what they meant.
	if(op_taken_over(A))
		return op_end(A, ACT_REPLACED, null)
	var/why = op_reserve(A)
	if(why)
		return op_end(A, ACT_REFUSED, why)
	// chance(p): a failed roll plays its else feedback, commits the reserved costs (the attempt cost them), runs no effect and ends committed.
	if(P.chance && !TEST_ROLL(op_chance_percent(A, P.chance.args["percent"])))
		A.rolled = FALSE
		op_feedback_parts(A, P.chance.children)
		op_commit_reservations(A)
		return op_end(A, ACT_COMMITTED, null)
	var/report = OP_OK
	for(var/datum/entry/part/effect/F as anything in P.effects)
		report = op_run_effect(A, F)
		if(report == OP_PASS) // handled, input not used up: the effects after it still run, the op commits, and the click goes on (OP_PASS)
			A.passed = TRUE
			report = OP_OK
			continue
		if(report != OP_OK)
			break
	if(report == OP_OK)
		var/commit_report = op_commit_reservations(A)
		if(commit_report != OP_OK)
			report = commit_report
	else
		op_release_reservations(A)
	switch(report)
		if(OP_OK)
			return op_end(A, ACT_COMMITTED, null)
		if(OP_REPLACED)
			return op_end(A, ACT_REPLACED, A.reason)
		if(OP_REFUSED)
			return op_end(A, ACT_REFUSED, A.reason || /datum/msg/op/not_available)
		if(OP_DECLINE)
			return op_end(A, ACT_DECLINED, null)
	return op_end(A, ACT_REFUSED, A.reason || /datum/msg/op/failed)

/// Runs the holder's takeovers of its own ops (instead hooks on /datum/act/op), in order, on the op's context. TRUE when one took the op over. The
/// context's entry fields (activation, capability, source) are the op's own and come back as they were whatever the hook did.
/proc/op_taken_over(datum/act/op/A)
	var/datum/holder = A.holder
	if(!holder || QDELETED(holder))
		return FALSE
	var/static_plan = act_plan_static(table_of(holder), /datum/act/op)
	if(!static_plan && !length(holder.rx?.hooks))
		return FALSE
	var/datum/act_plan/plan = act_plan_for(holder, /datum/act/op)
	if(!length(plan.instead))
		return FALSE
	var/datum/activation/was_activation = A.activation
	var/datum/capability/was_cap = A.cap
	var/datum/was_source = A.source
	. = FALSE
	for(var/datum/hook/H as anything in plan.instead)
		if(!hook_conditions_hold(H, holder))
			continue
		hook_context(A, H)
		var/took = hook_run_parts(H, A, H.entry.children)
		A.activation = was_activation // ALLOW(ownership): a pooled context holds its entities for one trigger and is reset on release
		A.cap = was_cap
		A.source = was_source // ALLOW(ownership): a pooled context holds its entities for one trigger and is reset on release
		if(took)
			return TRUE

/// The percent a chance() names: a number, the name of a var of the holder (escape_chance = nameof(escapechance)), or a handler.
/proc/op_chance_percent(datum/act/op/A, percent)
	if(!istext(percent))
		return percent
	var/datum/holder = A.holder
	if(holder && (percent in holder.vars))
		return holder.vars[percent]
	var/answer = op_call(A, percent)
	return isnum(answer) ? answer : 0

/// Reserves every cost the op declares or implies. A reason when one cannot be made (the ones made are released).
/proc/op_reserve(datum/act/op/A)
	var/datum/op_plan/P = A.oplan
	var/list/wanted = list()
	for(var/id in P.cost_order)
		wanted += text2num(id)
	for(var/id in op_implied_costs(P, A.binding))
		wanted |= id
	for(var/id in wanted)
		var/datum/resource/RS = resource_of(id)
		if(!RS)
			continue
		var/n = op_cost_amount(P, A.binding, id, A)
		var/datum/reservation/R = RS.reserve(A, n)
		if(!R)
			op_release_reservations(A)
			return RS.refusal(A, n)
		TEST_REC_RESOURCE(TEST_EVENT_RESERVE, id, R.holder, n, A.key)
		LAZYADD(A.reservations, R) // ALLOW(ownership): a pooled transient: reset on release
	return null

/// Commits every reservation: OP_OK, or OP_FAILED with a log line naming the resource when one cannot (the rest are released).
/proc/op_commit_reservations(datum/act/op/A)
	. = OP_OK
	var/list/open = A.reservations
	A.reservations = null
	for(var/datum/reservation/R as anything in open)
		if(. != OP_OK)
			reservation_release(R)
			continue
		var/report = reservation_commit(R)
		if(report != OP_OK)
			. = OP_FAILED
			act_log(A, "failed to commit [R.amount] of resource [R.res_id] held by [R.holder]")

/proc/op_release_reservations(datum/act/op/A)
	var/list/open = A.reservations
	A.reservations = null
	for(var/datum/reservation/R as anything in open)
		reservation_release(R)

/// Runs one effect: its report, with a runtime reported as OP_FAILED and logged.
/proc/op_run_effect(datum/act/op/A, datum/entry/part/effect/F)
	var/report = OP_OK
	try
		report = F.run_effect(A)
	catch(var/exception/fault)
		log_world("OP FAILED: [A.key] effect [F.part_name]: [fault.name] ([fault.file]:[fault.line])")
		act_log(A, "effect [F.part_name] failed: [fault.name]")
		return OP_FAILED
	if(isnull(report) || report == TRUE || report == FALSE)
		return OP_OK
	return report

/// An effect part run from a hook (an instead or an on_notice): its report, a runtime logged as OP_FAILED. The context is the action's own.
/proc/hook_effect_report(datum/act/A, datum/entry/part/effect/F)
	var/report = OP_OK
	try
		report = F.run_effect(A)
	catch(var/exception/fault)
		log_world("HOOK EFFECT FAILED: [A.type] effect [F.part_name]: [fault.name] ([fault.file]:[fault.line])")
		return OP_FAILED
	return (isnull(report) || report == TRUE || report == FALSE) ? OP_OK : report

/// Calls a resource adapter's proc, reporting a runtime as OP_FAILED.
/proc/op_safe_call(datum/target, proc_name, ...)
	var/list/rest = args.Copy(3)
	try
		return call(target, proc_name)(arglist(rest))
	catch(var/exception/fault)
		log_world("OP FAILED: [target.type].[proc_name]: [fault.name] ([fault.file]:[fault.line])")
		return OP_FAILED

/// Feedback parts (says, plays) run from a failed roll's else list.
/proc/op_feedback_parts(datum/act/op/A, list/parts)
	for(var/part in parts)
		if(istype(part, /datum/entry/part/says))
			var/datum/entry/part/says/S = part
			S.feedback(A)
		else if(istype(part, /datum/entry/part/plays))
			var/datum/entry/part/plays/PL = part
			PL.feedback(A)

// ---- ending an op ----

/// The op ends: the result is filled in, the unspent reservations are released, feedback and the notice go out for a committed op with a
/// successful roll, the log line is written, and the act is released. Returns the result.
/proc/op_end(datum/act/op/A, outcome, reason = null, mob/told = null)
	RETURN_TYPE(/datum/op_result)
	var/datum/op_result/result = A.result
	var/datum/op_plan/P = A.oplan
	var/mob/actor = A.actor || told
	op_release_reservations(A)
	A.outcome = outcome
	A.reason = reason
	if(result)
		result.outcome = outcome
		result.reason = reason
		result.rolled = A.rolled
		result.passed = A.passed && outcome == ACT_COMMITTED
	TEST_REC_OUTCOME(A.key, outcome, reason, actor)
	var/committed = (outcome == ACT_COMMITTED)
	if(committed && A.rolled && P)
		op_feedback(A)
	var/declined = (outcome == ACT_DECLINED)
	if(!committed && !declined)
		op_tell(actor, reason)
	op_log(A, actor, outcome, reason)
	if(P && !P.quiet && A.holder && !declined)
		op_publish_done(A, committed ? (A.rolled ? ACT_COMMITTED : ACT_ROLL_FAILED) : outcome)
	if(committed && A.rolled && P && length(P.delayed))
		op_schedule_delayed(A)
	A.release()
	return result

/// The success feedback: says(), plays(), flash().
/proc/op_feedback(datum/act/op/A)
	var/datum/op_plan/P = A.oplan
	if(P.says)
		P.says.feedback(A)
	if(P.plays)
		P.plays.feedback(A)

/datum/entry/part/says/proc/feedback(datum/act/op/A)
	var/msg = src.args["msg"]
	if(istext(msg)) // says(PROC_REF(x)) / says(CAP_PROC(x)): x(datum/act/A) returns the /datum/msg type this commit tells (a toggle says what it did)
		msg = op_call(A, msg)
	if(ispath(msg, /datum/msg) && A.actor)
		A.actor.op_feedback_message(istype(A.target, /atom) ? A.target : null, msg, A.held_provider())

/// What the actor and onlookers are told when the op starts waiting.
/datum/entry/part/begins/proc/feedback(datum/act/op/A)
	var/msg = src.args["msg"]
	if(istext(msg))
		msg = op_call(A, msg)
	if(ispath(msg, /datum/msg) && A.actor)
		A.actor.op_feedback_message(istype(A.target, /atom) ? A.target : null, msg, A.held_provider())

/datum/entry/part/plays/proc/feedback(datum/act/op/A)
	var/atom/where = istype(A.target, /atom) ? A.target : A.actor
	if(where && src.args["sfx"])
		where.op_feedback_sound(src.args["sfx"])

/// The op's log line: committed ops that declared logs(), and every refusal after the op started or declared logs().
/proc/op_log(datum/act/op/A, mob/actor, outcome, reason)
	var/datum/op_plan/P = A.oplan
	if(!P)
		return
	if(outcome == ACT_DECLINED)
		return
	var/committed = (outcome == ACT_COMMITTED)
	if(committed && (!P.log_type || !A.rolled))
		if(!(P.log_type && !A.rolled))
			return
	if(!committed && !(A.started || P.log_type))
		return
	var/text = "[A.actor_name || "something"] [op_label(P)] [A.target_name || "it"]"
	if(!committed)
		text += " ([outcome == ACT_REPLACED ? "replaced" : "refused"]: [reason_text(reason)])"
	else if(!A.rolled)
		text += " (failed roll)"
	for(var/line in A.log_lines)
		text += "; [line]"
	TEST_REC_LOG(A.key, outcome, A.origin, A.actor || actor, A.target, text)
	if(P.log_type & LOG_GAME)
		log_game(text)

/// The op_done notice (E4's delivery): published for the outcomes listeners asked for (on_op(key, ..., outcome =)), carrying the op key. A committed op
/// whose roll succeeded is ACT_COMMITTED, a failed roll ACT_ROLL_FAILED; nothing is built when nobody listens.
/proc/op_publish_done(datum/act/op/A, outcome)
	var/datum/holder = A.holder
	if(!holder || QDELETED(holder) || !notice_wanted(holder, /datum/notice/op_done, outcome))
		return
	var/datum/notice/op_done/N = notice_take(/datum/notice/op_done)
	N.op_key = A.key
	N.refusal = A.reason // a listener of refusals (on_op(..., outcome = ACT_REFUSED)) reads why
	notice_publish(holder, N, outcome)

/// delayed(t, parts...): schedules more parts on the holder's clock with only the holder and the snapshot names.
/proc/op_schedule_delayed(datum/act/op/A)
	var/datum/op_plan/P = A.oplan
	if(!A.holder || QDELETED(A.holder))
		return
	for(var/datum/entry/part/delayed/D as anything in P.delayed)
		after(A.holder, D.args["t"], GLOBAL_PROC_REF(op_delayed_run), with = list(A.holder, D, A.held_name, A.target_name, A.actor_name, A.actor))

/// A delayed() part runs: on = ON_HOLDER and says() only.
/proc/op_delayed_run(datum/holder, datum/entry/part/delayed/D, held_name, target_name, actor_name, mob/actor)
	if(!holder || QDELETED(holder))
		return
	var/datum/act/timer/T = take(/datum/act/timer)
	T.holder = holder // ALLOW(ownership): a pooled transient: reset on release
	T.held_name = held_name
	T.target_name = target_name
	T.actor_name = actor_name
	for(var/part in D.children)
		if(istype(part, /datum/entry/part/says))
			var/datum/entry/part/says/S = part
			var/msg = S.args["msg"]
			if(ispath(msg, /datum/msg) && istype(holder, /atom))
				holder.op_timer_message(msg)
	T.release()

// ---- effects ----

/// The entity an on = selector names for this act.
/proc/op_on_entity(datum/act/op/A, on)
	switch(on)
		if(ON_HOLDER)
			return A.holder
		if(ON_ACTOR)
			return A.actor
		if(ON_HELD)
			return A.held_provider()
	return A.target

/// The source a holds() or grants() uses by default: the activation when it lands on the op's own holder, else the op holder.
/proc/op_default_source(datum/act/op/A, datum/entity, source_arg, outlives)
	if(source_arg)
		if(source_arg == ON_ACTOR)
			return A.actor
		return source_arg
	if(entity == A.holder && A.activation && !outlives)
		return A.activation
	return A.holder

/datum/entry/part/effect/then/run_effect(datum/act/op/A)
	var/list/extra = list()
	if(A.ordered_args)
		extra = A.ordered_args
	return op_call_list(A, src.args["handler"], extra)

/datum/entry/part/effect/toggles/run_effect(datum/act/op/A)
	var/datum/D = A.holder
	var/key = src.args["key"]
	if(isnum(key))
		key_set(D, key, !cap_key_get(D, key))
		return OP_OK
	if(!istext(key) || !(key in D.vars))
		return OP_FAILED
	op_write_key(D, key, !D.vars[key])
	return OP_OK

/datum/entry/part/effect/sets/run_effect(datum/act/op/A)
	var/datum/D = A.holder
	var/key = src.args["key"]
	if(isnum(key))
		key_set(D, key, src.args["value"])
		return OP_OK
	if(!istext(key) || !(key in D.vars))
		return OP_FAILED
	op_write_key(D, key, src.args["value"])
	return OP_OK

/// Writes a tracked var through its setter (set_<var>) when it has one, else directly and publishes the change.
/proc/op_write_key(datum/D, var_name, value)
	if(hascall(D, "set_[var_name]"))
		call(D, "set_[var_name]")(value)
		return
	D.vars[var_name] = value // ALLOW(api): an op's sets()/toggles() writes the tracked var it names, then publishes it
	tracked_changed(D, var_name)

/datum/entry/part/effect/holds/run_effect(datum/act/op/A)
	var/datum/entity = op_on_entity(A, src.args["on"])
	if(!entity)
		return OP_FAILED
	var/source = op_default_source(A, entity, src.args["source"], src.args["outlives"])
	var/placed = hold(entity, src.args["stat"], src.args["value"], source, src.args["lasts"], bound = src.args["bound"])
	return placed ? OP_OK : OP_FAILED

/datum/entry/part/effect/releases/run_effect(datum/act/op/A)
	var/datum/entity = op_on_entity(A, src.args["on"])
	if(!entity)
		return OP_FAILED
	release(entity, src.args["stat"], op_default_source(A, entity, src.args["source"], FALSE))
	return OP_OK

/datum/entry/part/effect/toggles_hold/run_effect(datum/act/op/A)
	var/datum/entity = op_on_entity(A, src.args["on"])
	if(!entity)
		return OP_FAILED
	var/source = op_default_source(A, entity, src.args["source"], FALSE)
	if(held_by_source(entity, src.args["stat"], source))
		release(entity, src.args["stat"], source)
		return OP_OK
	return hold(entity, src.args["stat"], src.args["value"], source) ? OP_OK : OP_FAILED

/datum/entry/part/effect/grants/run_effect(datum/act/op/A)
	var/datum/entity = op_on_entity(A, src.args["on"])
	if(!entity)
		return OP_FAILED
	var/source = op_default_source(A, entity, src.args["source"], src.args["outlives"])
	// A grant whose source is the running activation is owned by it (X1): it ends with it, whichever way the activation ends.
	var/datum/activation/owner = (source == A.activation && A.activation && !A.activation.dead) ? A.activation : null
	return grant(entity, src.args["what"], source, src.args["lasts"], src.args["bound"], owner) ? OP_OK : OP_FAILED





/datum/entry/part/effect/shares_effects/run_effect(datum/act/op/A)
	var/datum/op_plan/other = op_plan_for(A.holder, src.args["key"], list())
	if(!other)
		return OP_FAILED
	for(var/requirement in other.needs)
		if(!op_req_holds(A, requirement))
			A.reason = op_req_refusal(A, requirement)
			return OP_REFUSED
	for(var/datum/entry/part/effect/F as anything in other.effects)
		var/report = op_run_effect(A, F)
		if(report != OP_OK)
			return report
	return OP_OK

/// The pre-check of the insert action (E4): the needs hooks of the holder's table and activations asked about this insert, nothing started.
/// A reason, or null. Allocates only when something hooks the action.
/proc/op_insert_precheck(atom/holder, atom/movable/thing, slot_id)
	if(!holder || !act_wanted(holder, /datum/act/insert))
		return null
	var/datum/act/insert/F = act_begin(/datum/act/insert, holder)
	if(!F)
		return null
	F.item = thing // ALLOW(ownership): a pooled context holds its entities for one trigger and is reset on release
	F.slot_id = slot_id
	var/datum/act_plan/plan = act_plan_for(holder, /datum/act/insert)
	var/reason = null
	for(var/datum/hook/H as anything in plan.needs)
		if(!hook_conditions_hold(H, holder))
			continue
		reason = act_needs_refusal(F, H)
		if(reason)
			break
	F.release()
	return reason


/// Interfaces to presentation and actor policy used by an operation.
/datum/progress_view
	abstract_type = /datum/progress_view
/datum/progress_view/proc/animate_fill(delay)
	return
/datum/progress_view/proc/end_progress(success)
	return
/datum/cog_view
	abstract_type = /datum/cog_view
/datum/cog_view/proc/remove()
	return
/datum/proc/op_window_interactive()
	return FALSE
/atom/proc/op_claim_changed()
	return
/mob/proc/op_notify(text)
	return
/mob/proc/op_uses_actor_stats()
	return FALSE
/mob/proc/op_hand_capable()
	return TRUE
/mob/proc/op_feedback_message(atom/target, msg, obj/held)
	return
/atom/proc/op_feedback_sound(sfx)
	return
