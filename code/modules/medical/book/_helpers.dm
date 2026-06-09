// DQ Medical Reference — shared helper(s) that don't fit a single tab.
//
// _dq_condition_name() resolves a /datum/medical_issue/condition
// typepath to its display name by reading the prototype. Used from
// multiple tab builders (conditions complications, causes produces,
// surgeries treats) to render condition cross-links.

/proc/_dq_condition_name(typepath)
	if(!ispath(typepath, /datum/medical_issue/condition))
		return "[typepath]"
	var/datum/medical_issue/condition/proto = dq_proto(typepath)
	return proto.name
