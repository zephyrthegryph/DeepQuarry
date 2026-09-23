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

/datum/expedition_teardown_job
	var/datum/controller/subsystem/expedition/controller
	var/datum/expedition_site/site
	var/z_level
	var/reason
	var/yield_count = 0
	var/tick_budget = 60

/datum/expedition_teardown_job/New(datum/controller/subsystem/expedition/new_controller, datum/expedition_site/new_site, new_reason)
	..()
	controller = new_controller
	site = new_site
	z_level = new_site?.z_level
	reason = new_reason

/datum/expedition_teardown_job/Destroy()
	controller = null
	site = null
	return ..()

/datum/expedition_teardown_job/proc/checkpoint()
	if(TICK_USAGE >= tick_budget)
		yield_count++
		sleep(0)

/datum/expedition_teardown_job/proc/execute()
	if(!controller || !site || QDELETED(site))
		qdel(src)
		return
	var/site_name = site.name
	controller.wipe_z(z_level, src)
	if(z_level >= 1 && z_level <= world.maxz)
		controller.free_z |= z_level
	controller.teardown_z -= "[z_level]"
	log_world("SSexpedition: released [site_name], z[z_level] recycled after [yield_count] budget yields (reason: [reason]).")
	qdel(site)
	qdel(src)

SUBSYSTEM_DEF(expedition)
	name = "Expedition"
	wait = 2 SECONDS
	priority = FIRE_PRIORITY_DEFAULT
	/// "[z]" -> /datum/expedition_site for every live site.
	var/list/sites = list()
	/// Wiped z-levels available for reuse.
	var/list/free_z = list()
	/// Z-levels currently being cleared incrementally and unavailable for reuse.
	var/list/teardown_z = list()

/datum/controller/subsystem/expedition/Initialize()
	#ifndef CITESTING
	// Pay world.maxz growth during startup rather than during the first player
	// jump. The blank vacuum level remains unavailable until generation claims it.
	var/datum/map_template/expedition_site/template = new
	var/preallocated_z = template.load_new_z()
	qdel(template)
	if(isnum(preallocated_z) && preallocated_z >= 1)
		free_z |= preallocated_z
		log_world("SSexpedition: preallocated expedition z[preallocated_z] during startup.")
	#endif
	return SS_INIT_SUCCESS

/datum/controller/subsystem/expedition/proc/plot_for_vessel(mob/user, datum/flight_vessel/vessel, atom/payout_source)
	if(!vessel?.shuttle || !vessel.has_capabilities(FLIGHT_CAP_EXPEDITION | FLIGHT_CAP_LAND))
		to_chat(user, span_warning("This vessel cannot perform surface expeditions."))
		return null
	if(vessel.active_expedition && !QDELETED(vessel.active_expedition) && vessel.active_expedition.status != EXP_STATUS_EXPIRED)
		to_chat(user, span_warning("This vessel already has an active expedition assignment."))
		return null
	var/list/choices = list()
	for(var/mission_type in expedition_mission_types())
		var/datum/expedition_mission/preview = new mission_type()
		choices[preview.name] = mission_type
		qdel(preview)
	var/choice = tgui_input_list(user, "Select an expedition contract", "Flight Operations", choices)
	if(!choice || !CanInteract(user, GLOB.tgui_default_state))
		return null
	var/list/threat_bands = expedition_threat_bands()
	var/threat_band = tgui_input_list(user, "Select a threat band", "Flight Operations", threat_bands)
	if(!threat_band || !CanInteract(user, GLOB.tgui_default_state))
		return null
	var/difficulty = threat_bands[threat_band]
	if(!isnum(difficulty))
		to_chat(user, span_warning("Flight Operations rejected an invalid threat band."))
		return null
	var/mission_type = choices[choice]
	var/datum/expedition_mission/mission = new mission_type(difficulty)
	mission.faction_type = expedition_pick_faction(difficulty)
	var/datum/expedition_site/site = create_site_descriptor(mission, difficulty, vessel.shuttle)
	if(!site)
		qdel(mission)
		to_chat(user, span_warning("Flight Operations could not survey a viable destination."))
		return null
	site.assigned_flight_vessel = vessel
	site.payout_turf = get_turf(payout_source)
	vessel.active_expedition = site
	to_chat(user, span_notice("[site.name] has been surveyed. Select it in Flight Operations to begin the jump and generate its landing zone."))
	return site

/datum/controller/subsystem/expedition/proc/abandon_assignment(mob/user, datum/flight_vessel/vessel)
	var/datum/expedition_site/site = vessel?.active_expedition
	if(!site || QDELETED(site))
		return FALSE
	var/datum/flight_destination/destination = SSflight_operations?.destinations[site.flight_destination_id]
	if(LAZYLEN(destination?.active_plans))
		to_chat(user, span_warning("The assignment cannot be abandoned while a flight plan is using it."))
		return FALSE
	if(site.z_level > 0 && players_on_z(site.z_level))
		to_chat(user, span_warning("The assignment cannot be abandoned while crew remain at the site."))
		return FALSE
	vessel.active_expedition = null
	if(site.z_level > 0 && sites["[site.z_level]"] == site)
		release_site(site, "assignment abandoned")
	else
		if(site.flight_destination_id)
			SSflight_operations?.unregister_destination(site.flight_destination_id)
		qdel(site)
	to_chat(user, span_notice("The expedition assignment has been abandoned."))
	return TRUE

/datum/controller/subsystem/expedition/proc/create_site_descriptor(datum/expedition_mission/mission, difficulty = EXP_DIFF_LOW, datum/shuttle/autodock/overmap/assigned_shuttle = null, obj/machinery/computer/shuttle_control/explore/origin_console = null, parent_destination_id = null)
	if(mission)
		difficulty = mission.difficulty
	var/datum/expedition_site/site = new(0, difficulty)
	site.name = "Site [pick("Theta", "Sigma", "Kappa", "Vega", "Orion", "Lyra", "Cygnus", "Draco")]-[rand(1, 99)]"
	site.faction = mission?.faction_type || expedition_pick_faction(difficulty)
	site.name += " — [expedition_faction_name(site.faction)]"
	site.mission = mission
	site.assigned_shuttle = assigned_shuttle
	site.origin_console = origin_console
	site.parent_destination_id = parent_destination_id
	site.payout_turf = get_turf(origin_console)
	var/datum/flight_vessel/assigned_vessel = SSflight_operations?.vessel_for_ship(assigned_shuttle?.myship)
	site.assigned_flight_vessel = assigned_vessel
	if(assigned_vessel)
		assigned_vessel.active_expedition = site
	site.status = EXP_STATUS_GENERATING
	SSflight_operations?.register_expedition(site)
	return site

/datum/controller/subsystem/expedition/proc/materialize_site(datum/expedition_site/site, datum/flight_plan/plan)
	if(!site || QDELETED(site) || !plan)
		return FALSE
	if(site.z_level > 0 && site.landing_waypoint)
		plan.generation_state = FLIGHT_GENERATION_READY
		plan.generation_progress = 100
		plan.generation_stage = "Destination ready"
		return TRUE
	plan.generation_progress = 5
	plan.generation_stage = "Allocating planetary survey area"
	INVOKE_ASYNC(src, PROC_REF(materialize_site_async), site, plan)
	return TRUE

/datum/controller/subsystem/expedition/proc/materialize_site_async(datum/expedition_site/descriptor, datum/flight_plan/plan)
	if(!descriptor || QDELETED(descriptor) || !plan || QDELETED(plan))
		return
	var/datum/expedition_mission/mission = descriptor.mission
	descriptor.mission = null
	plan.generation_progress = 15
	plan.generation_stage = "Generating terrain"
	var/datum/expedition_site/site = generate_site(mission, descriptor.difficulty, descriptor.assigned_shuttle, descriptor.origin_console, plan)
	if(!site)
		descriptor.mission = mission
		if(plan && !QDELETED(plan))
			plan.generation_state = FLIGHT_GENERATION_FAILED
			plan.generation_stage = "Terrain generation failed"
		return
	var/descriptor_name = descriptor.name
	var/old_destination_id = descriptor.flight_destination_id
	site.name = descriptor_name
	if(site.overmap_sector)
		site.overmap_sector.name = descriptor_name
	if(site.landing_waypoint)
		site.landing_waypoint.name = "[descriptor_name] - Expedition Landing Zone"
	if(descriptor.origin_console?.active_expedition == descriptor)
		descriptor.origin_console.active_expedition = site
	if(descriptor.assigned_flight_vessel?.active_expedition == descriptor)
		descriptor.assigned_flight_vessel.active_expedition = site
	site.assigned_flight_vessel = descriptor.assigned_flight_vessel
	site.payout_turf = descriptor.payout_turf
	var/datum/flight_destination/destination = SSflight_operations?.destinations[old_destination_id]
	if(destination)
		var/generated_destination_id = site.flight_destination_id
		if(generated_destination_id && generated_destination_id != old_destination_id)
			SSflight_operations.unregister_destination(generated_destination_id)
		destination.name = descriptor_name
		destination.expedition = site
		destination.target = site.overmap_sector
		if(site.overmap_sector)
			SSflight_operations.destination_by_target[REF(site.overmap_sector)] = destination.id
		site.flight_destination_id = destination.id
	descriptor.origin_console = null
	descriptor.assigned_shuttle = null
	descriptor.assigned_flight_vessel = null
	descriptor.payout_turf = null
	qdel(descriptor)
	if(!plan || QDELETED(plan))
		return
	plan.generation_progress = 100
	plan.generation_state = FLIGHT_GENERATION_READY
	plan.generation_stage = "Landing zone ready"

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
			for(var/mob/living/L in GLOB.player_list)
				if(L.z == site.z_level)
					site.participants |= L
			site.last_occupied = world.time
			continue
		if(site.status >= EXP_STATUS_ACTIVE)
			if(site.has_travel_lease())
				continue
			if(site.has_active_assignment() && site.status != EXP_STATUS_COMPLETE)
				continue
			// Never release within the deploy grace window: crew may still be in the
			// bluespace-travel gap (0 on-z players) between fire() and arrival.
			if(site.deployed_at && (world.time - site.deployed_at) <= EXP_DEPLOY_GRACE)
				continue
			if((world.time - site.last_occupied) > EXP_AUTO_RELEASE_GRACE)
				release_site(site, "unoccupied after deployment")
		else if(site.status == EXP_STATUS_READY && !site.has_active_assignment() && (world.time - site.generated_at) > 5 MINUTES)
			release_site(site, "unassigned before deployment")

// ---- Generation -----------------------------------------------------------

/// Minimal sealed publication target used only after every rich-layout attempt
/// fails. It deliberately has no department simulation contract: its job is to
/// guarantee a pressurized, walkable destination and preserve the expedition.
/proc/generated_station_emergency_spec(seed)
	var/datum/generated_station_spec/spec = new
	spec.seed = seed
	spec.id = "station-emergency-[seed]"
	spec.name = "[generated_station_designation(seed)] Emergency Annex"
	spec.grid_width = 17
	spec.grid_height = 17
	spec.maximum_area = 225
	spec.size_class = "emergency"
	spec.layout_archetype = "fallback_annex"
	return spec

/proc/generated_station_emergency_materialization(datum/generated_station_spec/spec, z)
	var/datum/generated_station_materialization/materialization = new
	materialization.station_id = spec.id
	materialization.z_level = z
	materialization.origin_x = max(1, round((world.maxx - spec.grid_width) / 2))
	materialization.origin_y = max(1, round((world.maxy - spec.grid_height) / 2))
	var/area/generated_station/transit/emergency_area = new
	emergency_area.station_id = spec.id
	emergency_area.department_id = "emergency"
	emergency_area.name = "[spec.name] Habitable Annex"
	materialization.transit_area = emergency_area
	for(var/local_x in 1 to spec.grid_width)
		for(var/local_y in 1 to spec.grid_height)
			var/turf/T = materialization.world_turf(local_x, local_y)
			if(local_x == 1 || local_y == 1 || local_x == spec.grid_width || local_y == spec.grid_height)
				T = T.ChangeTurf(/turf/simulated/wall, tell_universe = FALSE)
				materialization.wall_count++
			else
				T = T.ChangeTurf(/turf/simulated/floor/tiled, tell_universe = FALSE)
				generated_station_seed_air(T)
				materialization.floor_count++
			ChangeArea(T, emergency_area)
	var/turf/arrival = materialization.world_turf(round(spec.grid_width / 2), round(spec.grid_height / 2))
	materialization.entry = new(arrival)
	materialization.entry.station_id = spec.id
	materialization.degradation_events += "rich station generation exhausted; published sealed emergency annex"
	return materialization

// Generate a site, optionally bound to a mission. Returns the site (or null).
/datum/controller/subsystem/expedition/proc/generate_site(datum/expedition_mission/mission = null, difficulty = EXP_DIFF_LOW, datum/shuttle/autodock/overmap/assigned_shuttle = null, obj/machinery/computer/shuttle_control/explore/origin_console = null, datum/flight_plan/flight_plan = null)
	if(mission)
		difficulty = mission.difficulty

	var/gen_started = REALTIMEOFDAY
	var/z = acquire_z()
	if(!isnum(z) || z < 1)
		log_world("SSexpedition: failed to acquire a z-level for a new site.")
		return null
	var/t_zalloc = REALTIMEOFDAY
	if(flight_plan && !QDELETED(flight_plan))
		flight_plan.generation_progress = 20
		flight_plan.generation_stage = "Survey volume reserved"

	// Build a reproducible station instead of seeding legacy biome content.
	var/generation_seed = max(1, round((world.realtime + world.time * 1009 + z * 7919) % 2147483646))
	var/datum/generated_station_spec/station_spec
	var/datum/generated_station_materialization/station_materialization
	var/materialization_yields = 0
	var/materialization_elapsed = 0
	// A live destination is monotonic once its z-level has been reserved. Retry
	// the rich planner with deterministic alternate seeds, then publish a small
	// emergency station instead of returning no destination.
	for(var/attempt in 1 to 3)
		var/attempt_seed = ((generation_seed + (attempt - 1) * 104729 - 1) % 16000000) + 1
		var/datum/generated_station_planner/planner = new
		station_spec = planner.plan(attempt_seed)
		var/planner_error = planner.error_message
		qdel(planner)
		if(!station_spec)
			log_world("SSexpedition: generated-station planning attempt [attempt] failed on z[z] (seed [attempt_seed]): [planner_error || "no specification"].")
			continue
		var/datum/generated_station_materializer/materializer = new
		materializer.strict_room_contracts = FALSE
		var/origin_x = max(1, round((world.maxx - station_spec.grid_width) / 2))
		var/origin_y = max(1, round((world.maxy - station_spec.grid_height) / 2))
		station_materialization = materializer.materialize(station_spec, z, origin_x, origin_y, flight_plan)
		materialization_yields += materializer.last_yield_count
		materialization_elapsed += materializer.last_elapsed_seconds
		var/materialization_error = materializer.last_failure_details
		qdel(materializer)
		if(station_materialization)
			generation_seed = attempt_seed
			break
		log_world("SSexpedition: generated-station materialization attempt [attempt] failed on z[z] (seed [attempt_seed]): [materialization_error || "no result"].")
		qdel(station_spec)
		station_spec = null
		wipe_z(z)
	if(!station_materialization)
		generation_seed = max(1, generation_seed % 16000000)
		station_spec = generated_station_emergency_spec(generation_seed)
		station_materialization = generated_station_emergency_materialization(station_spec, z)
		log_world("SSexpedition: rich generation exhausted on z[z]; publishing emergency station [station_spec.name].")
	var/t_biome = REALTIMEOFDAY
	if(flight_plan && !QDELETED(flight_plan))
		flight_plan.generation_progress = 55
		flight_plan.generation_stage = "Station structure generated"

	// Wire the freshly-(re)allocated z into the LINDA multi-z atmos table.
	if(SSair)
		SSair.update_dynamic_multiz_atmos_level(z)
	var/t_multiz = REALTIMEOFDAY
	if(flight_plan && !QDELETED(flight_plan))
		flight_plan.generation_progress = 65
		flight_plan.generation_stage = "Atmospheric topology linked"

	var/datum/expedition_site/site = new(z, difficulty)
	site.generation_seed = generation_seed
	site.station_spec = station_spec
	site.station_materialization = station_materialization
	if(!site.initialize_generated_station_utilities())
		station_materialization.degradation_events += "utility initialization failed; station published with local emergency services"
	if(!site.initialize_generated_station_runtime())
		station_materialization.degradation_events += "strategic runtime initialization failed"
	if(site.station_director && !site.initialize_generated_station_infrastructure())
		station_materialization.degradation_events += "strategic infrastructure initialization failed"
	if(!site.repair_generated_station_runtime_access())
		station_materialization.degradation_events += "post-utility access repair was incomplete"
	if(site.station_director && !site.initialize_generated_station_defenders())
		station_materialization.degradation_events += "defender initialization failed"
	site.size = expedition_roll_size()
	// Roll (or take the mission's pinned) enemy faction — themes every hostile here.
	site.faction = mission?.faction_type || expedition_pick_faction(difficulty)
	site.floors = scan_floors(z)
	var/t_scan = REALTIMEOFDAY
	if(flight_plan && !QDELETED(flight_plan))
		flight_plan.generation_progress = 72
		flight_plan.generation_stage = "Selecting landing zone"
	if(!length(site.floors))
		var/turf/fallback_floor = locate(round(world.maxx / 2), round(world.maxy / 2), z)
		fallback_floor = fallback_floor.ChangeTurf(/turf/simulated/floor/tiled, tell_universe = FALSE)
		ChangeArea(fallback_floor, station_materialization.transit_area)
		generated_station_seed_air(fallback_floor)
		site.floors += fallback_floor
		station_materialization.degradation_events += "no planned floor survived; installed an emergency landing floor"
	site.landing = get_turf(station_materialization.entry)
	if(!site.landing || site.landing.density)
		site.landing = site.floors[1]
		QDEL_NULL(station_materialization.entry)
		station_materialization.entry = new(site.landing)
		station_materialization.entry.station_id = station_spec.id
		station_materialization.degradation_events += "planned docking entry was unusable; moved arrival to the first walkable floor"
	site.name = station_spec.name
	site.name += " — [expedition_faction_name(site.faction)]"
	site.assigned_shuttle = assigned_shuttle
	site.origin_console = origin_console
	site.payout_turf = get_turf(origin_console)

	var/obj/effect/shuttle_landmark/automatic/clearing/expedition/waypoint = new(site.landing)
	waypoint.site = site
	site.landing_waypoint = waypoint

	// Let the mission lay down its objective content.
	if(mission)
		site.mission = mission
		mission.populate(site)
		if(!mission.has_viable_objectives())
			station_materialization.degradation_events += "mission objective population was incomplete"
			log_world("SSexpedition: [site.name] published without complete mission objectives; destination remains playable.")
	if(flight_plan && !QDELETED(flight_plan))
		flight_plan.generation_progress = 92
		flight_plan.generation_stage = "Validating objectives and approach"

	site.status = EXP_STATUS_READY
	sites["[z]"] = site
	SSflight_operations?.register_expedition(site)
	log_world("SSexpedition: generated [site.name] on z[z] (seed [generation_seed], difficulty [difficulty][mission ? ", mission '[mission.name]'" : ""]).")
	log_world("SSexpedition: incremental materialization used [materialization_yields] budget yields across [materialization_elapsed]s.")
	// Phase timing (real seconds) — generation is rare, so always log; this is
	// the first place to look when site generation gets slow.
	log_world("SSexpedition: timing z-alloc=[(t_zalloc - gen_started) / 10]s station=[(t_biome - t_zalloc) / 10]s multiz=[(t_multiz - t_biome) / 10]s floor-scan=[(t_scan - t_multiz) / 10]s content=[(REALTIMEOFDAY - t_scan) / 10]s total=[(REALTIMEOFDAY - gen_started) / 10]s")
	return site

// Reuse a pooled z if available, else allocate a fresh one — capped so runaway
// launches can't grow world.maxz without bound. Returns null on failure.
/datum/controller/subsystem/expedition/proc/acquire_z()
	while(length(free_z))
		var/z = free_z[1]
		free_z.Cut(1, 2)
		if(isnum(z) && z >= 1 && z <= world.maxz)
			// Pooled levels must expose vacuum beyond the generated hull even if a
			// failed or interrupted teardown left another substrate behind.
			if(!istype(locate(1, 1, z), /turf/space))
				wipe_z(z)
			return z
	// Pool is empty: only allocate a new z if we're under the site-z cap.
	if((length(sites) + length(free_z) + length(teardown_z)) >= EXP_MAX_SITE_ZLEVELS)
		log_world("SSexpedition: at the [EXP_MAX_SITE_ZLEVELS]-z site cap with an empty reuse pool; refusing to allocate a new z-level.")
		return null
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

/datum/controller/subsystem/expedition/proc/release_site(datum/expedition_site/site, reason = "unspecified")
	if(!istype(site))
		return
	var/z = site.z_level
	site.status = EXP_STATUS_EXPIRED
	sites -= "[z]"
	if(site.flight_destination_id)
		SSflight_operations?.unregister_destination(site.flight_destination_id)
	if(site.origin_console && site.origin_console.active_expedition == site)
		site.origin_console.active_expedition = null
	if(site.assigned_flight_vessel?.active_expedition == site)
		site.assigned_flight_vessel.active_expedition = null
	QDEL_NULL(site.landing_waypoint)
	QDEL_NULL(site.overmap_sector)
	teardown_z["[z]"] = TRUE
	var/datum/expedition_teardown_job/job = new(src, site, reason)
	INVOKE_ASYNC(job, TYPE_PROC_REF(/datum/expedition_teardown_job, execute))

// Clear every movable off a z and reset it to vacuum for the next generated
// station. Never deletes a connected player (defensive).
/datum/controller/subsystem/expedition/proc/wipe_z(z, datum/expedition_teardown_job/job)
	var/wiped = 0
	var/area/space/space_area = generated_station_space_area()
	for(var/turf/T in block(locate(1, 1, z), locate(world.maxx, world.maxy, z)))
		// Deleting a closet or crate spills what it holds onto the turf (its
		// drop policy), so sweep again until only connected players are left.
		for(var/pass in 1 to 8)
			var/list/doomed = list()
			for(var/atom/movable/AM in T)
				if(ismob(AM))
					var/mob/M = AM
					if(M.client)
						continue
				doomed += AM
			if(!length(doomed))
				break
			for(var/atom/movable/AM as anything in doomed)
				if(!QDELETED(AM))
					qdel(AM)
				job?.checkpoint()
		if(!istype(T, /turf/space))
			T.ChangeTurf(/turf/space, tell_universe = FALSE)
		ChangeArea(T, space_area)
		wiped++
		if(job)
			job.checkpoint()
		else if(wiped % 1000 == 0)
			CHECK_TICK

// ---- Helpers --------------------------------------------------------------

/datum/controller/subsystem/expedition/proc/players_on_z(z)
	var/count = 0
	for(var/mob/M in GLOB.player_list)
		if(M.z == z)
			count++
	return count
