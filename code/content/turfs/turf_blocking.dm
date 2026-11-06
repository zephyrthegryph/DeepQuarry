/proc/DirBlocked(turf/loc,dir)
	for(var/obj/structure/window/D in turf_contents_of_type(loc, /obj/structure/window))
		if(!D.density)			continue
		if(D.dir == SOUTHWEST)	return 1
		if(D.dir == dir)		return 1

	for(var/obj/machinery/door/D in turf_contents_of_type(loc, /obj/machinery/door))
		if(!D.density)			continue
		if(istype(D, /obj/machinery/door/window))
			if((dir & SOUTH) && (D.dir & (EAST|WEST)))		return 1
			if((dir & EAST ) && (D.dir & (NORTH|SOUTH)))	return 1
		else return 1	// it's a real, air blocking door
	return 0

/proc/TurfBlockedNonWindow(turf/loc)
	for(var/obj/O in turf_contents_of_type(loc, /obj))
		if(O.density && !istype(O, /obj/structure/window))
			return 1
	return 0

/**
 * - is_valid_z_level
 *
 * Checks if source_loc and checking_loc is both on the station, or on the same z level.
 * This is because the station's several levels aren't considered the same z, so multi-z stations need this special case.
 *
 * Args:
 * source_loc - turf of the source we're comparing.
 * checking_loc - turf we are comparing to source_loc.
 *
 * returns TRUE if connection is valid, FALSE otherwise.
 */
/proc/is_valid_z_level(turf/source_loc, turf/checking_loc)
	return is_on_same_plane_or_station(source_loc.z, checking_loc.z)

/proc/LinkBlocked(turf/A, turf/B)
	if(A == null || B == null) return 1
	var/adir = get_dir(A,B)
	var/rdir = get_dir(B,A)
	if((adir & (NORTH|SOUTH)) && (adir & (EAST|WEST)))	//	diagonal
		var/iStep = get_step(A,adir&(NORTH|SOUTH))
		if(!LinkBlocked(A,iStep) && !LinkBlocked(iStep,B)) return 0

		var/pStep = get_step(A,adir&(EAST|WEST))
		if(!LinkBlocked(A,pStep) && !LinkBlocked(pStep,B)) return 0
		return 1

	if(DirBlocked(A,adir)) return 1
	if(DirBlocked(B,rdir)) return 1
	return 0
