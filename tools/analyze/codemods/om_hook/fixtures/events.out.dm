/datum/holder/proc/watch(datum/thing)
	observe(thing, /datum/notice/moved, src, then(PROC_REF(changed)))
	observe(thing, /datum/notice/qdeleting, src, then(PROC_REF(changed)))

/datum/holder/proc/stop(datum/thing)
	unobserve(thing, /datum/notice/moved, src)
	unobserve(thing, /datum/notice/qdeleting, src)

/datum/holder/proc/changed(datum/act/notice/A)
	var/datum/source = A.target
	return source
