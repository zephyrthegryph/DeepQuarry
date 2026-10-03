/mob/proc/observe()
	return

/mob/proc/setup(datum/thing)
	om_hook(thing, /datum/om/event/moved, src, PROC_REF(follow))
	om_unhook(thing, /datum/om/event/moved, src)

/mob/proc/follow(datum/source, datum/om/event/moved/event)
	return event.old_loc
