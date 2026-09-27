/*
/atom/movable/proc/recursive_move(atom/movable/am, old_loc, new_loc)
	SEND_SIGNAL(src, COMSIG_MOVABLE_ATTEMPTED_MOVE, old_loc, new_loc)
*/
/proc/move_to_destination(atom/movable/source, atom/movable/am, old_loc, new_loc)
	var/turf/T = get_turf(new_loc)
	if(T && T != source.loc)
		source.forceMove(T)

/proc/recursive_dir_set(atom/source, atom/a, old_dir, new_dir)
	source.set_dir(new_dir)

/datum/proc/qdel_self()
	SIGNAL_HANDLER
	qdel(src)

