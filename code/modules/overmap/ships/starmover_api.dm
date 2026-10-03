// The star mover system's API (code/modules/overmap/ships/starmover_service.dm declares the system).
//
//   SSstarmover.toggle_move_stars(zlevel, direction)   start moving the stars of a z-level in `direction`; a null direction stops them

/// Used to 'move' stars in spess. null direction stops movement
/datum/system/starmover/proc/toggle_move_stars(zlevel, direction)
	if(!zlevel)
		return
	var/list/spaceturfs = block(locate(1, 1, zlevel), locate(world.maxx, world.maxy, zlevel))
	zqueue += list(list(zlevel,direction,spaceturfs))
	wake_work_item(PROC_REF(move_stars))
