//
// Handles the moving star effects behind overmap shuttles during travel (fold wave F4; was
// SSstarmover). /datum/om/behaviour/world/starmover (code/datums/om/world_lanes.dm) works through
// the queued z-levels every tick, parked while nothing is queued.
//
GLOBAL_DATUM_INIT(starmover_service, /datum/world_service/starmover, new)

/datum/world_service/starmover
	name = "Shuttle Star Movement"
	lane = /datum/om/behaviour/world/starmover
	on_demand = TRUE
	var/list/zqueue = list()
	var/list/current_movement = null
	//list used to track which zlevels are being 'moved' by the proc below
	var/list/moving_levels = list()
	var/list/currentrun = null
	var/current_direction = 0

#define CR_ZLEVEL 1
#define CR_DIRECTION 2
#define CR_TURFS 3

/datum/world_service/starmover/service_step(resumed)
	// Get next in queue or dropout
	if(!resumed && !current_movement)
		if(!length(zqueue))
			return TRUE
		current_movement = zqueue[1]
		zqueue[1] = null
		zqueue -= null
		// Setup data
		var/zlevel = current_movement[CR_ZLEVEL]
		var/new_dir = current_movement[CR_DIRECTION]
		var/list/turf_list = current_movement[CR_TURFS]
		if(!length(turf_list) || moving_levels["[zlevel]"] == new_dir)
			clear_movement_run()
			return TRUE
		moving_levels["[zlevel]"] = new_dir
		currentrun = turf_list

	// Has a movement queued, process all turfs
	while(length(currentrun))
		var/turf/space/T = currentrun[length(currentrun)]
		currentrun.len--
		if(istype(T))
			T.toggle_transit(current_movement[CR_DIRECTION])
		if(TICK_CHECK)
			return FALSE
	clear_movement_run()
	return TRUE

/datum/world_service/starmover/proc/clear_movement_run()
	current_movement.Cut()
	current_movement = null
	currentrun = null

/datum/world_service/starmover/stat_line()
	return "Q:[length(zqueue)] C:[currentrun ? length(currentrun) : "-"]"

/datum/world_service/starmover/has_work()
	return length(zqueue) || current_movement

/// Used to 'move' stars in spess. null direction stops movement
/datum/world_service/starmover/proc/toggle_move_stars(zlevel, direction)
	if(!zlevel)
		return
	var/list/spaceturfs = block(locate(1, 1, zlevel), locate(world.maxx, world.maxy, zlevel))
	zqueue += list(list(zlevel,direction,spaceturfs))
	demand()

#undef CR_ZLEVEL
#undef CR_DIRECTION
#undef CR_TURFS
