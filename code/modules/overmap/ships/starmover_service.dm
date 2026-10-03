//
// Handles the moving star effects behind overmap shuttles during travel (was SSstarmover). The system works
// through the queued z-levels every tick, parked while nothing is queued. The API is in starmover_api.dm.
//
SYSTEM_DEF(starmover)
	name = "Shuttle Star Movement"
	periodic_runlevels = RUNLEVELS_DEFAULT
	VAR_PRIVATE/list/zqueue = list()
	VAR_PRIVATE/list/current_movement = null
	//list used to track which zlevels are being 'moved' by the proc below
	VAR_PRIVATE/list/moving_levels = list()
	VAR_PRIVATE/list/currentrun = null
	VAR_PRIVATE/current_direction = 0
	/// TRUE while a pass that ran out of budget waits to resume.
	VAR_PRIVATE/resuming = FALSE

/// Works through the queued z-levels every tick, parked while nothing is queued (toggle_move_stars() wakes it).
/datum/system/starmover/reactions()
	. = ..()
	. += every(1, PROC_REF(move_stars), when = PROC_REF(work_ready), lane = LANE_SIMULATION)

#define CR_ZLEVEL 1
#define CR_DIRECTION 2
#define CR_TURFS 3

/datum/system/starmover/proc/move_stars(dt)
	var/resumed = resuming
	resuming = FALSE
	// Get next in queue or dropout
	if(!resumed && !current_movement)
		if(!length(zqueue))
			return STEP_PARK
		current_movement = zqueue[1]
		zqueue[1] = null
		zqueue -= null
		// Setup data
		var/zlevel = current_movement[CR_ZLEVEL]
		var/new_dir = current_movement[CR_DIRECTION]
		var/list/turf_list = current_movement[CR_TURFS]
		if(!length(turf_list) || moving_levels["[zlevel]"] == new_dir)
			clear_movement_run()
			return has_work() ? STEP_DONE : STEP_PARK
		moving_levels["[zlevel]"] = new_dir
		currentrun = turf_list

	// Has a movement queued, process all turfs
	while(length(currentrun))
		var/turf/space/T = currentrun[length(currentrun)]
		currentrun.len--
		if(istype(T))
			T.toggle_transit(current_movement[CR_DIRECTION])
		if(KERNEL_OVER_BUDGET)
			resuming = TRUE
			return STEP_YIELD
	clear_movement_run()
	return has_work() ? STEP_DONE : STEP_PARK

/datum/system/starmover/proc/clear_movement_run()
	current_movement.Cut()
	current_movement = null
	currentrun = null

/datum/system/starmover/stat_entry(msg)
	return "[msg]Q:[length(zqueue)] C:[currentrun ? length(currentrun) : "-"]"

/datum/system/starmover/proc/has_work()
	return length(zqueue) || current_movement

#undef CR_ZLEVEL
#undef CR_DIRECTION
#undef CR_TURFS
