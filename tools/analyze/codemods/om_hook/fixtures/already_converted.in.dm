/datum/holder/proc/setup(datum/thing)
	observe(thing, /datum/notice/moved, src, then(PROC_REF(moved_to)))
	unobserve(thing, /datum/notice/moved, src)

/datum/holder/proc/moved_to(datum/act/notice/A)
	var/datum/source = A.target
	return source
