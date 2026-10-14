/obj/proc/not_reagents()
	if(world.time > data)
		return
	if(world.time > last_dose)
		return
	if(world.time < foo_until)
		return
