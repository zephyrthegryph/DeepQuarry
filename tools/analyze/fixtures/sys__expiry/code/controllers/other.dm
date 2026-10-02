/datum/controller/other/proc/o()
	if(world.time < last_use + delay)
		return
	if(world.time > foo_until)
		return
	if(world.time > 30 MINUTES)
		return
	if(world.time > foo_until) // ALLOW(cooldown): fixture keep
		return
	x = world.time
	if(world.time - last > 5)
		return
