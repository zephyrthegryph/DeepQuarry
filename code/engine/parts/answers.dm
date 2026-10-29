// Answer requirements (doc/rewrite/final_api.html, section 9 "Conditions and requirements" and section 13 "Requests, prompts and workflows").
//
// An op that asks (asks()) often refuses on what it was told: a label too long, a count that cannot be split off, a belly that is gone. That refusal is a
// requirement, not a message and a return at the head of the effect:
//
//   op("label", inputs(...), asks(/datum/prompt/text, fields = list("question" = "Enter a label:"), step = "label"),
//       needs(req_answer(PROC_REF(label_refusal), step = "label")), then(PROC_REF(label_applied)))
//
//   /obj/x/proc/label_refusal(datum/act/op/A)          // pure: reads A.answer (or A.step_value("label")), returns null to allow or a reason
//       return length("[A.answer.value]") > 50 ? MSG(x/label_too_long) : null
//
// The requirement holds while its step has not been answered (the op's first Require, before the question opens, and any later step's check), so it
// costs nothing before the question. Once the step is answered it is evaluated against the answer: right after it arrives (a refused answer ends the op
// there, the actor told the reason, the later steps never asked) and again at commit, with every other requirement (the recheck every wait and answer
// runs). A step that ended on asks(optional = TRUE)'s default counts as answered with that default.

/// req_answer(PROC_REF(x), step = null, because = null): `x(datum/act/op/A)` is pure (it reads A.answer, the latest answered request, or
/// A.step_value("name"), and writes nothing) and returns null to allow, or the reason (a /datum/msg type or text). `step` names the asks() step it
/// judges (null: the latest answer of whatever step); `because` replaces the reason x returns.
/proc/req_answer(check, step = null, because = null, id = null)
	return part_make(/datum/entry/part/req/answer, list("check" = check, "step" = step, "because" = because, "id" = id))

/datum/entry/part/req/answer
	part_name = "req_answer"

/// The answered request this requirement judges, or null while its step is open or not yet reached.
/datum/entry/part/req/answer/proc/judged(datum/act/op/A)
	RETURN_TYPE(/datum/request)
	var/step = src.args["step"]
	if(isnull(step))
		return A.answer
	return A.step_answer(step)

/datum/entry/part/req/answer/holds(datum/act/op/A)
	if(isnull(judged(A)))
		return TRUE
	return isnull(op_call(A, src.args["check"]))

/datum/entry/part/req/answer/refusal(datum/act/op/A)
	if(!isnull(src.args["because"]))
		return ..()
	return req_refusal_value(op_call(A, src.args["check"]), default_reason)
