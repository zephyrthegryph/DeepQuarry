/datum/unit_test/proc/t()
	if(world.time > foo_until)
		return
	if(world.time < last_use + delay)
		return
	x = world.time
	COOLDOWN_START_OWN(src, undeclared_ut, 5)
	COOLDOWN_DECLARE(ut_declared)
