// Exempt path: benchmarks build the forbidden things on purpose.
/datum/bench/proc/everything()
	spawn(0)
	sleep(1)
	del(src)
