/datum/holder/proc/watch(datum/thing)
	om_hook(thing, list(/datum/om/event/moved, /datum/om/event/qdeleting), src, PROC_REF(changed))

/datum/holder/proc/stop(datum/thing)
	om_unhook(thing, list(/datum/om/event/moved, /datum/om/event/qdeleting), src)

/datum/holder/proc/changed(datum/source, datum/om/event/event)
	return source
