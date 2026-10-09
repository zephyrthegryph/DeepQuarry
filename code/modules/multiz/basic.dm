// If you add a more comprehensive system, just untick this file.
GLOBAL_LIST_EMPTY(z_levels)// Each bit re... haha just kidding this is a list of bools now

// If the height is more than 1, we mark all contained levels as connected.
CAPABILITIES(/obj/effect/landmark/map_data)
	configure(map_resolver(GLOBAL_PROC_REF(resolve_map_data), vars = list("height")))

/// MAP_RESOLVER for map data: marks the levels below this one (height) as connected.
/proc/resolve_map_data(atom/loc, path, list/varedits)
	var/obj/effect/landmark/map_data/P = path
	var/turf/T = get_turf(loc)
	if(!T)
		return TRUE
	var/height = MAP_VAR(P, varedits, height)
	for(var/i = (T.z - height + 1) to (T.z - 1))
		if(length(GLOB.z_levels) < i)
			GLOB.z_levels.len = i
		GLOB.z_levels[i] = TRUE
	return TRUE

// The storage of connections between adjacent levels means some bitwise magic is needed.
/proc/HasAbove(z)
	if(z >= world.maxz || z < 1 || z > length(GLOB.z_levels))
		return 0
	return GLOB.z_levels[z]

/proc/HasBelow(z)
	if(z > world.maxz || z < 2 || (z-1) > length(GLOB.z_levels))
		return 0
	return GLOB.z_levels[z-1]

// Thankfully, no bitwise magic is needed here.
/proc/GetAbove(atom/atom)
	var/turf/turf = get_turf(atom)
	if(!turf)
		return null
	return HasAbove(turf.z) ? get_step(turf, UP) : null

/proc/GetBelow(atom/atom)
	var/turf/turf = get_turf(atom)
	if(!turf)
		return null
	return HasBelow(turf.z) ? get_step(turf, DOWN) : null

/proc/GetConnectedZlevels(z)
	. = list(z)
	for(var/level = z, HasBelow(level), level--)
		. |= level-1
	for(var/level = z, HasAbove(level), level++)
		. |= level+1

/proc/AreConnectedZLevels(zA, zB)
	return zA == zB || (zB in GetConnectedZlevels(zA))

/proc/get_zstep(ref, dir)
	if(dir == UP)
		. = GetAbove(ref)
	else if (dir == DOWN)
		. = GetBelow(ref)
	else
		. = get_step(ref, dir)
