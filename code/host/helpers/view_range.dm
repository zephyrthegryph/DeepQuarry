/proc/view_or_range(distance = world.view , center , type)
	switch(type)
		if("view")
			. = view(distance,center)
		if("range")
			. = range(distance,center)
	return

GLOBAL_DATUM(dview_mob, /mob/dview)

//Version of view() which ignores darkness, because BYOND doesn't have it.
/proc/dview(range = world.view, center, invis_flags = 0)
	if(!center)
		return
	if(!GLOB.dview_mob) // Debugging
		GLOB.dview_mob = new

	GLOB.dview_mob.loc = center // ALLOW(containment): dview mob: hot view() helper, abstract placement without Enter/Crossed

	GLOB.dview_mob.see_invisible = invis_flags

	. = view(range, GLOB.dview_mob)
	GLOB.dview_mob.loc = null // ALLOW(containment): dview mob: hot view() helper, abstract nullspace park

/mob/dview
	invisibility = INVISIBILITY_ABSTRACT
	density = FALSE

	anchored = TRUE

	see_in_dark = 1e6

/// We don't want to be in any mob registry; we're a dummy not a mob.
/mob/dview/skips_registry(registry_id)
	return TRUE

// The shared dview mob refuses deletion unless forced, then is replaced.
/mob/dview/lifecycle_keep(force)
	stack_trace("Attempt to delete the dview_mob: [log_info_line(src)]")
	return !force

/mob/dview/on_destroy(force)
	GLOB.dview_mob = new
	..()

// Displays something as commonly used (non-submultiples) SI units.
//ultra range (no limitations on distance, faster than range for distances > 8); including areas drastically decreases performance
/proc/urange(dist=0, atom/center=null, orange=0, areas=0)
	if(!dist)
		if(!orange)
			return list(center)
		else
			return list()

	if(!get_turf(center))
		return list()

	var/list/turfs = RANGE_TURFS(dist, center)
	if(orange)
		turfs -= get_turf(center)
	. = list()
	for(var/turf/T as anything in turfs)
		. += T
		. += T.contents
		if(areas)
			. |= T.loc

/proc/spiral_range(dist = 0, atom/center = null, orange = FALSE)
	var/list/atom_list = list()
	var/turf/t_center = get_turf(center)
	if(!t_center)
		return list()

	if(!orange)
		atom_list += t_center
		atom_list += t_center.contents

	if(!dist)
		return atom_list

	var/turf/checked_turf
	var/y
	var/x
	var/c_dist = 1

	while( c_dist <= dist )
		y = t_center.y + c_dist
		x = t_center.x - c_dist + 1
		for(x in x to t_center.x + c_dist)
			checked_turf = locate(x, y, t_center.z)
			if(checked_turf)
				atom_list += checked_turf
				atom_list += checked_turf.contents

		y = t_center.y + c_dist - 1
		x = t_center.x + c_dist
		for(y in t_center.y - c_dist to y)
			checked_turf = locate(x, y, t_center.z)
			if(checked_turf)
				atom_list += checked_turf
				atom_list += checked_turf.contents

		y = t_center.y - c_dist
		x = t_center.x + c_dist - 1
		for(x in t_center.x - c_dist to x)
			checked_turf = locate(x, y, t_center.z)
			if(checked_turf)
				atom_list += checked_turf
				atom_list += checked_turf.contents

		y = t_center.y - c_dist + 1
		x = t_center.x - c_dist
		for(y in y to t_center.y + c_dist)
			checked_turf = locate(x, y, t_center.z)
			if(checked_turf)
				atom_list += checked_turf
				atom_list += checked_turf.contents
		c_dist++

	return atom_list

/*
	get_holder_at_turf_level(): Similar to get_turf(), will return the "highest up" holder of this atom, excluding the turf.
	Example: A fork inside a box inside a locker will return the locker. Essentially, get_just_before_turf().
*/ //Credit to /vg/
