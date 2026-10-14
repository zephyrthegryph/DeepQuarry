EXPIRY_DECLARE(om_declared)

/datum/om/proc/internals()
	if(world.time > foo_until)
		return
	x = world.time
	EXPIRY_SET(src, undeclared_om, 5)
	if(world.time - last > 5)
		return
