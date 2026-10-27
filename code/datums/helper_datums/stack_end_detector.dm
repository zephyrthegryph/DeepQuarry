/**
	Stack End Detector.
	Can detect if a given code stack has exited, used by the mc for stack overflow detection.

 **/
/datum/stack_end_detector
	/// A weak view of the canary: it pins nothing and never names a datum that reuses the canary's address, so canary_watch() reads null once
	/// BYOND has collected the canary (the stack that held it has ended); the collection is logged.
	var/canary_watch
	var/datum/handle_sentinel/stack_canary/_canary

CAPABILITIES(/datum/stack_end_detector)
	ref_one(nameof(canary_watch), /datum/handle_sentinel/stack_canary, weak = TRUE)
	owns_one(nameof(_canary), /datum/handle_sentinel/stack_canary)

/datum/stack_end_detector/New()
	rel_set(src, nameof(_canary), new /datum/handle_sentinel/stack_canary())
	rel_set(src, nameof(canary_watch), _canary)

/** Prime the stack overflow detector.
	Store the return value of this proc call in a proc level var.
	Can only be called once.
**/
/datum/stack_end_detector/proc/prime_canary()
	if (!_canary)
		CRASH("Prime_canary called twice")
	. = _canary
	rel_take(src, nameof(_canary))

/// Returns true if the stack is still going. Calling before the canary has been primed also returns true
/datum/stack_end_detector/proc/check()
	return istype(canary_watch(), /datum/handle_sentinel/stack_canary)

/// Stack canary. Will go away if the stack it was primed by is ended by byond for return or stack overflow reasons.
/datum/handle_sentinel/stack_canary

/// empty proc to avoid warnings about unused variables. Call this proc on your canary in the stack it's watching.
/datum/handle_sentinel/stack_canary/proc/use_variable()

