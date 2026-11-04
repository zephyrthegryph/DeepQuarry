//Will return the contents of an atom recursivly to a depth of 'searchDepth'
/atom/proc/GetAllContents(searchDepth = 5)
	var/list/toReturn = list()
	if(latent_contents_enabled())
		latent_materialize_all() // a search needs real things (C5)

	for(var/atom/part in contents)
		toReturn += part
		if((contents_count(part) || part?.latent_contents_enabled()) && searchDepth)
			toReturn += part.GetAllContents(searchDepth - 1)

	return toReturn

//Step-towards method of determining whether one atom can see another. Similar to viewers()
/proc/can_see(atom/source, atom/target, length=5) // I couldn't be arsed to do actual raycasting :I This is horribly inaccurate.
	var/turf/current = get_turf(source)
	var/turf/target_turf = get_turf(target)
	var/steps = 0

	if(!current || !target_turf)
		return 0

	while(current != target_turf)
		if(steps > length) return 0
		if(current.opacity) return 0
		for(var/atom/A in turf_contents_of_type(current, /atom))
			if(A.opacity) return 0
		current = get_step_towards(current, target_turf)
		steps++

	return 1

/proc/is_blocked_turf(turf/T)
	var/cant_pass = 0
	if(T.density) cant_pass = 1
	for(var/atom/A in turf_contents_of_type(T, /atom))
		if(A.density)//&&A.anchored
			cant_pass = 1
	return cant_pass

/* //If you uncomment and use this I will assimilate you. -C.L.
//Takes: Anything that could possibly have variables and a varname to check.
//Returns: 1 if found, 0 if not.
*/

/datum/coords //Simple datum for storing coordinates.
	var/x_pos = null
	var/y_pos = null
	var/z_pos = null

/proc/get(atom/current, type)
	while(current)
		if(istype(current, type))
			return current
		current = current.loc
	return null

/proc/get_turf_or_move(turf/location)
	return get_turf(location)

/proc/istool(O)
	if(O && is_type_in_list(O, GLOB.common_tools))
		return 1
	return 0

/proc/gotwallitem(loc, dir)
	for(var/obj/O in contents_of(loc))
		if(O.flags & WALL_ITEM)
			//Direction works sometimes
			if(O.dir == dir)
				return 1

			//Some stuff doesn't use dir properly, so we need to check pixel instead
			switch(dir)
				if(SOUTH)
					if(O.pixel_y > 10)
						return 1
				if(NORTH)
					if(O.pixel_y < -10)
						return 1
				if(WEST)
					if(O.pixel_x > 10)
						return 1
				if(EAST)
					if(O.pixel_x < -10)
						return 1

	//Some stuff is placed directly on the wallturf (signs)
	for(var/obj/O in get_step(loc, dir))
		if(O.flags & WALL_ITEM)
			if(O.pixel_x == 0 && O.pixel_y == 0)
				return 1
	return 0

/proc/screen_loc2turf(scr_loc, turf/origin)
	var/tX = splittext(scr_loc, ",")
	var/tY = splittext(tX[2], ":")
	var/tZ = origin.z
	tY = tY[1]
	tX = splittext(tX[1], ":")
	tX = tX[1]
	tX = max(1, min(world.maxx, origin.x + (text2num(tX) - (world.view + 1))))
	tY = max(1, min(world.maxy, origin.y + (text2num(tY) - (world.view + 1))))
	return locate(tX, tY, tZ)

/proc/get_holder_at_turf_level(const/atom/movable/O)
	if(!istype(O)) //atom/movable does not include areas
		return
	var/atom/A
	for(A=O, A && !isturf(A.loc), A=A.loc);  // semicolon is for the empty statement
	return A

/// A key for the light this atom casts (range, power, colour), compared before and after a first draw to see whether the draw moved it (look_stamp.dm,
/// lazy first draw). The host has no lighting; code/content/lighting/lighting_atom.dm answers.
/atom/proc/look_light_key()
	return null

/// The turf whose contents a client sees through this turf (open space shows the level below), or null. The host has no levels;
/// code/content/behaviours/turf_transparency.dm answers. refresh_drain_near() follows it so a parked first draw below open space is drawn.
/turf/proc/seen_through()
	return null
