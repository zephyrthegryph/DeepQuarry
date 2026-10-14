// Expedition terrain helpers: the walkability test and the carve region bounds.

// Shared test: a turf a crew can stand on and content can spawn on — non-dense
// and not open space. Used by floor scans across the system so any biome's
// ground (cave rock, grass, station plating) is recognised.
/proc/expedition_is_walkable(turf/T)
	return isturf(T) && !T.density && !istype(T, /turf/space)

/proc/expedition_region_min_x()
	return max(2, round((world.maxx - min(EXP_REGION_SIZE, world.maxx - 4)) / 2))

/proc/expedition_region_min_y()
	return max(2, round((world.maxy - min(EXP_REGION_SIZE, world.maxy - 4)) / 2))

/proc/expedition_region_max_x()
	return min(world.maxx - 1, expedition_region_min_x() + EXP_REGION_SIZE - 1)

/proc/expedition_region_max_y()
	return min(world.maxy - 1, expedition_region_min_y() + EXP_REGION_SIZE - 1)
