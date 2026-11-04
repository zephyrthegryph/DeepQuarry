//Returns: all the areas in the world
/proc/return_areas()
	var/list/area/areas = list()
	for(var/area/A in world)
		areas[A.name] = A
	return areas

//Returns: all the areas in the world, sorted.
/proc/return_sorted_areas()
	return sortTim(return_areas(), GLOBAL_PROC_REF(cmp_text_asc))

//Takes: Area type as text string or as typepath OR an instance of the area.
//Returns: A list of all turfs in areas of that type of that type in the world.
/proc/get_area_turfs(areatype)
	if(!areatype) return null
	if(istext(areatype)) areatype = text2path(areatype)
	if(isarea(areatype))
		var/area/areatemp = areatype
		areatype = areatemp.type

	var/list/turfs = new/list()
	for(var/area/N in world)
		if(istype(N, areatype))
			for(var/turf/T in N) turfs += T
	return turfs

//Takes: An instance of the area.
//Returns: A list of all turfs in that area.
//Side note: I don't know why this was never a thing. Did everyone just ignore the Blueprint item?! - C.L.
/proc/get_current_area_turfs(area/checked_area)
	if(!checked_area)
		return null

	var/list/turfs = new/list()
	for(var/turf/counted_turfs in contents_of(checked_area)) //Cheap. Efficient. Lovely.
		turfs += counted_turfs
	return turfs

//Takes: Area type as text string or as typepath OR an instance of the area.
//Returns: A list of all atoms	(objs, turfs, mobs) in areas of that type of that type in the world.
/proc/get_area_all_atoms(areatype)
	if(!areatype) return null
	if(istext(areatype)) areatype = text2path(areatype)
	if(isarea(areatype))
		var/area/areatemp = areatype
		areatype = areatemp.type

	var/list/atoms = new/list()
	for(var/area/N in world)
		if(istype(N, areatype))
			for(var/atom/A in N)
				atoms += A
	return atoms

//Takes: Area as an instance of the area.
//Returns: A list of all atoms	(objs, turfs, mobs) in the selected area.
/proc/get_current_area_atoms(area/checked_area)
	if(!checked_area)
		return null

	var/list/atoms = new/list()
	for(var/atom/A in contents_of(checked_area))
		atoms += A
	return atoms
