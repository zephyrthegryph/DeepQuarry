/datum/holder/proc/start(datum/thing)
	observe(thing, /datum/notice/moved, src, then(PROC_REF(follow)))

/datum/holder/proc/follow(datum/act/notice/A)
	var/datum/notice/moved/event = A
	return event.old_loc

/datum/holder/proc/stop(datum/thing)
	unobserve(thing, /datum/notice/moved, src)
