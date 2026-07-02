// On-demand expedition z-level generator + lifecycle controller.
//
// Replaces the old SSquarry depth/elevator system. Each launch allocates (or
// recycles) a z-level, carves a procedural cave network into it, bridges it into
// the multi-z atmos table, scatters ambient POIs + loot, and lets a bound
// /datum/expedition_mission populate its objective content. The subsystem fires
// slowly to poll mission completion and to recycle a site's z-level once the
// crew has left.
//
// Z-levels are never truly freed in BYOND (world.maxz only grows), so released
// sites are wiped back to bare substrate and their z pushed onto free_z for the
// next generate_site() to reuse.
SUBSYSTEM_DEF(expedition)
	name = "Expedition"
	wait = 2 SECONDS
	priority = FIRE_PRIORITY_DEFAULT
	/// "[z]" -> /datum/expedition_site for every live site.
	var/list/sites = list()
	/// Wiped z-levels available for reuse.
	var/list/free_z = list()
	/// Launch consoles that have registered themselves.
	var/list/consoles = list()

/datum/controller/subsystem/expedition/Initialize()
	ensure_console()
	return SS_INIT_SUCCESS

/datum/controller/subsystem/expedition/fire(resumed = FALSE)
	for(var/key in sites.Copy())
		var/datum/expedition_site/site = sites[key]
		if(!istype(site))
			sites -= key
			continue

		// Poll mission completion (cheap per-mission check).
		if(site.mission && !site.rewarded && site.mission.state == EXP_MISSION_ACTIVE)
			if(site.mission.check_completion())
				site.mission.on_complete()
				site.rewarded = TRUE
				site.status = EXP_STATUS_COMPLETE
				log_world("SSexpedition: mission '[site.mission.name]' completed on [site.name] (z[site.z_level]).")

		// Presence-driven lifecycle.
		var/players = players_on_z(site.z_level)
		if(players > 0)
			site.last_occupied = world.time
			continue
		if(site.status >= EXP_STATUS_ACTIVE && (world.time - site.last_occupied) > EXP_AUTO_RELEASE_GRACE)
			release_site(site)
		else if(site.status == EXP_STATUS_READY && (world.time - site.generated_at) > 5 MINUTES)
			release_site(site)

// ---- Generation -----------------------------------------------------------

// Generate a site, optionally bound to a mission. Returns the site (or null).
/datum/controller/subsystem/expedition/proc/generate_site(datum/expedition_mission/mission = null, difficulty = EXP_DIFF_LOW)
	if(mission)
		difficulty = mission.difficulty

	var/z = acquire_z()
	if(!isnum(z) || z < 1)
		log_world("SSexpedition: failed to acquire a z-level for a new site.")
		return null

	// Pick and lay down the biome terrain (cavern / plains / asteroid / orbital).
	var/datum/expedition_biome/biome = pick_biome(mission)
	biome.generate(z)

	// Wire the freshly-(re)allocated z into the LINDA multi-z atmos table.
	if(SSair)
		SSair.build_multiz_atmos_levels()

	var/datum/expedition_site/site = new(z, difficulty)
	site.biome = biome
	site.size = expedition_roll_size()
	// Roll (or take the mission's pinned) enemy faction — themes every hostile here.
	site.faction = mission?.faction_type || expedition_pick_faction(difficulty)
	site.floors = scan_floors(z)
	if(!length(site.floors))
		log_world("SSexpedition: site on z[z] carved no walkable floor; releasing.")
		wipe_z(z)
		free_z |= z
		qdel(site)
		return null
	site.landing = pick(site.floors)
	site.name = "Site [pick("Theta", "Sigma", "Kappa", "Vega", "Orion", "Lyra", "Cygnus", "Draco")]-[rand(1, 99)]"
	if(biome)
		site.name += " ([biome.name])"
	site.name += " — [expedition_faction_name(site.faction)]"

	// Base loot + ambient POIs for reward density and flavour (scaled by size).
	scatter_loot(site)
	scatter_ambient_pois(site, (1 + difficulty) + site.size * 2)

	// A light site-wide wash of faction set-dressing between the POIs.
	if(site.faction != EXP_FACTION_FAUNA)
		for(var/i in 1 to 3 + site.size * 3)
			var/turf/T = site.random_floor()
			if(T)
				expedition_faction_decorate(T, 1, site.faction, 1)

	// Let the mission lay down its objective content.
	if(mission)
		site.mission = mission
		mission.populate(site)

	// Drop the extraction beacon on the landing pad.
	var/obj/structure/expedition_return_beacon/beacon = new(site.landing)
	beacon.site = site
	site.beacon = beacon

	site.status = EXP_STATUS_READY
	sites["[z]"] = site
	log_world("SSexpedition: generated [site.name] on z[z] (difficulty [difficulty][mission ? ", mission '[mission.name]'" : ""]).")
	return site

// Reuse a pooled z if available, else allocate a fresh one.
/datum/controller/subsystem/expedition/proc/acquire_z()
	while(length(free_z))
		var/z = free_z[1]
		free_z.Cut(1, 2)
		if(isnum(z) && z >= 1 && z <= world.maxz)
			return z
	var/datum/map_template/expedition_site/template = new()
	return template.load_new_z()

// Roll a biome for a new site. Missions may pin one via their biome_type var.
/datum/controller/subsystem/expedition/proc/pick_biome(datum/expedition_mission/mission)
	var/static/list/biome_pool = list(
		/datum/expedition_biome/cave = 10,
		/datum/expedition_biome/plains = 8,
		/datum/expedition_biome/asteroid = 6,
		/datum/expedition_biome/orbital = 6,
	)
	var/biome_type = mission?.biome_type || pickweight(biome_pool)
	return new biome_type()

/datum/controller/subsystem/expedition/proc/scan_floors(z)
	var/list/out = list()
	for(var/turf/T in block(locate(1, 1, z), locate(world.maxx, world.maxy, z)))
		if(expedition_is_walkable(T))
			out += T
	return out

/datum/controller/subsystem/expedition/proc/scatter_loot(datum/expedition_site/site)
	var/loot_count = min(length(site.floors), (4 + site.difficulty * 2) * site.size)
	for(var/i in 1 to loot_count)
		expedition_spawn_loot(pick(site.floors), expedition_roll_tier(site.difficulty, site.size))

/datum/controller/subsystem/expedition/proc/scatter_ambient_pois(datum/expedition_site/site, count)
	var/static/list/ambient_pool = list(
		/datum/expedition_poi/nest = 12,
		/datum/expedition_poi/cache = 14,
		/datum/expedition_poi/salvage_field = 8,
		/datum/expedition_poi/relay = 6,
		/datum/expedition_poi/outpost = 5,
		/datum/expedition_poi/hive = 5,
	)
	for(var/i in 1 to count)
		var/turf/T = site.random_floor()
		if(!T)
			break
		var/poi_type = pickweight(ambient_pool)
		var/datum/expedition_poi/P = new poi_type()
		// Respect each POI's min_difficulty — too-tough POIs just don't seed here.
		if(P.min_difficulty > site.difficulty)
			qdel(P)
			continue
		P.stamp(T, site)
		qdel(P)

// ---- Release / recycle ----------------------------------------------------

/datum/controller/subsystem/expedition/proc/release_site(datum/expedition_site/site)
	if(!istype(site))
		return
	var/z = site.z_level
	site.status = EXP_STATUS_EXPIRED
	sites -= "[z]"
	if(site.origin_console && site.origin_console.active_site == site)
		site.origin_console.active_site = null
	wipe_z(z)
	if(z >= 1 && z <= world.maxz)
		free_z |= z
	log_world("SSexpedition: released [site.name], z[z] recycled.")
	qdel(site)

// Clear every movable off a z and reset its turfs to bare substrate so the next
// carve starts clean. Never deletes a connected player (defensive).
/datum/controller/subsystem/expedition/proc/wipe_z(z)
	var/wiped = 0
	for(var/turf/T in block(locate(1, 1, z), locate(world.maxx, world.maxy, z)))
		for(var/atom/movable/AM in T)
			if(ismob(AM))
				var/mob/M = AM
				if(M.client)
					continue
			qdel(AM)
		if(!istype(T, /turf/simulated/mineral/cave))
			T.ChangeTurf(/turf/simulated/mineral/cave, tell_universe = FALSE)
		if(++wiped % 1000 == 0)
			CHECK_TICK

// ---- Helpers --------------------------------------------------------------

/datum/controller/subsystem/expedition/proc/players_on_z(z)
	var/count = 0
	for(var/mob/M in GLOB.player_list)
		if(M.z == z)
			count++
	return count

// Place a launch console on the station if none was mapped in.
/datum/controller/subsystem/expedition/proc/ensure_console()
	if(length(consoles))
		return
	for(var/area_type in list(/area/hangar/three, /area/hangar, /area/hangar/one, /area/hangar/two))
		for(var/turf/T in get_area_turfs(area_type))
			if(T.density || istype(T, /turf/space))
				continue
			new /obj/machinery/computer/expedition(T)
			log_world("SSexpedition: auto-placed launch console in [area_type] at [T.x],[T.y],[T.z].")
			return
	log_world("SSexpedition: no suitable station area found to auto-place a launch console.")
