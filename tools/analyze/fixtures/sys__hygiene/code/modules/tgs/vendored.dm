/datum/tgs
	var/cached_vendor
	var/cached_other

/datum/tgs/proc/f()
	cached_vendor = 1
	qdel(src) // ALLOW(lifecycle): baseline when ci was wired
	if(world.time >= vendored_deadline)
		go()

/datum/tgs/process()
	if(world.time >= vendored_deadline2)
		go()
