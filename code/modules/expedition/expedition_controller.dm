/// Turfs per batched destroy when a z-level is wiped.
#define WIPE_Z_CHUNK 64

// On-demand expedition z-level generator + lifecycle controller.
//
// Replaces the old SSquarry depth/elevator system. Each launch allocates (or
// recycles) a z-level, carves a procedural cave network into it, bridges it into
// the multi-z atmos table, scatters ambient POIs + loot, and lets a bound
// /datum/expedition_mission populate its objective content. The service's lane
// runs slowly (on demand, while any site is live) to poll mission completion and to recycle a site's z-level once the
// crew has left.
//
// Z-levels are never truly freed in BYOND (world.maxz only grows), so released
// sites are wiped back to bare substrate and their z pushed onto free_z for the
// next generate_site() to reuse.

/datum/expedition_teardown_job
	var/tmp/datum/world_service/expedition/controller_static
	var/tmp/site_handle
	var/z_level
	var/reason
	var/yield_count = 0
	var/tick_budget = 60
	/// The z's turfs, in wipe order, while the job runs.
	var/tmp/list/turfs

/datum/expedition_teardown_job/New(datum/world_service/expedition/new_controller, datum/expedition_site/new_site, new_reason)
	..()
	controller_static = new_controller
	site_handle = om_handle(new_site)
	z_level = new_site?.z_level
	reason = new_reason

/// Clears the z as lane work (om_task_slices(), object_model_core.md §4.11): a turf at a time,
/// resuming by cursor, within the scheduler's budget. Nothing sleeps.
/datum/expedition_teardown_job/proc/execute()
	if(!controller() || !site() || QDELETED(site()))
		qdel(src)
		return
	turfs = block(locate(1, 1, z_level), locate(world.maxx, world.maxy, z_level))
	om_task_slices(src, PROC_REF(wipe_slice), 1, PROC_REF(finish))

/// A slice of the wipe: turfs from `cursor` while the slice's budget lasts.
/datum/expedition_teardown_job/proc/wipe_slice(cursor)
	var/started = TICK_USAGE
	var/area/space/space_area = generated_station_space_area()
	var/i = cursor
	while(i <= length(turfs))
		// A chunk of turfs at a time, each chunk one batched destroy.
		var/last = min(length(turfs), i + WIPE_Z_CHUNK - 1)
		controller().wipe_turfs(turfs.Copy(i, last + 1), space_area)
		i = last + 1
		if(i <= length(turfs) && TICK_USAGE - started >= tick_budget)
			yield_count++
			return i
	return null

/datum/expedition_teardown_job/proc/finish()
	turfs = null
	if(!controller() || !site() || QDELETED(site()))
		qdel(src)
		return
	var/site_name = site().name
	if(z_level >= 1 && z_level <= world.maxz)
		controller().free_z |= z_level
	controller().teardown_z -= "[z_level]"
	log_world("Expedition: released [site_name], z[z_level] recycled after [yield_count] budget yields (reason: [reason]).")
	qdel(site())
	qdel(src)

// The expedition world service (was GLOB.expedition_service). On demand: the lifecycle poll lane is parked
// while no site is live and woken when a site is registered.
GLOBAL_DATUM_INIT(expedition_service, /datum/world_service/expedition, new)

/datum/world_service/expedition
	name = "Expedition"
	lane = /datum/om/behaviour/world/expedition
	on_demand = TRUE
	// The old subsystem had no dependencies and initialized in the main stage. Its setup
	// preallocates a z-level through load_new_z(), which needs the map system up and should
	// follow the station mapload, so boot right after SSmapping.
	boot_after = /datum/controller/subsystem/mapping
	/// "[z]" -> /datum/expedition_site for every live site.
	var/list/sites = list()
	/// Surveyed site descriptors not yet materialized (z_level 0). Flight
	/// destinations and vessels name a descriptor only by handle, so this list
	/// is what owns it until it is materialized, abandoned or deleted.
	var/list/descriptors
	/// Wiped z-levels available for reuse.
	var/list/free_z = list()
	/// Running survey-point score earned by completed missions this round.
	var/survey_points_total = 0
	/// Z-levels currently being cleared incrementally and unavailable for reuse.
	var/list/teardown_z = list()

/datum/world_service/expedition/initialize()
	initialized = TRUE
	#ifndef CITESTING
	// Pay world.maxz growth during startup rather than during the first player
	// jump. The blank vacuum level remains unavailable until generation claims it.
	var/datum/map_template/expedition_site/template = new
	var/preallocated_z = template.load_new_z()
	qdel(template)
	if(isnum(preallocated_z) && preallocated_z >= 1)
		free_z |= preallocated_z
		log_world("Expedition: preallocated expedition z[preallocated_z] during startup.")
	#endif
	log_world("World service [name] initialized: [length(free_z)] free z-levels.")

/datum/world_service/expedition/proc/plot_for_vessel(mob/user, datum/flight_vessel/vessel, atom/payout_source)
	if(!vessel?.shuttle() || !vessel.has_capabilities(FLIGHT_CAP_EXPEDITION | FLIGHT_CAP_LAND))
		to_chat(user, span_warning("This vessel cannot perform surface expeditions."))
		return null
	if(vessel.active_expedition() && !QDELETED(vessel.active_expedition()) && vessel.active_expedition().status != EXP_STATUS_EXPIRED)
		to_chat(user, span_warning("This vessel already has an active expedition assignment."))
		return null
	var/list/choices = list()
	for(var/mission_type in expedition_mission_types())
		var/datum/expedition_mission/preview = new mission_type()
		choices[preview.name] = mission_type
		qdel(preview)
	var/choice = rerun_ask(user, "k105", PROC_REF(plot_for_vessel), args, /datum/om/prompt/choice, message = "Select an expedition contract", title = "Flight Operations", choices = choices)
	if(isnull(choice))
		return
	if(!choice || !CanInteract(user, GLOB.tgui_default_state))
		return null
	var/list/threat_bands = expedition_threat_bands()
	var/threat_band = rerun_ask(user, "k109", PROC_REF(plot_for_vessel), args, /datum/om/prompt/choice, message = "Select a threat band", title = "Flight Operations", choices = threat_bands)
	if(isnull(threat_band))
		return
	if(!threat_band || !CanInteract(user, GLOB.tgui_default_state))
		return null
	var/difficulty = threat_bands[threat_band]
	if(!isnum(difficulty))
		to_chat(user, span_warning("Flight Operations rejected an invalid threat band."))
		return null
	var/mission_type = choices[choice]
	var/datum/expedition_mission/mission = new mission_type(difficulty)
	mission.faction_type = expedition_pick_faction(difficulty)
	var/datum/expedition_site/site = create_site_descriptor(mission, difficulty, vessel.shuttle())
	if(!site)
		qdel(mission)
		to_chat(user, span_warning("Flight Operations could not survey a viable destination."))
		return null
	site.assigned_flight_vessel_handle = om_handle(vessel)
	site.payout_turf_handle = om_handle(get_turf(payout_source))
	vessel.active_expedition_handle = om_handle(site)
	to_chat(user, span_notice("[site.name] has been surveyed. Select it in Flight Operations to begin the jump and generate its landing zone."))
	return site

/datum/world_service/expedition/proc/abandon_assignment(mob/user, datum/flight_vessel/vessel)
	var/datum/expedition_site/site = vessel?.active_expedition()
	if(!site || QDELETED(site))
		return FALSE
	var/datum/flight_destination/destination = GLOB.flight_service?.destinations[site.flight_destination_id]
	if(LAZYLEN(destination?.active_plans))
		to_chat(user, span_warning("The assignment cannot be abandoned while a flight plan is using it."))
		return FALSE
	if(site.z_level > 0 && players_on_z(site.z_level))
		to_chat(user, span_warning("The assignment cannot be abandoned while crew remain at the site."))
		return FALSE
	vessel.active_expedition_handle = null
	if(site.z_level > 0 && sites["[site.z_level]"] == site)
		release_site(site, "assignment abandoned")
	else
		if(site.flight_destination_id)
			GLOB.flight_service?.unregister_destination(site.flight_destination_id)
		qdel(site)
	to_chat(user, span_notice("The expedition assignment has been abandoned."))
	return TRUE

/datum/world_service/expedition/proc/create_site_descriptor(datum/expedition_mission/mission, difficulty = EXP_DIFF_LOW, datum/shuttle/autodock/overmap/assigned_shuttle = null, obj/machinery/computer/shuttle_control/explore/origin_console = null, parent_destination_id = null)
	if(mission)
		difficulty = mission.difficulty
	var/datum/expedition_site/site = new(0, difficulty)
	site.name = "Site [pick("Theta", "Sigma", "Kappa", "Vega", "Orion", "Lyra", "Cygnus", "Draco")]-[rand(1, 99)]"
	site.faction = mission?.faction_type || expedition_pick_faction(difficulty)
	site.name += " — [expedition_faction_name(site.faction)]"
	site.mission = mission
	site.assigned_shuttle_handle = om_handle(assigned_shuttle)
	site.origin_console_handle = om_handle(origin_console)
	site.parent_destination_id = parent_destination_id
	site.payout_turf_handle = om_handle(get_turf(origin_console))
	var/datum/flight_vessel/assigned_vessel = GLOB.flight_service?.vessel_for_ship(assigned_shuttle?.myship())
	site.assigned_flight_vessel_handle = om_handle(assigned_vessel)
	if(assigned_vessel)
		assigned_vessel.active_expedition_handle = om_handle(site)
	site.status = EXP_STATUS_GENERATING
	LAZYADD(descriptors, site)
	GLOB.flight_service?.register_expedition(site)
	return site

/datum/world_service/expedition/proc/materialize_site(datum/expedition_site/site, datum/flight_plan/plan)
	if(!site || QDELETED(site) || !plan)
		return FALSE
	if(site.z_level > 0 && site.landing_waypoint)
		plan.generation_state = FLIGHT_GENERATION_READY
		plan.generation_progress = 100
		plan.generation_stage = "Destination ready"
		return TRUE
	plan.generation_progress = 5
	plan.generation_stage = "Allocating planetary survey area"
	INVOKE_ASYNC(src, PROC_REF(materialize_site_async), site, plan) // ALLOW(scheduler): site generation allocates/wipes z-levels and yields (stoplag); callers run on the non-sleeping flight lane
	return TRUE

/datum/world_service/expedition/proc/materialize_site_async(datum/expedition_site/descriptor, datum/flight_plan/plan)
	if(!descriptor || QDELETED(descriptor) || !plan || QDELETED(plan))
		return
	var/datum/expedition_mission/mission = descriptor.mission
	descriptor.mission = null
	plan.generation_progress = 15
	plan.generation_stage = "Generating terrain"
	generate_site_async(mission, descriptor.difficulty, descriptor.assigned_shuttle(), descriptor.origin_console(), plan, CALLBACK(src, PROC_REF(site_materialized), descriptor, plan, mission))

/// The generated site replaces its descriptor (the destination the crew planned against).
/datum/world_service/expedition/proc/site_materialized(datum/expedition_site/descriptor, datum/flight_plan/plan, datum/expedition_mission/mission, datum/expedition_site/site)
	if(!site)
		descriptor.mission = mission
		if(plan && !QDELETED(plan))
			plan.generation_state = FLIGHT_GENERATION_FAILED
			plan.generation_stage = "Terrain generation failed"
		return
	var/descriptor_name = descriptor.name
	var/old_destination_id = descriptor.flight_destination_id
	site.name = descriptor_name
	if(site.overmap_sector())
		site.overmap_sector().name = descriptor_name
	if(site.landing_waypoint)
		site.landing_waypoint.name = "[descriptor_name] - Expedition Landing Zone"
	if(descriptor.origin_console()?.active_expedition() == descriptor)
		descriptor.origin_console().active_expedition_handle = om_handle(site)
	if(descriptor.assigned_flight_vessel()?.active_expedition() == descriptor)
		descriptor.assigned_flight_vessel().active_expedition_handle = om_handle(site)
	site.assigned_flight_vessel_handle = om_handle(descriptor.assigned_flight_vessel())
	site.payout_turf_handle = om_handle(descriptor.payout_turf())
	var/datum/flight_destination/destination = GLOB.flight_service?.destinations[old_destination_id]
	if(destination)
		var/generated_destination_id = site.flight_destination_id
		if(generated_destination_id && generated_destination_id != old_destination_id)
			GLOB.flight_service.unregister_destination(generated_destination_id)
		destination.name = descriptor_name
		destination.expedition_handle = om_handle(site)
		destination.target_handle = om_handle(site.overmap_sector())
		if(site.overmap_sector())
			GLOB.flight_service.destination_by_target[REF(site.overmap_sector())] = destination.id
		site.flight_destination_id = destination.id
	descriptor.origin_console_handle = null
	descriptor.assigned_shuttle_handle = null
	descriptor.assigned_flight_vessel_handle = null
	descriptor.payout_turf_handle = null
	qdel(descriptor)
	if(!plan || QDELETED(plan))
		return
	plan.generation_progress = 100
	plan.generation_state = FLIGHT_GENERATION_READY
	plan.generation_stage = "Landing zone ready"

/datum/world_service/expedition/service_step(resumed)
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
				log_world("Expedition: mission '[site.mission.name]' completed on [site.name] (z[site.z_level]).")

		// Presence-driven lifecycle.
		var/players = players_on_z(site.z_level)
		if(players > 0)
			for(var/mob/living/L in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
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
			// bluespace-travel gap (0 on-z players) between service_step() and arrival.
			if(site.deployed_at && ELAPSED_SINCE(src, site.deployed_at, CLOCK_WORLD) <= EXP_DEPLOY_GRACE)
				continue
			if(ELAPSED_SINCE(src, site.last_occupied, CLOCK_WORLD) > EXP_AUTO_RELEASE_GRACE)
				release_site(site, "unoccupied after deployment")
		else if(site.status == EXP_STATUS_READY && !site.has_active_assignment() && ELAPSED_SINCE(src, site.generated_at, CLOCK_WORLD) > 5 MINUTES)
			release_site(site, "unassigned before deployment")
	return TRUE

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
	var/area/generated_station/transit/emergency_area = generated_station_create_area(/area/generated_station/transit)
	emergency_area.station_id = spec.id
	emergency_area.department_id = "emergency"
	emergency_area.name = "[spec.name] Habitable Annex"
	materialization.transit_area_handle = om_handle(emergency_area)
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
	materialization.entry_handle = om_handle(new /obj/effect/landmark/generated_station_entry(arrival))
	materialization.entry().station_id = spec.id
	generated_station_emergency_utilities(spec, materialization, emergency_area)
	materialization.degradation_events += "rich station generation exhausted; published sealed emergency annex"
	return materialization

/// The annex is a real destination, so it gets a minimal self-contained power
/// and lighting set: one cell-backed APC on the west wall and a wall light on
/// each side. Everything is owned by the materialization so teardown removes it.
/proc/generated_station_emergency_utilities(datum/generated_station_spec/spec, datum/generated_station_materialization/materialization, area/generated_station/emergency_area)
	var/mid_x = round(spec.grid_width / 2)
	var/mid_y = round(spec.grid_height / 2)
	var/turf/apc_turf = materialization.world_turf(2, mid_y)
	if(istype(apc_turf, /turf/simulated/floor))
		var/obj/machinery/power/apc/APC = new(apc_turf)
		APC.set_dir(WEST)
		emergency_area.apc = APC
		materialization.infrastructure += APC
		if(APC.terminal)
			materialization.infrastructure += APC.terminal
	var/list/light_sockets = list(
		list(materialization.world_turf(mid_x, spec.grid_height - 1), NORTH, 0, 26),
		list(materialization.world_turf(mid_x, 2), SOUTH, 0, -26),
		list(materialization.world_turf(spec.grid_width - 1, mid_y), EAST, 26, 0),
		list(materialization.world_turf(2, mid_y + 2), WEST, -26, 0),
	)
	for(var/list/socket in light_sockets)
		var/turf/T = socket[1]
		if(!istype(T, /turf/simulated/floor))
			continue
		var/obj/machinery/light/light = new(T)
		light.set_dir(socket[2])
		light.pixel_x = socket[3]
		light.pixel_y = socket[4]
		materialization.infrastructure += light
	emergency_area.power_change()

// Generate a site, optionally bound to a mission. Returns the site (or null).
/datum/world_service/expedition/proc/generate_site(datum/expedition_mission/mission = null, difficulty = EXP_DIFF_LOW, datum/shuttle/autodock/overmap/assigned_shuttle = null, obj/machinery/computer/shuttle_control/explore/origin_console = null, datum/flight_plan/flight_plan = null)
	if(mission)
		difficulty = mission.difficulty

	var/gen_started = REALTIMEOFDAY
	var/z = acquire_z()
	if(!isnum(z) || z < 1)
		log_world("Expedition: failed to acquire a z-level for a new site.")
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
		// A failed materialization can leave partial turfs, areas, and atoms on
		// the z. Every attempt (and the emergency fallback) must start from
		// vacuum, so wipe before each attempt after the first.
		if(attempt > 1)
			wipe_z(z)
		var/datum/generated_station_planner/planner = new
		station_spec = planner.plan(attempt_seed)
		var/planner_error = planner.error_message
		qdel(planner)
		if(!station_spec)
			log_world("Expedition: generated-station planning attempt [attempt] failed on z[z] (seed [attempt_seed]): [planner_error || "no specification"].")
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
		log_world("Expedition: generated-station materialization attempt [attempt] failed on z[z] (seed [attempt_seed]): [materialization_error || "no result"].")
		qdel(station_spec)
		station_spec = null
		wipe_z(z)
	return publish_generated_site(mission, difficulty, assigned_shuttle, origin_console, flight_plan, z, gen_started, t_zalloc, generation_seed, station_spec, station_materialization, materialization_yields, materialization_elapsed)

/// generate_site() for the live game: the same attempts, but planning and materializing run as
/// lane work and timers (object_model_core.md §4.11), so nothing sleeps. `on_done` is invoked
/// with the site, or null.
/datum/world_service/expedition/proc/generate_site_async(datum/expedition_mission/mission = null, difficulty = EXP_DIFF_LOW, datum/shuttle/autodock/overmap/assigned_shuttle = null, obj/machinery/computer/shuttle_control/explore/origin_console = null, datum/flight_plan/flight_plan = null, datum/callback/on_done)
	if(mission)
		difficulty = mission.difficulty
	var/gen_started = REALTIMEOFDAY
	var/list/needs_wipe = list()
	var/z = acquire_z(needs_wipe)
	if(!isnum(z) || z < 1)
		log_world("Expedition: failed to acquire a z-level for a new site.")
		on_done?.Invoke(null)
		return
	var/list/generation = list(
		"mission" = mission,
		"difficulty" = difficulty,
		"shuttle" = assigned_shuttle,
		"console" = origin_console,
		"plan" = flight_plan,
		"z" = z,
		"started" = gen_started,
		"zalloc" = REALTIMEOFDAY,
		// Build a reproducible station instead of seeding legacy biome content.
		"seed" = max(1, round((world.realtime + world.time * 1009 + z * 7919) % 2147483646)),
		"attempt" = 0,
		"yields" = 0,
		"elapsed" = 0,
		"done" = on_done,
	)
	if(flight_plan && !QDELETED(flight_plan))
		flight_plan.generation_progress = 20
		flight_plan.generation_stage = "Survey volume reserved"
	if(length(needs_wipe))
		// Pooled levels must expose vacuum beyond the generated hull even if a failed or
		// interrupted teardown left another substrate behind.
		wipe_z_async(z, CALLBACK(src, PROC_REF(generation_attempt), generation))
		return
	generation_attempt(generation)

/// The next planning attempt (a live destination is monotonic once its z-level is reserved:
/// retry with deterministic alternate seeds, then publish a small emergency station).
/datum/world_service/expedition/proc/generation_attempt(list/generation)
	generation["attempt"]++
	if(generation["attempt"] > 3)
		generation_publish(generation, null, null)
		return
	var/attempt_seed = ((generation["seed"] + (generation["attempt"] - 1) * 104729 - 1) % 16000000) + 1
	generation["attempt_seed"] = attempt_seed
	var/datum/generated_station_planner/planner = new
	planner.plan_async(attempt_seed, 160, 160, CALLBACK(src, PROC_REF(generation_planned), generation, planner))

/datum/world_service/expedition/proc/generation_planned(list/generation, datum/generated_station_planner/planner, datum/generated_station_spec/station_spec)
	var/planner_error = planner.error_message
	qdel(planner)
	if(!station_spec)
		log_world("Expedition: generated-station planning attempt [generation["attempt"]] failed on z[generation["z"]] (seed [generation["attempt_seed"]]): [planner_error || "no specification"].")
		generation_attempt(generation)
		return
	var/datum/generated_station_materializer/materializer = new
	materializer.strict_room_contracts = FALSE
	var/origin_x = max(1, round((world.maxx - station_spec.grid_width) / 2))
	var/origin_y = max(1, round((world.maxy - station_spec.grid_height) / 2))
	materializer.materialize_async(station_spec, generation["z"], origin_x, origin_y, generation["plan"], FALSE, CALLBACK(src, PROC_REF(generation_materialized), generation, materializer, station_spec))

/datum/world_service/expedition/proc/generation_materialized(list/generation, datum/generated_station_materializer/materializer, datum/generated_station_spec/station_spec, datum/generated_station_materialization/station_materialization)
	generation["yields"] += materializer.last_yield_count
	generation["elapsed"] += materializer.last_elapsed_seconds
	var/materialization_error = materializer.last_failure_details
	qdel(materializer)
	if(station_materialization)
		generation["seed"] = generation["attempt_seed"]
		generation_publish(generation, station_spec, station_materialization)
		return
	log_world("Expedition: generated-station materialization attempt [generation["attempt"]] failed on z[generation["z"]] (seed [generation["attempt_seed"]]): [materialization_error || "no result"].")
	qdel(station_spec)
	wipe_z_async(generation["z"], CALLBACK(src, PROC_REF(generation_attempt), generation))

/datum/world_service/expedition/proc/generation_publish(list/generation, datum/generated_station_spec/station_spec, datum/generated_station_materialization/station_materialization)
	var/datum/expedition_site/site = publish_generated_site(generation["mission"], generation["difficulty"], generation["shuttle"], generation["console"], generation["plan"], generation["z"], generation["started"], generation["zalloc"], generation["seed"], station_spec, station_materialization, generation["yields"], generation["elapsed"])
	var/datum/callback/on_done = generation["done"]
	on_done?.Invoke(site)

/// wipe_z() as lane work: a turf at a time within the scheduler's budget, then `on_done`.
/datum/world_service/expedition/proc/wipe_z_async(z, datum/callback/on_done)
	evacuate_mobs_from_z(z)
	om_task_slices(src, PROC_REF(wipe_z_slice), list(block(locate(1, 1, z), locate(world.maxx, world.maxy, z)), 1), on_done)

/datum/world_service/expedition/proc/wipe_z_slice(list/cursor)
	var/list/turfs = cursor[1]
	var/area/space/space_area = generated_station_space_area()
	var/i = cursor[2]
	while(i <= length(turfs))
		// A chunk of turfs at a time, each chunk one batched destroy.
		var/last = min(length(turfs), i + WIPE_Z_CHUNK - 1)
		wipe_turfs(turfs.Copy(i, last + 1), space_area)
		i = last + 1
		if(i <= length(turfs) && om_scheduler().out_of_budget())
			cursor[2] = i
			return cursor
	return null

/// The rest of a generation once the station stands (or every attempt failed): the emergency
/// annex if needed, the site, its runtime, landing zone and mission. Returns the site.
/datum/world_service/expedition/proc/publish_generated_site(datum/expedition_mission/mission, difficulty, datum/shuttle/autodock/overmap/assigned_shuttle, obj/machinery/computer/shuttle_control/explore/origin_console, datum/flight_plan/flight_plan, z, gen_started, t_zalloc, generation_seed, datum/generated_station_spec/station_spec, datum/generated_station_materialization/station_materialization, materialization_yields, materialization_elapsed)
	if(!station_materialization)
		wipe_z(z)
		generation_seed = max(1, generation_seed % 16000000)
		station_spec = generated_station_emergency_spec(generation_seed)
		station_materialization = generated_station_emergency_materialization(station_spec, z)
		log_world("Expedition: rich generation exhausted on z[z]; publishing emergency station [station_spec.name].")
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
		ChangeArea(fallback_floor, station_materialization.transit_area())
		generated_station_seed_air(fallback_floor)
		site.floors += fallback_floor
		station_materialization.degradation_events += "no planned floor survived; installed an emergency landing floor"
	site.landing_handle = om_handle(get_turf(station_materialization.entry()))
	if(!site.landing() || site.landing().density)
		site.landing_handle = om_handle(site.floors[1])
		qdel_handle(station_materialization.entry_handle); station_materialization.entry_handle = null
		station_materialization.entry_handle = om_handle(new /obj/effect/landmark/generated_station_entry(site.landing()))
		station_materialization.entry().station_id = station_spec.id
		station_materialization.degradation_events += "planned docking entry was unusable; moved arrival to the first walkable floor"
	site.name = station_spec.name
	site.name += " — [expedition_faction_name(site.faction)]"
	site.assigned_shuttle_handle = om_handle(assigned_shuttle)
	site.origin_console_handle = om_handle(origin_console)
	site.payout_turf_handle = om_handle(get_turf(origin_console))

	var/obj/effect/shuttle_landmark/automatic/clearing/expedition/waypoint = new(site.landing())
	waypoint.site_handle = om_handle(site)
	site.landing_waypoint = waypoint

	// Let the mission lay down its objective content.
	if(mission)
		site.mission = mission
		mission.populate(site)
		if(!mission.has_viable_objectives())
			station_materialization.degradation_events += "mission objective population was incomplete"
			log_world("Expedition: [site.name] published without complete mission objectives; destination remains playable.")
	if(flight_plan && !QDELETED(flight_plan))
		flight_plan.generation_progress = 92
		flight_plan.generation_stage = "Validating objectives and approach"

	site.status = EXP_STATUS_READY
	sites["[z]"] = site
	demand()
	GLOB.flight_service?.register_expedition(site)
	log_world("Expedition: generated [site.name] on z[z] (seed [generation_seed], difficulty [difficulty][mission ? ", mission '[mission.name]'" : ""]).")
	log_world("Expedition: incremental materialization used [materialization_yields] budget yields across [materialization_elapsed]s.")
	// Phase timing (real seconds) — generation is rare, so always log; this is
	// the first place to look when site generation gets slow.
	log_world("Expedition: timing z-alloc=[(t_zalloc - gen_started) / 10]s station=[(t_biome - t_zalloc) / 10]s multiz=[(t_multiz - t_biome) / 10]s floor-scan=[(t_scan - t_multiz) / 10]s content=[(REALTIMEOFDAY - t_scan) / 10]s total=[(REALTIMEOFDAY - gen_started) / 10]s")
	return site

// Reuse a pooled z if available, else allocate a fresh one — capped so runaway
// launches can't grow world.maxz without bound. Returns null on failure.
/// `needs_wipe`: instead of wiping a pooled level that isn't vacuum, add it to this list (the
/// caller wipes it as lane work).
/datum/world_service/expedition/proc/acquire_z(list/needs_wipe)
	while(length(free_z))
		var/z = free_z[1]
		free_z.Cut(1, 2)
		if(isnum(z) && z >= 1 && z <= world.maxz)
			// Pooled levels must expose vacuum beyond the generated hull even if a
			// failed or interrupted teardown left another substrate behind.
			if(!istype(locate(1, 1, z), /turf/space))
				if(islist(needs_wipe))
					needs_wipe += z
				else
					wipe_z(z)
			return z
	// Pool is empty: only allocate a new z if we're under the site-z cap.
	if((length(sites) + length(free_z) + length(teardown_z)) >= EXP_MAX_SITE_ZLEVELS)
		log_world("Expedition: at the [EXP_MAX_SITE_ZLEVELS]-z site cap with an empty reuse pool; refusing to allocate a new z-level.")
		return null
	var/datum/map_template/expedition_site/template = new()
	return template.load_new_z()

// Roll a biome for a new site. Missions may pin one via their biome_type var.
/datum/world_service/expedition/proc/pick_biome(datum/expedition_mission/mission)
	var/static/list/biome_pool = list(
		/datum/expedition_biome/cave = 10,
		/datum/expedition_biome/plains = 8,
		/datum/expedition_biome/asteroid = 6,
		/datum/expedition_biome/orbital = 6,
	)
	var/biome_type = mission?.biome_type || pickweight(biome_pool)
	return new biome_type()

/datum/world_service/expedition/proc/scan_floors(z)
	var/list/out = list()
	for(var/turf/T in block(locate(1, 1, z), locate(world.maxx, world.maxy, z)))
		if(expedition_is_walkable(T))
			out += T
	return out

/datum/world_service/expedition/proc/scatter_loot(datum/expedition_site/site)
	var/loot_count = min(length(site.floors), (4 + site.difficulty * 2) * site.size)
	for(var/i in 1 to loot_count)
		expedition_spawn_loot(pick(site.floors), expedition_roll_tier(site.difficulty, site.size))

/datum/world_service/expedition/proc/scatter_ambient_pois(datum/expedition_site/site, count)
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

/datum/world_service/expedition/proc/release_site(datum/expedition_site/site, reason = "unspecified")
	if(!istype(site))
		return
	var/z = site.z_level
	site.status = EXP_STATUS_EXPIRED
	sites -= "[z]"
	if(site.flight_destination_id)
		GLOB.flight_service?.unregister_destination(site.flight_destination_id)
	if(site.origin_console() && site.origin_console().active_expedition() == site)
		site.origin_console().active_expedition_handle = null
	if(site.assigned_flight_vessel()?.active_expedition() == site)
		site.assigned_flight_vessel().active_expedition_handle = null
	QDEL_NULL(site.landing_waypoint)
	qdel_handle(site.overmap_sector_handle); site.overmap_sector_handle = null
	teardown_z["[z]"] = TRUE
	var/datum/expedition_teardown_job/job = new(src, site, reason)
	job.execute()

// Every mob still on a z that is about to be wiped is either a player (connected
// or not — a disconnected body still has a ckey/mind and must never be deleted
// or left floating in the vacuum the wipe produces) or an NPC. Players are moved
// to a safe turf; NPCs are removed with the rest of the level by wipe_turf().
/datum/world_service/expedition/proc/evacuate_mobs_from_z(z, turf/preferred_destination = null)
	var/turf/destination = preferred_destination
	if(!destination || destination.z == z || destination.density)
		destination = null
		var/list/candidates = list()
		for(var/obj/effect/landmark/L in REGISTRY_MEMBERS(REGISTRY_LATEJOIN))
			var/turf/T = get_turf(L)
			if(T && T.z != z && !T.density)
				candidates += T
		if(length(candidates))
			destination = pick(candidates)
	var/relocated = 0
	for(var/mob/M in REGISTRY_MEMBERS(REGISTRY_MOBS))
		if(QDELETED(M) || M.z != z)
			continue
		var/is_player = M.client || M.ckey || M.mind
		if(is_player && destination)
			M.forceMove(destination)
			to_chat(M, span_danger("The expedition site is being abandoned; you have been pulled back to safety."))
			relocated++
		else if(is_player)
			// No safe destination exists at all; leave the body untouched rather
			// than delete a player. The wipe below skips it as well.
			log_world("Expedition: no evacuation destination for [M] ([M.ckey]) on z[z]; leaving mob in place.")
		// NPCs are left to wipe_turf(), which deletes them with the rest of the level.
	if(relocated)
		log_world("Expedition: evacuated z[z]: [relocated] player mob(s) relocated.")

// Clear every movable off a z and reset it to vacuum for the next generated
// station. Never deletes a player mob (connected or not): they are evacuated
// first by evacuate_mobs_from_z(), and anything still left is skipped (defensive).
/datum/world_service/expedition/proc/wipe_z(z)
	evacuate_mobs_from_z(z)
	var/area/space/space_area = generated_station_space_area()
	var/list/turfs = block(locate(1, 1, z), locate(world.maxx, world.maxy, z))
	for(var/i = 1, i <= length(turfs), i += WIPE_Z_CHUNK)
		wipe_turfs(turfs.Copy(i, min(length(turfs), i + WIPE_Z_CHUNK - 1) + 1), space_area)
		CHECK_TICK

/// Clears `turfs` back to vacuum: everything on them (and anything that
/// would spill onto them) goes as one batched destroy (lifecycle/batch.dm),
/// sparing connected players, then each turf becomes space.
/datum/world_service/expedition/proc/wipe_turfs(list/turfs, area/space/space_area)
	qdel_batch(null, turfs)
	for(var/turf/T as anything in turfs)
		wipe_turf(T, space_area)

/// Clears one turf of a released site back to vacuum, sparing connected players.
/datum/world_service/expedition/proc/wipe_turf(turf/T, area/space/space_area)
	// Deleting a closet or crate spills what it holds onto the turf (its
	// drop policy), so sweep again until only connected players are left.
	for(var/pass in 1 to 8)
		var/list/doomed = list()
		for(var/atom/movable/AM in contents_of(T))
			if(ismob(AM))
				var/mob/M = AM
				if(M.client || M.ckey || M.mind)
					continue
			doomed += AM
		if(!length(doomed))
			break
		for(var/atom/movable/AM as anything in doomed)
			if(!QDELETED(AM))
				qdel(AM)
	if(!istype(T, /turf/space))
		T.ChangeTurf(/turf/space, tell_universe = FALSE)
	ChangeArea(T, space_area)

// ---- Helpers --------------------------------------------------------------

/datum/world_service/expedition/proc/players_on_z(z)
	var/count = 0
	for(var/mob/M in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
		if(M.z == z)
			count++
	return count

/// DECLARE_REF(..., STATIC): a shared definition/flyweight, held strongly and never cleared.
/datum/expedition_teardown_job/proc/controller() as /datum/world_service/expedition
	return controller_static
DECLARE_REF(/datum/expedition_teardown_job, "controller_static", STATIC, null)

/// LC-refs: the site this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/expedition_teardown_job/proc/site() as /datum/expedition_site
	return om_resolve(site_handle)

/// Work while any site is live.
/datum/world_service/expedition/has_work()
	return length(sites)

/datum/world_service/expedition/stat_line()
	return "Sites:[length(sites)] Free z:[length(free_z)] Teardown:[length(teardown_z)]"

/// Expedition mission polling and site release (was GLOB.expedition_service, 2 s). On demand.
/datum/om/behaviour/world/expedition
	name = "world: expedition"
	every = 2 SECONDS
	runlevels = RUNLEVELS_DEFAULT

/datum/om/behaviour/world/expedition/service()
	return GLOB.expedition_service

DECLARE_REF(/datum/world_service/expedition, "sites", OWNED_VALUES, null)
