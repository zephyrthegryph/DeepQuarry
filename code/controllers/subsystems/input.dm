SUBSYSTEM_DEF(input)
	name = "Input"
	wait = 1 // SS_TICKER means this runs every tick
	init_stage = INITSTAGE_EARLY
	flags = SS_TICKER | SS_NO_INIT
	priority = FIRE_PRIORITY_INPUT
	runlevels = RUNLEVELS_DEFAULT | RUNLEVEL_LOBBY

/datum/controller/subsystem/input/fire()
	// Clicks the kernel held back from the last tick run before movement.
	kernel_latency().drain_clicks()
	var/list/clients = GLOB.clients // Let's sing the list cache song
	for(var/i in 1 to length(clients))
		var/client/C = clients[i]
		C?.keyLoop()
