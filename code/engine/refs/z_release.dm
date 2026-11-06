// z-level release and the per-level generation turf handles carry.

/// z-level release: every REF view naming a turf on `z` is cleared, the level's generation moves on
/// and its turf handles stop resolving. Returns how many views were cleared.
/proc/relation_drop_z(z)
	relation_z_generation_bump(z)
	. = rel_drop_z(z)
	for(var/turf/T as anything in block(locate(1, 1, z), locate(world.maxx, world.maxy, z)))
		var/packed = T.x + 512 * (T.y + 512 * T.z)
		var/key = GLOB.handle_turf_texts[packed]
		if(key)
			GLOB.handle_turf_pos -= key // the level's plain turf handles stop resolving (its generation moved on): drop their cached positions

/// Per z-level: bumped each time the level is released (relation_drop_z()), carried in turf handles.
GLOBAL_LIST_EMPTY(z_generations)

/proc/relation_z_generation(z)
	var/list/gens = GLOB.z_generations
	// A level never released reads 0, also where a bump of a higher level grew the list over it: a null entry compares unequal to the 0 a handle without a generation carries, and every turf handle of that level stopped resolving.
	return (z > 0 && z <= length(gens)) ? (gens[z] || 0) : 0

/proc/relation_z_generation_bump(z)
	if(z <= 0)
		return
	var/list/gens = GLOB.z_generations
	if(length(gens) < z)
		gens.len = z
	gens[z] = (gens[z] || 0) + 1
