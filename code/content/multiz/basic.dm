// The level map (which levels join the one above) is the mapping system's z_links_up, read through mapping_z_links_up().

// If the height is more than 1, we mark all contained levels as connected.
CAPABILITIES(/obj/effect/landmark/map_data)
	configure(map_resolver(GLOBAL_PROC_REF(resolve_map_data), vars = list("height")))

/// The map resolver of map data: marks the levels below this one (height) as connected.
/proc/resolve_map_data(atom/loc, path, list/varedits)
	var/obj/effect/landmark/map_data/P = path
	var/turf/T = get_turf(loc)
	if(!T)
		return TRUE
	var/height = MAP_VAR(P, varedits, height)
	for(var/i = (T.z - height + 1) to (T.z - 1))
		SSmapping.link_level_up(i)
	return TRUE

/proc/HasAbove(z)
	if(z >= world.maxz || z < 1)
		return FALSE
	return (z in mapping_z_links_up())

/proc/HasBelow(z)
	if(z > world.maxz || z < 2)
		return FALSE
	return ((z - 1) in mapping_z_links_up())

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
