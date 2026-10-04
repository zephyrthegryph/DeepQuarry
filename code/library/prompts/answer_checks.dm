// What a question needs to still hold when its answer arrives, for a request opened outside an op (code/engine/kernel/requests.dm: valid(), "a request()
// outside an op has no op requirements to re-run"). A prompt opened by an op's asks() gets its op's requirements again; a verb, a window button or a
// timer that opens a question with open_request() names its own check:
//
//   open_request(src, /datum/prompt/choice, PROC_REF(tool_chosen), answerer = user, valid = PROC_REF(still_carried), choices = options, timeout = 0)
//
//   /obj/item/thing/proc/still_carried(datum/request/R)
//       return answerer_holds(R, ANSWER_CARRIED | ANSWER_CAPABLE, src)
//
// The conditions are the ones the old typed prompts re-checked (their ask_flags), read when the answer arrives:
//
//   ANSWER_ALIVE         the answerer and the asker are alive
//   ANSWER_CONSCIOUS     both are conscious
//   ANSWER_CAPABLE       neither is incapacitated
//   ANSWER_UNRESTRAINED  neither is restrained
//   ANSWER_ADJACENT      the answerer is next to the asker (next to the subject when they are the same mob)
//   ANSWER_NEAR_SUBJECT  the subject is next to the answerer
//   ANSWER_HELD          the subject is in one of the asker's hands
//   ANSWER_CARRIED       the subject is somewhere on the asker (held, worn, in a bag)
//
// The flags are in code/__defines/answer_checks.dm. The answerer is `R.answerer`; the asker is `asker` (default: the answerer); the subject is what the question is about. A deleted subject or asker
// fails every condition that reads it.

/// TRUE when every condition of `flags` holds for the request's answerer, `asker` and `subject` now. Reads only.
/proc/answerer_holds(datum/request/R, flags = NONE, atom/subject = null, mob/asker = null)
	var/mob/answerer = R.answerer
	asker = asker || answerer
	if(flags & (ANSWER_ALIVE | ANSWER_CONSCIOUS | ANSWER_CAPABLE | ANSWER_UNRESTRAINED | ANSWER_ADJACENT | ANSWER_NEAR_SUBJECT))
		if(!ismob(answerer) || !ismob(asker) || QDELETED(answerer) || QDELETED(asker))
			return FALSE
	if((flags & ANSWER_ALIVE) && (answerer.stat == DEAD || asker.stat == DEAD))
		return FALSE
	if((flags & ANSWER_CONSCIOUS) && (answerer.stat != CONSCIOUS || asker.stat != CONSCIOUS))
		return FALSE
	if((flags & ANSWER_CAPABLE) && (answerer.incapacitated() || asker.incapacitated()))
		return FALSE
	if((flags & ANSWER_UNRESTRAINED) && (answerer.restrained() || asker.restrained()))
		return FALSE
	if(flags & ANSWER_ADJACENT)
		var/atom/other = (asker != answerer) ? asker : subject
		if(!istype(other) || QDELETED(other) || !answerer.Adjacent(other))
			return FALSE
	if((flags & ANSWER_NEAR_SUBJECT) && (!istype(subject) || QDELETED(subject) || !answerer.Adjacent(subject)))
		return FALSE
	if(flags & ANSWER_HELD)
		if(!ismob(asker) || QDELETED(subject) || (asker.get_active_hand() != subject && asker.get_inactive_hand() != subject))
			return FALSE
	if(flags & ANSWER_CARRIED)
		if(!istype(subject, /atom/movable) || QDELETED(subject) || !ismob(asker))
			return FALSE
		var/found = FALSE
		for(var/atom/holder = subject.loc; holder; holder = holder.loc)
			if(holder == asker)
				found = TRUE
				break
		if(!found)
			return FALSE
	return TRUE
