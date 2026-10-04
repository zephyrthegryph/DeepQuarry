/datum/holder/proc/start(datum/thing)
	om_hook(thing, /datum/om/event/moved, src, PROC_REF(follow))

/datum/holder/proc/follow(datum/source, datum/om/event/moved/event)
	return event.old_loc

/datum/holder/proc/stop(datum/thing)
	om_unhook(thing, /datum/om/event/moved, src)
