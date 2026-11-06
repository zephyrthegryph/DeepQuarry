/datum/test
	var/cached_t

/datum/test/proc/f()
	cached_t = 1
	qdel(src) // ALLOW(lifecycle): see audit

/datum/test/process()
	if(world.time >= test_deadline)
		go()
