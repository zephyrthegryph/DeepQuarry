// Legacy spellings and subtype paths retain compatibility; implementation lives in the engine.

/datum/om/check/combinator
	parent_type = /datum/requirement_definition/combinator
	abstract_type = /datum/om/check/combinator

/proc/om_check_get(spec, datum/om/registry/reg)
	return definition_check_get(arglist(args))

/proc/om_spec_key(spec, datum/om/registry/reg)
	return definition_spec_key(arglist(args))

/proc/om_why_not(spec, datum/actor, datum/target)
	return definition_why_not(arglist(args))

/proc/om_can(spec, datum/actor, datum/target)
	return definition_can(arglist(args))
