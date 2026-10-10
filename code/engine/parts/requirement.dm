// The shared requirement protocol used by native operation parts and downstream adapters.
// holds() remains the boolean view needed by existing consumers; check() is null when allowed, or a refusal reason.

/datum/requirement
	/// The reason this requirement fails with (a /datum/msg type), unless test() returns another.
	var/reason = /datum/msg/req_failed
	/// OP_ACTOR / OP_TARGET / OP_HELD / OP_PROVIDER: whose state this reads.
	var/of = OP_TARGET


/datum/requirement/proc/holds(datum/act/op/A)
	stack_trace("legacy requirement [type] has no form in the new engine: write its req_* of code/engine/parts/cond.dm")
	return FALSE

/// The reason view of a compatibility requirement, null when allowed.
/datum/requirement/proc/check(datum/act/op/A)
	return holds(A) ? null : refusal(A)

/datum/requirement/proc/refusal(datum/act/op/A)
	return reason

/datum/requirement/proc/read_keys(datum/act/op/A)
	return null

// A downstream adapter supplies construction of compatibility requirements. Native
// parts are built directly and never need this composer.
GLOBAL_DATUM(requirement_composer, /datum/requirement_composer)

/datum/requirement_composer

/datum/requirement_composer/proc/all(list/parts)
	stack_trace("No compatibility requirement composer is installed")
	return null

/datum/requirement_composer/proc/any(list/parts)
	stack_trace("No compatibility requirement composer is installed")
	return null

/datum/requirement/proc/supports_native()
	return FALSE

/// Non-living actors have no living action-state gate. Living providers supply it.
/datum/proc/operation_actor_capable(ignoring)
	return TRUE

/// Authority is provided by the client role implementation.
/client/proc/operation_rights(required)
	return FALSE

/proc/requirement_composer()
	RETURN_TYPE(/datum/requirement_composer)
	if(!GLOB.requirement_composer)
		GLOB.requirement_composer = new /datum/requirement_composer
	return GLOB.requirement_composer
