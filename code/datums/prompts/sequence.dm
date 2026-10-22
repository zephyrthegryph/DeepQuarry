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
	/// The spec of the question open now (a step proc's answer is stored under the key and flags of the spec it returned).
	var/list/open_step
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
	/// TRUE when the step procs are procs of the sequence itself (called without the sequence argument): a self-contained set of questions.
	var/self_owned = FALSE
	/// TRUE when the owner's procs run with the answerer as usr (admin tools whose code still reads usr).
	var/as_actor = FALSE
	/// The sequence waiting for this one (wrapped), and the key this one's `result` is stored under in it.
	var/parent_w
	var/result_key
	/// The caller's own state for its on_done (a list the sequence never reads).
	var/list/kept

CAPABILITIES(/datum/ask_sequence)
	ref_one(nameof(owner))

/// The default answerer, or null when they are gone.
/datum/ask_sequence/proc/actor()
	RETURN_TYPE(/mob)
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

/// The steps a sequence type asks when its starter names none (a self-contained set of questions).
/datum/ask_sequence/proc/initial_steps()
	return null

/datum/ask_sequence/proc/call_owner(proc_ref, ...)
	return call_on_owner(FALSE, proc_ref, args.Copy(2))

/// Calls a step proc: on the sequence itself when it is self_owned, else like call_owner().
/datum/ask_sequence/proc/call_step(proc_ref)
	return call_on_owner(self_owned, proc_ref, list())

/datum/ask_sequence/proc/call_on_owner(on_self, proc_ref, list/rest)
	var/list/call_args = on_self ? rest : list(src) + rest
	var/global_proc = copytext("[proc_ref]", 1, 7) == "/proc/"
	var/datum/target = on_self ? src : owner
	if(!global_proc && (!target || QDELETED(target)))
		return null
	var/mob/who = as_actor ? actor() : null
	if(who)
		return with_actor(arglist(list(who, global_proc ? GLOBAL_PROC : target, proc_ref) + call_args))
	if(global_proc)
		return call(proc_ref)(arglist(call_args))
	return call(target, proc_ref)(arglist(call_args))

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
			var/asked = call_step(step)
			if(asked == ASK_STOP)
				return stop("stopped")
			if(asked == ASK_WAIT) // a child sequence answers; it calls resume()
				return
			if(asked == ASK_FINISH)
				return finish()
			if(isnull(asked))
				continue
			step = asked
		open_step = step
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
	finish()

/// Ends the sequence successfully: on_done runs on the owner, then the sequence waiting for this one goes on.
/datum/ask_sequence/proc/finish()
	if(done)
		return
	done = TRUE
	if(on_done)
		call_owner(on_done)
	deliver(TRUE)

/// Goes on to the next step (a step that returned ASK_WAIT, once its child sequence is answered).
/datum/ask_sequence/proc/resume()
	if(done)
		return
	next_step()

/// Puts `more` (steps) right after the step open now.
/datum/ask_sequence/proc/add_steps(list/more)
	steps = steps.Copy(1, step_index + 1) + more + steps.Copy(step_index + 1)

/// A step proc's way to ask a whole other set of questions of the same answerer: starts `child_type` (it asks its initial_steps()), and the child's `result` lands under `key` here
/// when it finishes; a child that stops stops this sequence. Returns ASK_WAIT: the step returns it.
/datum/ask_sequence/proc/ask_child(child_type, key, list/params)
	var/list/child_params = params ? params.Copy() : list()
	child_params["parent_w"] = rerun_wrap(src)
	child_params["result_key"] = key
	var/started = ask_sequence_begin(owner, child_type, actor(), subject(), null, null, null, common_fields, child_params)
	if(istext(started))
		stop(started)
	return ASK_WAIT

/// What this sequence hands the sequence waiting for it (kept as the answer "result", read with get("result")).
/datum/ask_sequence/proc/set_result(value)
	put("result", value)

/// Hands the end of this sequence to the one waiting for it.
/datum/ask_sequence/proc/deliver(ok, reason)
	if(isnull(parent_w))
		return
	var/datum/ask_sequence/waiting = rerun_unwrap(parent_w)
	parent_w = null
	if(!istype(waiting))
		return
	if(!ok)
		return waiting.stop(reason)
	waiting.put(result_key, get("result"))
	waiting.resume()

/datum/ask_sequence/proc/step_answered(datum/act/request/A)
	if(done)
		return
	var/list/step = open_step
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
	deliver(FALSE, reason)

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
	rel_set(S, nameof(S.owner), owner)
	S.steps = steps || S.initial_steps()
	S.on_done = on_done
	S.on_stop = on_stop
	S.common_fields = common_fields
	S.answerer_w = rerun_wrap(answerer)
	S.subject_w = subject ? rerun_wrap(subject) : null
	S.next_step()
	return S

/// The answers of an admin verb's questions (ask_steps()), read with get(key).
/datum/ask_sequence/admin_verb

/// Starts the questions of an ADMIN_VERB body (`src` is the verb): the verb's rights are re-checked as each question opens and is answered. `on_done` is a PROC_REF
/// on the verb called as (sequence); the verb's code after the questions lives there, and reads the answers with sequence.get(key).
/datum/admin_verb/proc/ask_steps(client/user, sequence, list/steps, on_done, list/params)
	if(!user?.mob)
		return "gone"
	var/started = ask_sequence_begin(src, sequence, user.mob, null, steps, on_done, null, list("rights" = permissions, "recheck_on_open" = TRUE), params)
	if(istext(started))
		log_admin("[key_name(user)]: [type] did not ask its questions ([started])")
	return started
