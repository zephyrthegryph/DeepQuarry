/datum/controller/master/proc/mc()
	if(world.time > foo_until)
		return
	x = world.time
	if(world.time - last > 5)
		return
