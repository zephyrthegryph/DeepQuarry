/*
 * This is the home of multi-tile movement checks, and thus here be dragons. You are warned.
 */

/proc/check_multi_tile_move_density_dir(atom/movable/source, stepdir)
	if(!source.locs || !source.locs.len)
		return TRUE

	if(source.bound_height > 32 || source.bound_width > 32)
		var/safe_move = TRUE
		var/list/checked_turfs = list()
		for(var/turf/T in source.locs)
			var/turf/Tcheck = get_step(T, stepdir)
			if(!Tcheck) //Map edge
				continue
			if(Tcheck in checked_turfs)
				continue
			if(Tcheck in source.locs)
				checked_turfs |= Tcheck
				continue
			if(!(Tcheck in source.locs))
				if(!T.Exit(source, Tcheck))
					safe_move = FALSE
				if(!Tcheck.Enter(source, T))
					safe_move = FALSE
			checked_turfs |= Tcheck
			if(!safe_move)
				break
		return safe_move
	return TRUE
