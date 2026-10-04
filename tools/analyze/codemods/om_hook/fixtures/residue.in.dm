/datum/holder
	var/list/paths

/datum/holder/proc/setup(datum/thing, datum/other, event_type)
	// too few arguments
	om_hook(thing, /datum/om/event/moved, src)
	// the event is a variable
	om_hook(thing, event_type, src, PROC_REF(fine))
	// a guard has no notice twin
	om_hook(thing, /datum/om/event/before/dice_roll, src, PROC_REF(fine))
	// an event list in a value
	var/ok = list(om_hook(thing, list(/datum/om/event/moved, /datum/om/event/qdeleting), src, PROC_REF(fine)))
	// the listener is not src
	om_hook(thing, /datum/om/event/moved, other, PROC_REF(fine))
	// the handler is not a PROC_REF
	om_hook(thing, /datum/om/event/moved, src, event_type)
	// the handler uses the event whole
	om_hook(thing, /datum/om/event/moved, src, PROC_REF(takes_event))
	// something else calls the handler
	om_hook(thing, /datum/om/event/moved, src, PROC_REF(called_directly))
	// the unhook of a hook that does not convert, and of one nobody hooks
	om_unhook(thing, /datum/om/event/before/dice_roll, src)
	om_unhook(thing, /datum/om/event/qdeleting, src)
	om_unhook_all(src)
	return ok

/datum/holder/proc/fine(datum/source, datum/om/event/moved/event)
	return TRUE

/datum/holder/proc/takes_event(datum/source, datum/om/event/moved/event)
	return event

/datum/holder/proc/called_directly(datum/source, datum/om/event/moved/event)
	return TRUE

/datum/holder/proc/other_caller(datum/thing, datum/om/event/moved/event)
	return called_directly(thing, event)
