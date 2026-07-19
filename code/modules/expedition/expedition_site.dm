// A single generated expedition site, one per dynamically-allocated z-level.
// Holds the site's identity, its bound mission, the crew deployed to it, and the
// lifecycle bookkeeping the controller uses to recycle the z-level once the crew
// has left.
/datum/expedition_site
	/// Human-readable designation, e.g. "Site Theta-3".
	var/name = "Expedition Site"
	/// The z-level this site occupies.
	var/z_level = 0
	/// Difficulty band the site was rolled at.
	var/difficulty = EXP_DIFF_LOW
	/// Size band (EXP_SIZE_*) — scales POI/loot count and building footprints.
	var/size = EXP_SIZE_SMALL
	/// EXP_STATUS_* lifecycle status.
	var/status = EXP_STATUS_GENERATING
	/// A safe, walkable turf crews arrive on.
	var/turf/landing
	/// Cached walkable floors, for content placement and respawns.
	var/list/floors
	/// The mission bound to this site (may be null for a raw debug site).
	var/datum/expedition_mission/mission
	/// The biome this site was generated as.
	var/datum/expedition_biome/biome
	/// Reproducible planner input and realized station geometry for this site.
	var/generation_seed
	var/datum/generated_station_spec/station_spec
	var/datum/generated_station_materialization/station_materialization
	/// The enemy faction (EXP_FACTION_*) guarding this site — themes every hostile spawn.
	var/faction = EXP_FACTION_FAUNA
	/// Mobs that have deployed here (for reward payout).
	var/list/participants
	/// The short-jump craft assigned to this expedition.
	var/datum/shuttle/autodock/overmap/assigned_shuttle
	/// Authoritative vessel assignment; survives console replacement or deletion.
	var/datum/flight_vessel/assigned_flight_vessel
	/// The craft's control console, used as the physical payout point.
	var/obj/machinery/computer/shuttle_control/explore/origin_console
	var/turf/payout_turf
	/// Overmap destination and landing waypoint owned by this site.
	var/obj/effect/overmap/visitable/sector/expedition/overmap_sector
	var/obj/effect/shuttle_landmark/automatic/clearing/expedition/landing_waypoint
	/// Stable destination registry key used before and after physical generation.
	var/flight_destination_id
	/// Planet destination that owns this surface site.
	var/parent_destination_id
	/// world.time at generation, and the last time a player was aboard.
	var/generated_at = 0
	var/last_occupied = 0
	/// world.time of the most recent deploy; guards against release during the
	/// bluespace-travel window (0 until the first deploy).
	var/deployed_at = 0
	/// Set once the mission's on_complete() has fired, so it only pays out once.
	var/rewarded = FALSE

/datum/expedition_site/New(_z_level, _difficulty = EXP_DIFF_LOW, turf/_landing)
	z_level = _z_level
	difficulty = _difficulty
	landing = _landing
	generated_at = world.time
	last_occupied = world.time
	participants = list()

/datum/expedition_site/Destroy()
	landing = null
	floors = null
	origin_console = null
	assigned_shuttle = null
	assigned_flight_vessel = null
	payout_turf = null
	overmap_sector = null
	landing_waypoint = null
	participants = null
	QDEL_LIST(station_controls)
	QDEL_NULL(station_defense)
	QDEL_NULL(station_director)
	QDEL_NULL(station_simulation)
	QDEL_NULL(station_utilities)
	if(mission)
		QDEL_NULL(mission)
	if(biome)
		QDEL_NULL(biome)
	QDEL_NULL(station_spec)
	QDEL_NULL(station_materialization)
	return ..()

// A random walkable floor on this site (prefers the cached list, falls back to
// a fresh scan if the cache is stale/empty). Biome-agnostic.
/datum/expedition_site/proc/random_floor()
	if(length(floors))
		var/turf/T = pick(floors)
		if(expedition_is_walkable(T) && T.z == z_level)
			return T
	// Rebuild the cache.
	floors = list()
	for(var/turf/T in block(locate(1, 1, z_level), locate(world.maxx, world.maxy, z_level)))
		if(expedition_is_walkable(T))
			floors += T
	if(length(floors))
		return pick(floors)
	return null

/datum/expedition_site/proc/has_active_assignment()
	if(assigned_flight_vessel && !QDELETED(assigned_flight_vessel) && assigned_flight_vessel.active_expedition == src)
		return TRUE
	return origin_console && !QDELETED(origin_console) && origin_console.active_expedition == src

/datum/expedition_site/proc/has_travel_lease()
	var/datum/flight_destination/destination = SSflight_operations?.destinations[flight_destination_id]
	return LAZYLEN(destination?.active_plans)
