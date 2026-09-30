/**
 * Failsafe
 *
 * Pretty much pokes the kernel loop to make sure it's still alive: kernel.last_tick is the heartbeat it watches.
 **/

// See initialization order in /code/game/world.dm
GLOBAL_REAL(Failsafe, /datum/controller/failsafe)

/datum/controller/failsafe // This thing pretty much just keeps poking the kernel
	name = "Failsafe"

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

/datum/controller/failsafe/New()
	// Ensure usr is null, to prevent any potential weirdness resulting from the failsafe having a usr if it's manually restarted.
	usr = null

	// Highlander-style: there can only be one! Kill off the old and replace it with the new.
	if(Failsafe != src)
		if(istype(Failsafe))
			qdel(Failsafe)
	Failsafe = src
	Initialize()

/datum/controller/failsafe/Initialize()
	set waitfor = FALSE // ALLOW(scheduler): kernel code (failsafe loop)
	Failsafe.Loop()
	if (defcon == 0) //The kernel is not responding and Failsafe just exited its loop
		defcon = 3 //Reset defcon level as its used inside the emergency loop
		while (defcon > 0)
			var/recovery_result = emergency_loop()
			if (recovery_result == 1) //Exit emergency loop and delete self if it was able to recover the kernel
				break
			else if (defcon == 1) //Exit Failsafe if we weren't able to recover the kernel in the last stage
				log_game("FailSafe: Failed to recover the kernel while in emergency state. Failsafe exiting.")
				message_admins(span_boldannounce("Failsafe failed critically while trying to restart the kernel loop. Please restart it (Debug > Restart Controller > Kernel) or reboot the server. Failsafe exiting now."))
			else if (recovery_result == -1) //Failed to restart the kernel
				defcon--
			// ALLOW(scheduler): failsafe
			sleep(initial(processing_interval)) //Wait a bit until the next try

	if(!QDELETED(src))
		qdel(src) //when Loop() returns, we delete ourselves and let the mc recreate us

// ALLOW(lifecycle): failsafe singleton; stops its loop and asks for a hard delete.
/datum/controller/failsafe/Destroy()
	running = FALSE
	..()
	return QDEL_HINT_HARDDEL_NOW

/datum/controller/failsafe/proc/Loop()
	while(running)
		lasttick = world.time
		var/datum/controller/kernel/K = kernel()
		// Only poke it if overrides are not in effect.
		if(processing_interval > 0)
			if(Master.processing && K.ticks)
				if (defcon > 1 && (!K.stack_end_detector || !K.stack_end_detector.check()))

					to_chat(GLOB.admins, span_boldannounce("ERROR: The kernel loop's code stack has exited unexpectedly, Restarting..."))
					defcon = 0
					var/rtn = Recreate_kernel()
					if(rtn > 0)
						kernel_tick_seen = 0
						to_chat(GLOB.admins, span_adminnotice("Kernel restarted successfully"))
					else if(rtn < 0)
						log_game("FailSafe: Could not restart the kernel, runtime encountered. Entering defcon 0")
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
								log_game("FailSafe: Could not restart the kernel, runtime encountered. Entering defcon 0")
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
				sleep(processing_interval*2) // ALLOW(scheduler): failsafe
			else
				sleep(processing_interval) // ALLOW(scheduler): failsafe
		else
			defcon = 5
			sleep(initial(processing_interval)) // ALLOW(scheduler): failsafe

//Emergency loop used when the kernel could not be restarted while Defcon == 0
//Loop is driven externally so runtimes only cancel the current recovery attempt
/datum/controller/failsafe/proc/emergency_loop()
	//The code in this proc should be kept as simple as possible, anything complicated like to_chat might rely on the kernel and runtime
	//The goal should always be to get the kernel loop running again before anything else
	. = -1
	switch (defcon) //The lower defcon goes the harder we try to fix the kernel
		if (2 to 3) //Try to normally restart the kernel loop two times
			. = Recreate_kernel()
		if (1) //Drop every hosted run first, in case one of them caused the trouble
			reset_all_hosted()
			. = Recreate_kernel()

	if (. == 1) //We were able to restart the loop
		kernel_tick_seen = 0
		SSticker.restore_runlevel() //so the Master's run level matches the round state
		to_chat(GLOB.admins, span_adminnotice("Failsafe recovered the kernel while in emergency state [defcon_pretty()]"))
	else
		log_game("FailSafe: Failsafe in emergency state and was unable to restart the kernel while in defcon state [defcon_pretty()].")
		message_admins(span_boldannounce("Failsafe in emergency state and the kernel down, trying to restart it while in defcon level [defcon_pretty()] failed."))

/// Drops every host service's in-flight run (a paused or wedged one), so the next loop starts them clean.
/proc/reset_all_hosted()
	for(var/datum/controller/subsystem/SS as anything in Master.subsystems)
		if(SS.flags & SS_KERNEL_HOSTED)
			SS.state = SS_IDLE
			SS.paused_ticks = 0
			SS.paused_tick_usage = 0
			SS.next_fire = 0

/datum/controller/failsafe/proc/defcon_pretty()
	return defcon

/datum/controller/failsafe/stat_entry(msg)
	msg = "Defcon: [defcon_pretty()] (Interval: [Failsafe.processing_interval] | Kernel tick: [Failsafe.kernel_tick_seen])"
	return msg
