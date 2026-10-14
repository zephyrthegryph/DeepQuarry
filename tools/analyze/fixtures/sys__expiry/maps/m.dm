/obj/thing/proc/map_proc()
	if(world.time < last_use + delay)
		return
	if(world.time > foo_until)
		return
	if(world.time > 30 MINUTES)
		return
	if(world.time < last_use + delay) // ALLOW(cooldown): fixture keep
		return
	if(world.time - last > 5)
		return
	x = world.time
	EXPIRY_SET(src, declared_a, 5)
	EXPIRY_SET(src, undeclared_map, 5)
