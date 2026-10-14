/datum/reagent/proc/dose()
	if(world.time > data)
		return
	if(world.time > data["x"])
		return
	if(world.time > metadata)
		return
	if(world.time > other.data)
		return
	if(world.time > last_dose)
		return
