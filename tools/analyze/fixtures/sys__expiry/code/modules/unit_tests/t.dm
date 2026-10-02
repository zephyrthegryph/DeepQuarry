/datum/unit_test/proc/t()
	if(world.time > foo_until)
		return
	if(world.time < last_use + delay)
		return
	x = world.time
	EXPIRY_SET(src, undeclared_ut, 5)
	EXPIRY_DECLARE(ut_declared)
