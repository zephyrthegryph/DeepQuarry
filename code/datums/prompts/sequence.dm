// Question sequences on native requests: a list of prompts asked one after another (doc/rewrite/final_api.html section 13). Moved off
// the object model's flows when it was retired; an op asks the same thing with several asks() steps.
//
//	start_ask_sequence(/datum/ask_sequence/pin_value, user, null, list(question_step("type_name", /datum/prompt/choice, question = "Type?", choices = types), PROC_REF(value_ask)), PROC_REF(value_entered), pin = src)
//
// `steps`: each is an question_step() spec, null (skipped), or a proc on the owner called as (sequence) that returns a spec, null to skip, or
// ASK_STOP to end there. Each answer (the request's value) lands in the sequence var named by its step's key when the type declares one,
// else in `answers` under the key (default: the step's index), read with get(key); later steps can depend on earlier answers. A step
// whose fields name an `answerer` asks that mob instead (consent from the other party). An optional step's cancel stores null and goes
// on; any other cancel, a "no" or a failed re-check ends the sequence and calls on_stop on the owner as (sequence, reason). When the last
// step is answered, on_done runs on the owner as (sequence). The owner is the caller's src; a /proc/ path is called globally with the
// same arguments. The sequence is deleted when it ends: its typed state is the owner's to copy in on_done.

/datum/ask_sequence
	var/list/steps
	var/step_index = 0
	/// key -> answer, for keys the type declares no var for.
	var/list/answers
	/// What step procs, on_done and on_stop run on (a plain reference: the sequence lives only while a question is open).
	var/datum/owner
	var/on_done
	var/on_stop
	/// Who answers by default (wrapped: never kept alive by the sequence).
	var/answerer_w
	/// What the questions are about (wrapped), or null.
	var/subject_w
	/// Fields every step's request also gets (rights, ask_flags, usable_state: the re-checks of the whole sequence).
	var/list/common_fields
	var/done = FALSE

/// The default answerer, or null when they are gone.
/datum/ask_sequence/proc/actor()
	return rerun_unwrap(answerer_w)

/// What the questions are about, or null.
/datum/ask_sequence/proc/subject()
	return rerun_unwrap(subject_w)

/// An answer so far, by key: the declared var, else from `answers`.
/datum/ask_sequence/proc/get(key)
	if(answers && (key in answers))
		return answers[key]
	if(sequence_var(key))
		return vars[key]
	return null

/// Stores an answer: in the declared var named `key`, else in `answers`.
/datum/ask_sequence/proc/put(key, value)
	if(sequence_var(key))
		vars[key] = value // ALLOW(api): a sequence's typed state set by the key its step declared
		return
	LAZYINITLIST(answers)
	answers[key] = value

/// TRUE when `key` names a var a subtype declares (its typed state).
/datum/ask_sequence/proc/sequence_var(key)
	var/static/list/base_vars
	if(!base_vars)
		var/datum/ask_sequence/plain = new
		base_vars = plain.vars.Copy()
	return istext(key) && (key in vars) && !(key in base_vars)

/datum/ask_sequence/proc/call_owner(proc_ref, ...)
	var/list/call_args = list(src) + args.Copy(2)
	if(copytext("[proc_ref]", 1, 7) == "/proc/")
		return call(proc_ref)(arglist(call_args))
	if(!owner || QDELETED(owner))
		return null
	return call(owner, proc_ref)(arglist(call_args))

/// Asks the next step, or runs on_done after the last.
/datum/ask_sequence/proc/next_step()
	if(done)
		return
	var/mob/user = actor()
	if(!user)
		return stop("gone")
	while(step_index < length(steps))
		step_index++
		var/list/step = steps[step_index]
		if(isnull(step))
			continue
		if(!islist(step))
			var/result = call_owner(step)
			if(result == ASK_STOP)
				return stop("stopped")
			if(isnull(result))
				continue
			step = result
		var/list/fields = (common_fields ? common_fields.Copy() : list()) + step["fields"]
		if(isnull(fields["timeout"]))
			fields["timeout"] = 0
		if(isnull(fields["answerer"]))
			fields["answerer"] = user
		if(isnull(fields["subject"]) && subject())
			fields["subject"] = subject()
		if(!request_open(src, step["type"], TYPE_PROC_REF(/datum/ask_sequence, step_answered), fields))
			stop("not asked")
		return
	done = TRUE
	if(on_done)
		call_owner(on_done)
	qdel(src) // ALLOW(lifecycle): a question sequence is a plain record that ends with its last answer

/datum/ask_sequence/proc/step_answered(datum/act/request/A)
	if(done)
		return
	var/list/step = steps[step_index]
	if(!islist(step))
		step = null
	var/key = step?["key"] || "[step_index]"
	if(!A.answer)
		if(step?["optional"])
			put(key, null)
			return next_step()
		return stop(A.request.outcome == REQ_TIMED_OUT ? "timed out" : "cancelled")
	if(ispath(A.request.type, /datum/prompt/yes_no) && !A.answer.value)
		return stop("declined")
	put(key, A.answer.value)
	next_step()

/// Ends the sequence early: on_stop runs once.
/datum/ask_sequence/proc/stop(reason = "stopped")
	if(done)
		return
	done = TRUE
	if(on_stop)
		call_owner(on_stop, reason)
	qdel(src) // ALLOW(lifecycle): a question sequence is a plain record that ends with its last answer

/// ask_sequence()'s body. `owner` is the caller's src. Returns the sequence, or a text reason it didn't start.
/proc/ask_sequence_begin(datum/owner, sequence, mob/answerer, datum/subject, list/steps, on_done, on_stop, list/common_fields, list/params)
	if(istype(answerer, /client))
		var/client/C = answerer
		answerer = C.mob
	if(!ismob(answerer))
		return "gone"
	var/datum/ask_sequence/S = ispath(sequence) ? new sequence : sequence
	if(!istype(S))
		CRASH("ask_sequence: [sequence] is not a /datum/ask_sequence")
	for(var/key in params)
		if(!(key in S.vars))
			CRASH("ask_sequence: [S.type] has no var [key]")
		S.vars[key] = params[key] // ALLOW(api): ask_sequence() named arguments set the sequence's own state
	S.owner = owner // ALLOW(ownership): a plain reference: the sequence lives only while one of its questions is open
	S.steps = steps
	S.on_done = on_done
	S.on_stop = on_stop
	S.common_fields = common_fields
	S.answerer_w = rerun_wrap(answerer)
	S.subject_w = subject ? rerun_wrap(subject) : null
	S.next_step()
	return S
