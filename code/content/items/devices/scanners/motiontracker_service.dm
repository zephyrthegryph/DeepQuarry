// The motion tracker system (was SSmotiontracker). ping() raises /datum/definition_event/movable_motiontracker on the
// system for every hooked listener; listeners queue echo turfs with queue_echo(), and draw_echoes draws the
// queued echoes every second.
SYSTEM_DEF(motiontracker)
	name = "Motion Tracker"
	periodic_runlevels = RUNLEVEL_GAME | RUNLEVEL_POSTGAME
	var/hide_all = FALSE // Hide and seek mode
	var/min_range = 2
	var/max_range = 8
	var/all_echos_round = 0
	var/all_pings_round = 0
	var/list/queued_echo_turfs = list()
	var/list/currentrun = list()
	var/list/expended_echos = list()
	/// TRUE while an echo pass that ran out of budget waits to resume.
	VAR_PRIVATE/echo_resuming = FALSE

/datum/system/motiontracker/stat_entry(msg)
	var/count = 0
	count = observer_count(src, /datum/notice/movable_motiontracker)
	if(hide_all)
		msg = "HIDE AND SEEK"
	else
		msg += "L: [count] | Q: [length(queued_echo_turfs)] | A: [all_echos_round]/[all_pings_round]"
	return msg

/datum/system/motiontracker/reactions()
	. = ..()
	. += every(1 SECOND, PROC_REF(draw_echoes), when = PROC_REF(work_ready), lane = LANE_SIMULATION)

/datum/system/motiontracker/proc/draw_echoes(dt)
	if(!echo_resuming)
		src.currentrun = queued_echo_turfs.Copy()
		expended_echos.Cut()
	echo_resuming = FALSE
	while(length(currentrun))
		var/key = currentrun[1] // Because using an index into an associative array gets the key at that index... I hate you byond.
		var/list/data = currentrun[key]
		var/AF= data[1]
		var/RF= data[2]
		var/count 			= data[3]
		var/list/clients 	= data[4]
		// A queue entry lives one service step: turfs held directly, skipped once released.
		var/turf/At = AF
		var/turf/Rt = RF
		if(isturf(Rt) && isturf(At) && !QDELETED(Rt) && !QDELETED(At) && count)
			while(count-- > 0)
				// Place at root turf offset from signal responder's turf using px offsets. So it will show up over visblocking.
				var/image/client_only/motion_echo/E = new /image/client_only/motion_echo('icons/effects/effects.dmi', Rt, "motion_echo", OBFUSCATION_LAYER, SOUTH)
				E.place_from_root(At)
				for(var/client/C in clients) // clients that left read null
					E.append_client(C)
		currentrun.Remove(key)
		expended_echos[key] = data
		if(KERNEL_OVER_BUDGET)
			echo_resuming = TRUE
			return STEP_YIELD
	// Removed used keys, incase the current queue grew while we were processing this one
	queued_echo_turfs -= expended_echos
	return STEP_DONE
