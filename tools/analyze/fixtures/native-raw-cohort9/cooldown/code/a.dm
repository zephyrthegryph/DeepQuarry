/datum/probe/proc/run()
	if(world.time > next_use)
		return
	if(world.time > other) // ALLOW(cooldown): deliberate compatibility fixture for recorded annotation
		return
	var/text = "world.time > fake"
