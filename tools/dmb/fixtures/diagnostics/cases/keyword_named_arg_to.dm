/proc/target(a = 1, b = 2)
	return a

/proc/run_it()
	return target(1, to = 2)

/world/New()
	run_it()
