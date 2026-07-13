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
	new /datum/random_map/automata/cave_system/expedition(null, 1, 1, z, world.maxx, world.maxy)

// ---------------------------------------------------------------------------
// Plains — open grassland with scattered rock outcrops. Breathable surface.
// ---------------------------------------------------------------------------
/datum/expedition_biome/plains
	name = "Plains"
	desc = "open windswept grassland"
	weight = 8

/datum/expedition_biome/plains/generate(z)
	var/n = 0
	for(var/x = 2 to world.maxx - 1)
		for(var/y = 2 to world.maxy - 1)
			var/turf/T = locate(x, y, z)
			if(T)
				T.ChangeTurf(/turf/simulated/floor/outdoors/grass, tell_universe = FALSE)
			if(++n % 500 == 0)
				CHECK_TICK
	// Rock outcrops as obstacles / cover.
	for(var/i in 1 to rand(24, 44))
		scatter_outcrop(z, rand(4, world.maxx - 4), rand(4, world.maxy - 4))

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
	new /datum/random_map/automata/cave_system/expedition(null, 1, 1, z, world.maxx, world.maxy)
	// Expose the rim to space.
	for(var/x = 2 to world.maxx - 1)
		expose(locate(x, 2, z))
		expose(locate(x, world.maxy - 1, z))
	for(var/y = 2 to world.maxy - 1)
		expose(locate(2, y, z))
		expose(locate(world.maxx - 1, y, z))
	// Punch a handful of vacuum windows into the rock (walls only — never the
	// floor crews walk on, so nobody floats off mid-stride).
	for(var/i in 1 to rand(10, 18))
		var/turf/T = locate(rand(4, world.maxx - 4), rand(4, world.maxy - 4), z)
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
	for(var/x = 2 to world.maxx - 1)
		for(var/y = 2 to world.maxy - 1)
			var/turf/T = locate(x, y, z)
			if(T)
				T.ChangeTurf(/turf/space, tell_universe = FALSE)
			if(++n % 500 == 0)
				CHECK_TICK
	// Lay a central plating platform — the deck the crew operates on.
	var/px1 = round(world.maxx * 0.28)
	var/px2 = round(world.maxx * 0.72)
	var/py1 = round(world.maxy * 0.28)
	var/py2 = round(world.maxy * 0.72)
	for(var/x = px1 to px2)
		for(var/y = py1 to py2)
			var/turf/T = locate(x, y, z)
			if(T)
				T.ChangeTurf(/turf/simulated/floor/plating, tell_universe = FALSE)
			if(++n % 500 == 0)
				CHECK_TICK
