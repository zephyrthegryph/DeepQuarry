/**
	Stack End Detector.
	Can detect if a given code stack has exited, used by the mc for stack overflow detection.

 **/
/datum/stack_end_detector
	/// REF() of the canary. Deliberately not an OM handle: a handle keeps its
	/// target alive, and this has to notice BYOND collecting the canary.
	var/_canary_ref
	/// The canary's serial, so a reused ref id never reads as the canary.
	var/_canary_serial
	var/datum/stack_canary/_canary

CAPABILITIES(/datum/stack_end_detector)
	owns_one(nameof(_canary), /datum/stack_canary)

/datum/stack_end_detector/New()
	var/static/next_serial = 0
	rel_set(src, nameof(_canary), new /datum/stack_canary())
	_canary.serial = ++next_serial
	_canary_serial = _canary.serial
	_canary_ref = REF(_canary)

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
	var/datum/stack_canary/canary = locate(_canary_ref)
	return istype(canary) && canary.serial == _canary_serial

/// Stack canary. Will go away if the stack it was primed by is ended by byond for return or stack overflow reasons.
/datum/stack_canary
	var/serial = 0

/// empty proc to avoid warnings about unused variables. Call this proc on your canary in the stack it's watching.
/datum/stack_canary/proc/use_variable()

