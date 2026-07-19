// Expedition biomes — the terrain a site is built on.
//
// Each biome reshapes a freshly-allocated (mineral-substrate) z-level into a
// distinct environment, then the shared pipeline (loot, POIs, buildings,
// mission content) runs on whatever walkable floor it produced. The site picks
// a biome by weight at generation time.

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

/datum/expedition_biome
	/// Display name, shown on the console.
	var/name = "Cavern"
	/// One-liner for flavour.
	var/desc = "an underground cavern network"
	/// Selection weight.
	var/weight = 10
	/// Informational: is the site a vacuum (crews want internals)?
	var/vacuum = FALSE

/datum/expedition_biome/proc/generate(z)
	return

// ---------------------------------------------------------------------------
// Cavern — organic mineral caves carved by the cellular-automata generator.
// ---------------------------------------------------------------------------
/datum/expedition_biome/cave
	name = "Cavern"
	desc = "an organic mineral cave network"
	weight = 10

/datum/expedition_biome/cave/generate(z)
	new /datum/random_map/automata/cave_system/expedition(null, expedition_region_min_x(), expedition_region_min_y(), z, EXP_REGION_SIZE, EXP_REGION_SIZE)

// ---------------------------------------------------------------------------
// Plains — open grassland with scattered rock outcrops. Breathable surface.
// ---------------------------------------------------------------------------
/datum/expedition_biome/plains
	name = "Plains"
	desc = "open windswept grassland"
	weight = 8

/datum/expedition_biome/plains/generate(z)
	var/n = 0
	for(var/x = expedition_region_min_x() to expedition_region_max_x())
		for(var/y = expedition_region_min_y() to expedition_region_max_y())
			var/turf/T = locate(x, y, z)
			if(T)
				T.ChangeTurf(/turf/simulated/floor/outdoors/grass, tell_universe = FALSE)
			if(++n % 500 == 0)
				CHECK_TICK
	// Rock outcrops as obstacles / cover.
	for(var/i in 1 to rand(24, 44))
		scatter_outcrop(z, rand(expedition_region_min_x() + 2, expedition_region_max_x() - 2), rand(expedition_region_min_y() + 2, expedition_region_max_y() - 2))

/datum/expedition_biome/plains/proc/scatter_outcrop(z, cx, cy)
	var/turf/center = locate(cx, cy, z)
	if(!center)
		return
	for(var/turf/T in range(rand(1, 2), center))
		if(prob(55))
			T.ChangeTurf(/turf/simulated/mineral/cave, tell_universe = FALSE)

// ---------------------------------------------------------------------------
// Asteroid — mineral caverns, but exposed to space at the edges and pocked with
// vacuum windows. Airless.
// ---------------------------------------------------------------------------
/datum/expedition_biome/asteroid
	name = "Asteroid"
	desc = "a hollowed asteroid adrift in the void"
	weight = 6
	vacuum = TRUE

/datum/expedition_biome/asteroid/generate(z)
	new /datum/random_map/automata/cave_system/expedition(null, expedition_region_min_x(), expedition_region_min_y(), z, EXP_REGION_SIZE, EXP_REGION_SIZE)
	// Expose the rim to space.
	for(var/x = expedition_region_min_x() to expedition_region_max_x())
		expose(locate(x, expedition_region_min_y(), z))
		expose(locate(x, expedition_region_max_y(), z))
	for(var/y = expedition_region_min_y() to expedition_region_max_y())
		expose(locate(expedition_region_min_x(), y, z))
		expose(locate(expedition_region_max_x(), y, z))
	// Punch a handful of vacuum windows into the rock (walls only — never the
	// floor crews walk on, so nobody floats off mid-stride).
	for(var/i in 1 to rand(10, 18))
		var/turf/T = locate(rand(expedition_region_min_x() + 2, expedition_region_max_x() - 2), rand(expedition_region_min_y() + 2, expedition_region_max_y() - 2), z)
		if(T && T.density)
			T.ChangeTurf(/turf/space, tell_universe = FALSE)

/datum/expedition_biome/asteroid/proc/expose(turf/T)
	if(T)
		T.ChangeTurf(/turf/space, tell_universe = FALSE)

// ---------------------------------------------------------------------------
// Orbital — a station deck adrift in low orbit: a central plating platform
// surrounded by open space. Airless outside any structure.
// ---------------------------------------------------------------------------
/datum/expedition_biome/orbital
	name = "Low Orbit"
	desc = "a derelict station deck in low orbit"
	weight = 6
	vacuum = TRUE

/datum/expedition_biome/orbital/generate(z)
	var/n = 0
	// Flood the interior with space.
	for(var/x = expedition_region_min_x() to expedition_region_max_x())
		for(var/y = expedition_region_min_y() to expedition_region_max_y())
			var/turf/T = locate(x, y, z)
			if(T)
				T.ChangeTurf(/turf/space, tell_universe = FALSE)
			if(++n % 500 == 0)
				CHECK_TICK
	// Lay a central plating platform — the deck the crew operates on.
	var/px1 = expedition_region_min_x() + 12
	var/px2 = expedition_region_max_x() - 12
	var/py1 = expedition_region_min_y() + 12
	var/py2 = expedition_region_max_y() - 12
	for(var/x = px1 to px2)
		for(var/y = py1 to py2)
			var/turf/T = locate(x, y, z)
			if(T)
				T.ChangeTurf(/turf/simulated/floor/plating, tell_universe = FALSE)
			if(++n % 500 == 0)
				CHECK_TICK
