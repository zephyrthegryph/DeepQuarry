#define CAPABILITIES(T, entries...)
#define TRACKED(T, V) ##T/proc/set_##V(value) { V = value }
#define TRUE 1
#define FALSE 0

/datum/act
/datum/act/op
/datum/msg/refusal
/datum/probe
	var/available = TRUE

TRACKED(/datum/probe, available)

CAPABILITIES(/datum/probe,
	op("use", needs(req(PROC_REF(null_answer)), req(PROC_REF(bare_answer)), req(PROC_REF(text_answer)), req(PROC_REF(datum_answer)), req(PROC_REF(boolean_answer)), req(PROC_REF(list_answer)), req_bool(PROC_REF(old_boolean)), req_bool(PROC_REF(old_text), because = PROC_REF(old_reason))))
)

/datum/probe/proc/null_answer(datum/act/op/A)
	return null

/datum/probe/proc/bare_answer(datum/act/op/A)
	return

/datum/probe/proc/text_answer(datum/act/op/A)
	return available ? null : "Unavailable"

/datum/probe/proc/datum_answer(datum/act/op/A)
	return /datum/msg/refusal

/datum/probe/proc/boolean_answer(datum/act/op/A)
	return TRUE

/datum/probe/proc/list_answer(datum/act/op/A)
	return list()

/datum/probe/proc/old_boolean(datum/act/op/A)
	return available

/datum/probe/proc/old_text(datum/act/op/A)
	return "Unavailable"

/datum/probe/proc/old_reason(datum/act/op/A)
	return "Unavailable"
