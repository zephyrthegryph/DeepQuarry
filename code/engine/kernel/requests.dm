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
	var/datum/answerer
	/// TRUE when the request was opened with an answerer: its death ends the request (REQ_CANCELLED).
	var/answerer_expected = FALSE
	/// What the answerer gave, or the backend's answer. Read it through A.answer.
	var/answer_value
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
	/// A backend request's failure text (REQ_TRANSPORT_FAILED, REQ_FAILED), for the log.
	var/last_error

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

/// The oldest open request `answerer` is to answer, or null.
/datum/system/requests/proc/open_for(datum/answerer)
	for(var/datum/request/R as anything in open)
		if(R.answerer == answerer && R.is_open())
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
	var/datum/system/requests/registry = SSrequests
	registry.open += R
	registry.opened++
	if(R.timeout > 0)
		after(R, R.timeout, TYPE_PROC_REF(/datum/request, timed_out), key = "request_timeout")
	R.prepare(context)
	R.begin()
	return R

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

/// Ends `R` with `outcome` and runs its handler. Returns TRUE when this call ended it, FALSE when it had already ended.
/// An answer that no longer passes its valid() check ends as REQ_CANCELLED.
/proc/request_end(datum/request/R, outcome, value)
	if(!istype(R) || !R.is_open())
		return FALSE
	var/datum/system/requests/registry = SSrequests
	registry.open -= R
	if(outcome == REQ_ANSWERED)
		R.answer_value = value
		if(R.valid && R.owner && !call(R.owner, R.valid)(R))
			outcome = REQ_CANCELLED
	R.outcome = outcome
	if(istype(R, /datum/prompt))
		var/datum/prompt/prompt_ended = R
		if(outcome == REQ_ANSWERED)
			prompt_ended.value = R.answer_value
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
	if(R.owner && !QDELETED(R.owner) && R.handler)
		var/datum/act/request/A = take(/datum/act/request)
		A.holder = R.owner // ALLOW(ownership): a transient reference: the request is deleted when it ends, and the act is pooled and reset on release
		A.request = R // ALLOW(ownership): a transient reference: the request is deleted when it ends, and the act is pooled and reset on release
		A.answer = (outcome == REQ_ANSWERED) ? R : null // ALLOW(ownership): a transient reference: the request is deleted when it ends, and the act is pooled and reset on release
		call(R.owner, R.handler)(A)
		A.release()
	request_op_resume(R)
	// Ended: the request and its timer are done with; what a caller kept (R.outcome, R.answer_value) stays readable.
	qdel(R) // ALLOW(lifecycle): a request is a plain datum with no lifecycle verb: ending it is its deletion
	return TRUE

/// The op engine resumes the op that was waiting on `R` through the handler it opened the request with (code/engine/parts/run.dm,
/// /datum/pending_op/request_done), which runs before this seam: nothing is left to do here.
/proc/request_op_resume(datum/request/R)
	return

/// Answers `actor`'s oldest open request with `value`, or ends it with `outcome` (REQ_CANCELLED, REQ_TIMED_OUT). Returns the
/// /datum/op_result of the op that was waiting (the record an earlier call handed out, now advanced), or null when the request
/// had no op waiting or `actor` has nothing open.
/proc/request_answer(datum/actor, value, outcome = REQ_ANSWERED)
	RETURN_TYPE(/datum/op_result)
	var/datum/request/R = SSrequests.open_for(actor)
	if(!R)
		return null
	var/datum/op_result/waiting = R.waiting
	if(outcome == REQ_ANSWERED)
		request_submit(R, value) // a refused answer leaves the prompt (and the op waiting on it) open
	else
		request_end(R, outcome, value)
	return waiting
