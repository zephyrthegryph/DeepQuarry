// Requests and waiting (doc/rewrite/final_api.html, section 2 "Requests and waiting" and section 13; section 19 "E6").
//
// /datum/request is anything that waits for an answer: a prompt (a player answers), a backend request (/datum/io/*) or a client
// round trip (/datum/client_query/*). One concept, one outcome enum (REQ_*), one resumption rule:
//
//     open_request(owner, /datum/prompt/yes_no/x, PROC_REF(done), valid = PROC_REF(still_open), timeout = 30 SECONDS, answerer = M)
//
// done(datum/act/request/A) runs when the request ends, whatever its outcome: A.request is the request (A.request.outcome says
// how it ended) and A.answer is the same request when it was answered, else null. A handler never keeps A past its return.
// valid(datum/request/R) is asked when the answer arrives (a request() outside an op has no op requirements to re-run): a FALSE
// answer ends the request as REQ_CANCELLED. A request ends cancelled when its owner or its answerer is gone, and as REQ_TIMED_OUT
// when its timeout passes first.
//
// The test driver's test_answer() is request_answer(): it answers the actor's oldest open request, or ends it with an outcome,
// and returns the /datum/op_result of the op that was waiting on it (the op engine, E2, sets `waiting` when an asks() suspends).

/// The kinds a request comes in. They are requests (parent_type), not paths under /datum/request.
/datum/prompt
	parent_type = /datum/request
	abstract_type = /datum/prompt

/datum/io
	parent_type = /datum/request
	abstract_type = /datum/io

/datum/client_query
	parent_type = /datum/request
	abstract_type = /datum/client_query

/datum/request
	/// The entity that asked. A plain reference: the registry's sweep ends the request cancelled once the owner is deleted,
	/// and ending it deletes the request, so the reference is held a second past the owner's death at most.
	var/datum/owner
	/// Who answers a prompt: a mob. Null for a backend request.
	var/mob/answerer
	/// TRUE when the request was opened with an answerer: its death ends the request (REQ_CANCELLED).
	var/answerer_expected = FALSE
	/// What the answerer gave, or the backend's answer: the one answer field every request kind is read through (A.answer.value).
	var/value
	/// A PROC_REF on the owner: handler(datum/act/request/A), run when the request ends.
	var/handler
	/// A PROC_REF on the owner: valid(datum/request/R) re-checked when the answer arrives.
	var/valid
	/// Deciseconds until it ends as REQ_TIMED_OUT; 0 waits for ever.
	var/timeout = 0
	/// world.time it was opened at.
	var/opened_at = 0
	/// The op the request suspended (E2): its /datum/op_result carries the outcome once the request ends and the op resumes.
	var/datum/op_result/waiting
	/// The fields captured when the op first suspended (name -> value): the op uses what the player saw.
	var/list/captured
	/// The re-checks of the answer (ASK_*): who must still be alive, awake, able, near or holding something when it arrives, else the request ends cancelled.
	var/ask_flags = 0
	/// Who started the question, for the re-checks (null: the answerer). A plain reference like the owner's: a gone one fails the check.
	var/mob/asker
	/// What the question is about, for the re-checks (null: the owner, when it is an atom).
	var/atom/subject
	/// Admin rights (R_* flags) the answerer's player must still hold; 0 asks none, any other value needs them (check_rights_for).
	var/rights = 0
	/// A tgui state name (GLOB.tgui_<name>_state: "default", "physical", ...) the answerer must still be able to work the subject through.
	var/usable_state
	/// A backend request's failure text (REQ_TRANSPORT_FAILED, REQ_FAILED), for the log.
	var/last_error
	/// TRUE: the re-checks (ask_flags, rights, usable_state, recheck_extra()) also run when the request opens, and one that
	/// fails ends it REQ_CANCELLED before it is shown (an admin prompt whose asker lost the rights, a target already gone).
	var/recheck_on_open = FALSE
	/// What answering costs (RES_X -> amount), for a request outside an op (doc/rewrite/final_api.html, section 9 "Resource transactions"): the
	/// require half is asked when it opens (a request that cannot be paid for is not opened, and the payer is told why), the amounts are reserved
	/// from `payer` once a confirming answer arrives, and committed after the handler, unless it returned OP_REFUSED or OP_FAILED (released). An
	/// answer that can no longer be paid for ends the request REQ_CANCELLED with nothing spent.
	var/list/costs
	/// Who pays the costs (null: the answerer).
	var/datum/payer
	/// The reservations held while the handler runs.
	var/list/reservations

/// Whether the answer goes ahead with the request's costs: any answer does; a yes/no only on yes.
/datum/request/proc/confirmed()
	return TRUE

/// A kind's own re-check of an answer when it arrives: null, or why the answer is dropped. Reads only.
/datum/request/proc/recheck_extra()
	return null

/// A request that has ended can not be answered again.
/datum/request/proc/is_open()
	return isnull(outcome) && !QDELETED(src)

/// A backend request (code/engine/io/) starts its work here, once it is open and registered: the base does nothing (a prompt
/// waits for its answerer).
/datum/request/proc/begin()
	return

/// The backend could not take the request (no connection, nowhere to send it): it ends as REQ_TRANSPORT_FAILED on the next
/// tick, never inside the call that opened it, so the caller always holds an open request first.
/datum/request/proc/fail_transport(why)
	last_error = why
	after(src, 1 TICK, TYPE_PROC_REF(/datum/request, transport_failed), key = "request_begin")

/datum/request/proc/transport_failed()
	request_end(src, REQ_TRANSPORT_FAILED, null)

/// The owner is being deleted: the request ends cancelled now (its handler is skipped: there is no owner to run it on).
/datum/request/proc/owner_deleted(datum/act/A)
	log_game("request: [type] ended cancelled: its owner [owner?.type] was deleted while it was open")
	request_end(src, REQ_CANCELLED, null)

/// The timeout passed before anything answered.
/datum/request/proc/timed_out()
	request_end(src, REQ_TIMED_OUT, null)

// ---------------------------------------------------------------- the registry

SYSTEM_DEF(requests)
	name = "Requests"
	phase = KERNEL_PHASE_P
	latency_class = LATENCY_L1
	init_stage = INITSTAGE_FIRST
	/// Every open request, oldest first.
	var/list/open = list()
	/// Counters since boot: opened, ended by each outcome.
	var/opened = 0
	var/answered = 0
	var/cancelled = 0
	var/timed_out = 0
	var/transport_failed = 0

/datum/system/requests/reactions()
	. = ..()
	// A request whose owner or answerer died ends cancelled: swept once a second, so nothing waits for ever on a dead entity.
	. += every(1 SECONDS, PROC_REF(sweep), when = PROC_REF(has_open))

/datum/system/requests/proc/has_open()
	return length(open) > 0

/datum/system/requests/proc/sweep(dt)
	for(var/datum/request/R as anything in open.Copy())
		if(!R.is_open())
			open -= R
			continue
		if(QDELETED(R.owner) || (R.answerer_expected && QDELETED(R.answerer)))
			request_end(R, REQ_CANCELLED, null)
	return STEP_DONE

/// The oldest open request `answerer` is to answer, or null. `op_key` narrows it to the question of the pending op of that key (an actor may have several open).
/datum/system/requests/proc/open_for(datum/answerer, op_key = null)
	for(var/datum/request/R as anything in open)
		if(R.answerer != answerer || !R.is_open())
			continue
		if(!isnull(op_key))
			var/datum/pending_op/asking = R.owner
			if(!istype(asking) || asking.key != op_key)
				continue
		return R
	return null

/datum/system/requests/metrics()
	. = ..()
	.["open"] = length(open)
	.["opened"] = opened
	.["answered"] = answered
	.["cancelled"] = cancelled
	.["timed_out"] = timed_out
	.["transport_failed"] = transport_failed

// ---------------------------------------------------------------- opening and ending

/// Opens a request of `request_type` for `owner` (the open_request() macro, code/__defines/kernel.dm). `fields` are the named
/// arguments, each a var of the request type (`answerer = M`, `timeout = 30 SECONDS`, `role = R`) or `valid`, a PROC_REF on
/// `owner`; an unknown name is a CRASH. `handler` is a PROC_REF on `owner`. Returns the open request, or null when it could not
/// open (the owner is already gone).
/proc/request_open(datum/owner, request_type, handler, list/fields, datum/act/context = null)
	RETURN_TYPE(/datum/request)
	if(!ispath(request_type, /datum/request))
		CRASH("open_request(): [request_type] is not a request kind (/datum/prompt, /datum/io, /datum/client_query)")
	if(!owner || QDELETED(owner))
		return null
	var/datum/request/R = new request_type
	var/valid = null
	for(var/name in fields)
		var/value = fields[name]
		if(name == "valid")
			valid = value
			continue
		if(isnull(value))
			continue
		if(!istext(name))
			CRASH("open_request(): [request_type] was given a positional argument ([name]); name it (field = value)")
		if(name == "owner" || name == "handler")
			CRASH("open_request(): [name] is not a field")
		if(!(name in R.vars))
			CRASH("open_request(): [request_type] has no field [name]")
		if(name == "outcome")
			CRASH("open_request(): outcome is the engine's to set")
		R.vars[name] = value // ALLOW(api): open_request() named arguments: typed request fields by name
	R.owner = owner // ALLOW(ownership): a transient reference: the request is deleted when it ends, and the act is pooled and reset on release
	R.handler = handler
	R.valid = valid
	R.opened_at = world.time // ALLOW(sys_world_time_write): the request's own open stamp, read for diagnostics, not an expiry
	R.answerer_expected = !isnull(R.answerer)
	// Every request ends: one given no timeout gets the default (a request with none pins its owner until the owner dies), logged once per kind so a
	// caller that should name its own is found. timeout = REQUEST_NO_TIMEOUT is the explicit opt-out.
	if(R.timeout == 0)
		R.timeout = REQUEST_DEFAULT_TIMEOUT
		var/static/list/defaulted = list()
		if(!defaulted[R.type])
			defaulted[R.type] = TRUE
			log_game("request: [R.type] opened without a timeout: it times out after [REQUEST_DEFAULT_TIMEOUT / (1 SECOND)] s (pass timeout = ... to choose, REQUEST_NO_TIMEOUT to opt out)")
#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)
	// A test that records the prompts it causes (test_prompts_reset()) sees every one opened, in order.
	if(islist(GLOB.test_prompts) && istype(R, /datum/prompt))
		GLOB.test_prompts += R
#endif
	var/datum/system/requests/registry = SSrequests
	registry.open += R
	registry.opened++
	if(R.timeout > 0)
		after(R, R.timeout, TYPE_PROC_REF(/datum/request, timed_out), key = "request_timeout")
	// The owner's deletion ends the request at once (its qdeleting notice), not at the next sweep: the prompt must not stay up, and an answer must not
	// reach a handler that is gone. The sweep stays as the backstop for a notice that never came.
	observe(owner, /datum/notice/qdeleting, R, then(TYPE_PROC_REF(/datum/request, owner_deleted)))
	R.prepare(context)
	if(R.recheck_on_open && request_recheck(R))
		request_end(R, REQ_CANCELLED, null)
		return R
	if(length(R.costs))
		var/why = request_costs_refusal(R)
		if(why)
			op_tell(request_payer(R), why)
			log_game("request: [R.type] not opened: its costs cannot be paid ([reason_text(why)])")
			registry.open -= R
			cancel_after(R, "request_timeout")
			unobserve(owner, /datum/notice/qdeleting, R)
			qdel(R) // ALLOW(lifecycle): a request is a plain datum with no lifecycle verb: one that never opened is deleted at once
			return null
	R.begin()
	return R

/// Who pays a request's costs: its payer, else its answerer.
/proc/request_payer(datum/request/R)
	return R.payer || R.answerer

/// A transient context for a request's resource adapters (they read A.actor, A.held, A.key, as an op's do). The caller releases it.
/proc/request_cost_context(datum/request/R)
	RETURN_TYPE(/datum/act/op)
	var/datum/act/op/A = take(/datum/act/op)
	var/datum/payer = request_payer(R)
	A.holder = payer // ALLOW(ownership): a pooled transient: reset on release
	A.actor = ismob(payer) ? payer : null
	A.target = R.owner
	A.key = "request:[R.type]"
	return A

/// null when every cost of `R` could be reserved now, else the first refusal (the require half of costs: nothing is set aside). Reads only.
/proc/request_costs_refusal(datum/request/R)
	var/datum/act/op/A = request_cost_context(R)
	. = null
	for(var/res_id in R.costs)
		var/amount = R.costs[res_id]
		var/datum/resource/RS = resource_of(text2num("[res_id]"))
		if(!RS)
			stack_trace("request [R.type]: no adapter for resource [res_id]")
			. = /datum/msg/op/no_resource
			break
		if(!isnum(amount) || amount <= 0)
			continue
		var/datum/payer = RS.holder_of(A)
		if(!payer || RS.available(A) - reserved_total(payer, RS.res_id) < amount)
			. = RS.refusal(A, amount)
			break
	A.release()

/// Reserves every cost of `R` (all or nothing). TRUE when they are held in R.reservations.
/proc/request_costs_reserve(datum/request/R)
	var/datum/act/op/A = request_cost_context(R)
	var/list/held = list()
	. = TRUE
	for(var/res_id in R.costs)
		var/amount = R.costs[res_id]
		if(!isnum(amount) || amount <= 0)
			continue
		var/datum/resource/RS = resource_of(text2num("[res_id]"))
		var/datum/reservation/reserved = RS?.reserve(A, amount)
		if(!reserved)
			R.last_error = reason_text(RS ? RS.refusal(A, amount) : /datum/msg/op/no_resource)
			. = FALSE
			break
		held += reserved
	A.release()
	if(!.)
		for(var/datum/reservation/reserved as anything in held)
			reservation_release(reserved)
		return
	R.reservations = held

/// Ends the reservations of `R`: committed after a handler that went through, released after one that refused.
/proc/request_costs_settle(datum/request/R, commit)
	for(var/datum/reservation/reserved as anything in R.reservations)
		if(commit)
			if(reservation_commit(reserved) != OP_OK)
				log_game("request: [R.type] could not spend its [reserved.amount] of resource [reserved.res_id]")
		else
			reservation_release(reserved)
	R.reservations = null

/// A player's answer to prompt `R` (a window): normalised and checked first. Returns null when it ended the request answered, else the reason it was
/// refused (the prompt stays open for another try). The test driver's request_answer() goes through here too.
/proc/request_submit(datum/request/R, answer)
	if(!istype(R) || !R.is_open())
		return "that question is closed"
	var/datum/prompt/P = R
	if(istype(P))
		answer = P.normalize(answer)
		var/why = P.refusal(answer)
		if(why)
			P.last_error = why
			log_game("prompt: [P.type] refused an answer: [why]")
			return why
	request_end(R, REQ_ANSWERED, answer)
	return null

/// null when the answer to `R` may stand, else why it may not: the re-checks of ask_flags, rights and usable_state against the roles the request
/// names (the asker defaults to the answerer, the subject to the owner when that is an atom). Reads only.
/proc/request_recheck(datum/request/R)
	return R.check_context()

/// Library implementations supply gameplay and UI policy checks.
/datum/request/proc/check_context()
	return recheck_extra()

/// Ends `R` with `outcome` and runs its handler. Returns TRUE when this call ended it, FALSE when it had already ended.
/// An answer that no longer passes its valid() check ends as REQ_CANCELLED.
/proc/request_end(datum/request/R, outcome, value)
	if(!istype(R) || !R.is_open())
		return FALSE
	var/datum/system/requests/registry = SSrequests
	registry.open -= R
	if(outcome == REQ_ANSWERED && QDELETED(R.owner))
		log_game("request: [R.type] answer dropped: its owner was deleted")
		outcome = REQ_CANCELLED
	if(outcome == REQ_ANSWERED)
		R.value = value
		if(R.valid && R.owner && !call(R.owner, R.valid)(R))
			outcome = REQ_CANCELLED
		var/recheck = outcome == REQ_ANSWERED ? request_recheck(R) : null
		if(recheck)
			R.last_error = recheck
			log_game("request: [R.type] answer dropped: [recheck]")
			outcome = REQ_CANCELLED
		if(outcome == REQ_ANSWERED && length(R.costs) && R.confirmed() && !request_costs_reserve(R))
			op_tell(request_payer(R), R.last_error)
			log_game("request: [R.type] answer dropped: its costs could not be reserved ([R.last_error])")
			outcome = REQ_CANCELLED
	R.outcome = outcome
	if(istype(R, /datum/prompt))
		var/datum/prompt/prompt_ended = R
		prompt_ended.dismiss()
	switch(outcome)
		if(REQ_ANSWERED)
			registry.answered++
		if(REQ_CANCELLED)
			registry.cancelled++
		if(REQ_TIMED_OUT)
			registry.timed_out++
		if(REQ_TRANSPORT_FAILED)
			registry.transport_failed++
	cancel_after(R, "request_timeout")
	if(R.owner && !QDELETED(R.owner))
		unobserve(R.owner, /datum/notice/qdeleting, R)
	if(R.owner && !QDELETED(R.owner) && R.handler)
		var/datum/act/request/A = take(/datum/act/request)
		A.holder = R.owner // ALLOW(ownership): a transient reference: the request is deleted when it ends, and the act is pooled and reset on release
		A.request = R // ALLOW(ownership): a transient reference: the request is deleted when it ends, and the act is pooled and reset on release
		A.answer = (outcome == REQ_ANSWERED) ? R : null // ALLOW(ownership): a transient reference: the request is deleted when it ends, and the act is pooled and reset on release
		// The kernel isolates a faulting handler: the act is released and the request ends whatever the handler did, so a
		// callback never wraps its own body in safe_call().
		var/handled = OP_FAILED
		try
			handled = call(R.owner, R.handler)(A)
		catch(var/exception/fault) // ALLOW(silent_catch): the request kernel's isolation point: one handler's runtime must not leak the act or the request
			kernel().report_fault(fault, "request [R.type] handler [R.handler] on [R.owner.type]: [fault] ([fault.file]:[fault.line])")
		A.release()
		if(R.reservations)
			request_costs_settle(R, handled != OP_REFUSED && handled != OP_FAILED)
	if(R.reservations) // the owner went before the handler could run: nothing is spent
		request_costs_settle(R, FALSE)
	request_op_resume(R)
	// Ended: the request and its timer are done with; what a caller kept (R.outcome, R.value) stays readable.
	qdel(R) // ALLOW(lifecycle): a request is a plain datum with no lifecycle verb: ending it is its deletion
	return TRUE

/// The op engine resumes the op that was waiting on `R` through the handler it opened the request with (code/engine/parts/run.dm,
/// /datum/pending_op/request_done), which runs before this seam: nothing is left to do here.
/proc/request_op_resume(datum/request/R)
	return

/// Answers `actor`'s oldest open request (the one of the op named `op_key`, when given) with `value`, or ends it with `outcome` (REQ_CANCELLED, REQ_TIMED_OUT). Returns the
/// /datum/op_result of the op that was waiting (the record an earlier call handed out, now advanced), or null when the request
/// had no op waiting or `actor` has nothing open.
/proc/request_answer(datum/actor, value, outcome = REQ_ANSWERED, op_key = null)
	RETURN_TYPE(/datum/op_result)
	var/datum/request/R = SSrequests.open_for(actor, op_key)
	if(!R)
		return null
	var/datum/op_result/waiting = R.waiting
	if(outcome == REQ_ANSWERED)
		request_submit(R, value) // a refused answer leaves the prompt (and the op waiting on it) open
	else
		request_end(R, outcome, value)
	return waiting
