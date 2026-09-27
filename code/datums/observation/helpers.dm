/*
/atom/movable/proc/recursive_move(atom/movable/am, old_loc, new_loc)
	SEND_SIGNAL(src, COMSIG_MOVABLE_ATTEMPTED_MOVE, old_loc, new_loc)
*/
/atom/movable/proc/move_to_destination(atom/movable/am, old_loc, new_loc)
	var/turf/T = get_turf(new_loc)
	if(T && T != loc)
		forceMove(T)

/atom/proc/recursive_dir_set(atom/a, old_dir, new_dir)
	set_dir(new_dir)

/datum/proc/qdel_self()
	SIGNAL_HANDLER
	qdel(src)

