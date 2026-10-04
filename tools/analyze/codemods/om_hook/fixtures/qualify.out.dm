/mob/proc/observe()
	return

/mob/proc/setup(datum/thing)
	global.observe(thing, /datum/notice/moved, src, then(PROC_REF(follow)))
	unobserve(thing, /datum/notice/moved, src)

/mob/proc/follow(datum/act/notice/A)
	var/datum/notice/moved/event = A
	return event.old_loc
