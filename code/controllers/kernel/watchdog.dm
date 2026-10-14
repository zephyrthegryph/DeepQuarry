/**
 * The kernel watchdog
 *
 * Pokes the kernel loop to make sure it's still alive: kernel.last_tick is the heartbeat it watches. It is its own sleeping
 * loop outside the tick loop, because only something outside the loop can notice that the loop stopped. The kernel
 * (`Kernel.watchdog`) starts it from its first tick and starts a new one when it has stopped.
 **/

/datum/controller/kernel
	/// The watchdog loop that watches this kernel's heartbeat (start_watchdog()).
	var/datum/kernel_watchdog/watchdog

/// Starts a watchdog; one that is already running is stopped first (there can be only one).
/datum/controller/kernel/proc/start_watchdog()
	if(watchdog)
		watchdog.running = FALSE
	watchdog = new /datum/kernel_watchdog

/datum/kernel_watchdog // This thing pretty much just keeps poking the kernel
	var/name = "Watchdog"

	// The length of time to check on the kernel (in deciseconds).
	// Set to 0 to disable.
	var/processing_interval = 20
	// The alert level. For every failed poke, we drop a DEFCON level. Once we hit DEFCON 1, restart the kernel loop.
	var/defcon = 5
	//the world.time of the last check, so the kernel loop can restart US if we hang.
	// (Real friends look out for *each other*)
	var/lasttick = 0

	// The kernel's last_tick as of the previous look, to make sure it is still on track.
	var/kernel_tick_seen = 0
	var/running = TRUE

/datum/kernel_watchdog/New()
	..()
	// Ensure usr is null, to prevent any potential weirdness resulting from the watchdog having a usr if it's manually restarted.
	usr = null // ALLOW(sys_usr_outside_verb): the watchdog clears usr: it runs no verb and no player's input
	begin()

/// Watches the kernel until the loop ends, then (if the kernel stopped answering) tries to bring it back up.
/datum/kernel_watchdog/proc/begin()
	set waitfor = FALSE // ALLOW(scheduler): kernel code (the watchdog loop)
	Loop()
	if (defcon == 0) //The kernel is not responding and the watchdog just exited its loop
		defcon = 3 //Reset defcon level as its used inside the emergency loop
		while (defcon > 0)
			var/recovery_result = emergency_loop()
			if (recovery_result == 1) //Exit emergency loop and stop if it was able to recover the kernel
				break
			else if (defcon == 1) //Exit if we weren't able to recover the kernel in the last stage
				log_game("Watchdog: Failed to recover the kernel while in emergency state. The watchdog is exiting.")
				message_admins(span_boldannounce("The watchdog failed critically while trying to restart the kernel loop. Please restart it (Debug > Restart Controller > Kernel) or reboot the server. The watchdog is exiting now."))
			else if (recovery_result == -1) //Failed to restart the kernel
				defcon--
			// ALLOW(scheduler): the watchdog is outside the kernel: its sleeps and detached procs are its own loop
			sleep(initial(processing_interval)) //Wait a bit until the next try
	running = FALSE // nothing holds it any more: the kernel starts a new one when it next looks

/datum/kernel_watchdog/proc/Loop()
	while(running)
		// ALLOW(sys_world_time_write): the watchdog's own heartbeat, read by the kernel loop, not an entity expiry
		lasttick = world.time
		var/datum/controller/kernel/K = kernel()
		// Only poke it if overrides are not in effect.
		if(processing_interval > 0)
			if(Kernel.processing && K.ticks)
				if (defcon > 1 && (!K.stack_end_detector || !K.stack_end_detector.check()))

					to_chat(GLOB.admins, span_boldannounce("ERROR: The kernel loop's code stack has exited unexpectedly, Restarting..."))
					defcon = 0
					var/rtn = Recreate_kernel()
					if(rtn > 0)
						kernel_tick_seen = 0
						to_chat(GLOB.admins, span_adminnotice("Kernel restarted successfully"))
					else if(rtn < 0)
						log_game("Watchdog: Could not restart the kernel, runtime encountered. Entering defcon 0")
						to_chat(GLOB.admins, span_boldannounce("ERROR: DEFCON [defcon_pretty()]. Could not restart the kernel, runtime encountered. I will silently keep retrying."))
				// Check if the kernel ticked since the last look (kernel.last_tick is its heartbeat).
				if(K.last_tick == kernel_tick_seen)
					switch(defcon)
						if(4,5)
							--defcon

						if(3)
							message_admins(span_adminnotice("Notice: DEFCON [defcon_pretty()]. The kernel has not ticked in the last [(5-defcon) * processing_interval] ticks."))
							--defcon

						if(2)
							to_chat(GLOB.admins, span_boldannounce("Warning: DEFCON [defcon_pretty()]. The kernel has not ticked in the last [(5-defcon) * processing_interval] ticks. Automatic restart in [processing_interval] ticks."))
							--defcon

						if(1)
							to_chat(GLOB.admins, span_boldannounce("Warning: DEFCON [defcon_pretty()]. The kernel has still not ticked within the last [(5-defcon) * processing_interval] ticks. Killing and restarting..."))
							--defcon
							var/rtn = Recreate_kernel()
							if(rtn > 0)
								defcon = 4
								kernel_tick_seen = 0
								to_chat(GLOB.admins, span_adminnotice("Kernel restarted successfully"))
							else if(rtn < 0)
								log_game("Watchdog: Could not restart the kernel, runtime encountered. Entering defcon 0")
								to_chat(GLOB.admins, span_boldannounce("ERROR: DEFCON [defcon_pretty()]. Could not restart the kernel, runtime encountered. I will silently keep retrying."))
							//if the return number was 0, it just means the kernel was restarted too recently, and it just needs some time before we try again
							//no need to handle that specially when defcon 0 can handle it

						if(0) //DEFCON 0! (the kernel failed to restart)
							var/rtn = Recreate_kernel()
							if(rtn > 0)
								defcon = 4
								kernel_tick_seen = 0
								to_chat(GLOB.admins, span_adminnotice("Kernel restarted successfully"))
				else
					defcon = min(defcon + 1,5)
					kernel_tick_seen = K.last_tick
			if (defcon <= 1)
				sleep(processing_interval*2) // ALLOW(scheduler): the watchdog is outside the kernel: its sleeps and detached procs are its own loop
			else
				sleep(processing_interval) // ALLOW(scheduler): the watchdog is outside the kernel: its sleeps and detached procs are its own loop
		else
			defcon = 5
			sleep(initial(processing_interval)) // ALLOW(scheduler): the watchdog is outside the kernel: its sleeps and detached procs are its own loop

//Emergency loop used when the kernel could not be restarted while Defcon == 0
//Loop is driven externally so runtimes only cancel the current recovery attempt
/datum/kernel_watchdog/proc/emergency_loop()
	//The code in this proc should be kept as simple as possible, anything complicated like to_chat might rely on the kernel and runtime
	//The goal should always be to get the kernel loop running again before anything else
	. = -1
	switch (defcon) //The lower defcon goes the harder we try to fix the kernel
		if (2 to 3) //Try to normally restart the kernel loop two times
			. = Recreate_kernel()
		if (1) //Drop every work item's in-flight run first, in case one of them caused the trouble
			kernel().reset_work()
			. = Recreate_kernel()

	if (. == 1) //We were able to restart the loop
		kernel_tick_seen = 0
		SSticker.restore_runlevel() //so the kernel's run level matches the round state
		to_chat(GLOB.admins, span_adminnotice("The watchdog recovered the kernel while in emergency state [defcon_pretty()]"))
	else
		log_game("Watchdog: The watchdog in emergency state and was unable to restart the kernel while in defcon state [defcon_pretty()].")
		message_admins(span_boldannounce("The watchdog in emergency state and the kernel down, trying to restart it while in defcon level [defcon_pretty()] failed."))

/datum/kernel_watchdog/proc/defcon_pretty()
	return defcon

/datum/kernel_watchdog/proc/stat_entry(msg)
	msg = "Defcon: [defcon_pretty()] (Interval: [processing_interval] | Kernel tick: [kernel_tick_seen])"
	return msg
