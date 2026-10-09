// The expedition system's API (code/modules/expedition/expedition_controller.dm declares the system).
//
//   SSexpedition.plot_for_vessel(user, vessel, payout_source) / abandon_assignment(user, vessel)   a vessel's assignment
//   SSexpedition.create_site_descriptor(mission, difficulty, ...)    survey a site that is not generated yet
//   SSexpedition.generate_site(mission, ...) / materialize_site(site, plan) / release_site(site, reason)
//   SSexpedition.generate_debug_station(seed, ...)                   admin: a generated station on an expedition z-level

/datum/system/expedition/proc/plot_for_vessel(mob/user, datum/flight_vessel/vessel, atom/payout_source)
	if(!vessel?.shuttle() || !vessel.has_capabilities(FLIGHT_CAP_EXPEDITION | FLIGHT_CAP_LAND))
		to_chat(user, span_warning("This vessel cannot perform surface expeditions."))
		return null
	if(vessel.active_expedition() && !QDELETED(vessel.active_expedition()) && vessel.active_expedition().status != EXP_STATUS_EXPIRED)
		to_chat(user, span_warning("This vessel already has an active expedition assignment."))
		return null
	var/list/choices = list()
	for(var/mission_type in GLOB.expedition_mission_types)
		var/datum/expedition_mission/preview = new mission_type()
		choices[preview.name] = mission_type
		spent(preview, user)
	var/choice = rerun_ask(user, "k105", PROC_REF(plot_for_vessel), args, /datum/prompt/choice, question = "Select an expedition contract", title = "Flight Operations", choices = choices)
	if(isnull(choice))
		return
	if(!choice || !CanInteract(user, GLOB.tgui_default_state))
		return null
	var/list/threat_bands = GLOB.expedition_threat_bands
	var/threat_band = rerun_ask(user, "k109", PROC_REF(plot_for_vessel), args, /datum/prompt/choice, question = "Select a threat band", title = "Flight Operations", choices = threat_bands)
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
		spent(mission, user)
		to_chat(user, span_warning("Flight Operations could not survey a viable destination."))
		return null
	rel_set(site, nameof(site.assigned_flight_vessel), vessel)
	rel_set(site, nameof(site.payout_turf), get_turf(payout_source))
	rel_set(vessel, nameof(vessel.active_expedition), site)
	to_chat(user, span_notice("[site.name] has been surveyed. Select it in Flight Operations to begin the jump and generate its landing zone."))
	return site

/datum/system/expedition/proc/abandon_assignment(mob/user, datum/flight_vessel/vessel)
	var/datum/expedition_site/site = vessel?.active_expedition()
	if(!site || QDELETED(site))
		return FALSE
	var/datum/flight_destination/destination = SSflight?.destinations[site.flight_destination_id]
	if(LAZYLEN(destination?.active_plans))
		to_chat(user, span_warning("The assignment cannot be abandoned while a flight plan is using it."))
		return FALSE
	if(site.z_level > 0 && players_on_z(site.z_level))
		to_chat(user, span_warning("The assignment cannot be abandoned while crew remain at the site."))
		return FALSE
	rel_clear(vessel, nameof(vessel.active_expedition))
	if(site.z_level > 0 && sites?["[site.z_level]"] == site)
		release_site(site, "assignment abandoned")
	else
		if(site.flight_destination_id)
			SSflight?.unregister_destination(site.flight_destination_id)
		spent(site, user)
	to_chat(user, span_notice("The expedition assignment has been abandoned."))
	return TRUE

/datum/system/expedition/proc/create_site_descriptor(datum/expedition_mission/mission, difficulty = EXP_DIFF_LOW, datum/shuttle/autodock/overmap/assigned_shuttle = null, obj/machinery/computer/shuttle_control/explore/origin_console = null, parent_destination_id = null)
	if(mission)
		difficulty = mission.difficulty
	var/datum/expedition_site/site = new(0, difficulty)
	site.name = "Site [pick("Theta", "Sigma", "Kappa", "Vega", "Orion", "Lyra", "Cygnus", "Draco")]-[rand(1, 99)]"
	site.faction = mission?.faction_type || expedition_pick_faction(difficulty)
	site.name += " — [expedition_faction_name(site.faction)]"
	rel_set(site, nameof(site.mission), mission)
	rel_set(site, nameof(site.assigned_shuttle), assigned_shuttle)
	rel_set(site, nameof(site.origin_console), origin_console)
	site.parent_destination_id = parent_destination_id
	rel_set(site, nameof(site.payout_turf), get_turf(origin_console))
	var/datum/flight_vessel/assigned_vessel = SSflight?.vessel_for_ship(assigned_shuttle?.myship())
	rel_set(site, nameof(site.assigned_flight_vessel), assigned_vessel)
	if(assigned_vessel)
		rel_set(assigned_vessel, nameof(assigned_vessel.active_expedition), site)
	site.status = EXP_STATUS_GENERATING
	rel_add(src, nameof(descriptors), site)
	SSflight?.register_expedition(site)
	return site

// Generate a site, optionally bound to a mission. Returns the site (or null).
/datum/system/expedition/proc/generate_site(datum/expedition_mission/mission = null, difficulty = EXP_DIFF_LOW, datum/shuttle/autodock/overmap/assigned_shuttle = null, obj/machinery/computer/shuttle_control/explore/origin_console = null, datum/flight_plan/flight_plan = null)
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
		spent(planner)
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
		spent(materializer)
		if(station_materialization)
			generation_seed = attempt_seed
			break
		log_world("Expedition: generated-station materialization attempt [attempt] failed on z[z] (seed [attempt_seed]): [materialization_error || "no result"].")
		spent(station_spec)
		station_spec = null
		wipe_z(z)
	return publish_generated_site(mission, difficulty, assigned_shuttle, origin_console, flight_plan, z, gen_started, t_zalloc, generation_seed, station_spec, station_materialization, materialization_yields, materialization_elapsed)

/datum/system/expedition/proc/materialize_site(datum/expedition_site/site, datum/flight_plan/plan)
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

/datum/system/expedition/proc/release_site(datum/expedition_site/site, reason = "unspecified")
	if(!istype(site))
		return
	var/z = site.z_level
	site.status = EXP_STATUS_EXPIRED
	// The teardown job owns the site (own_move in its New()) until the wipe finishes.
	own_take_member(src, nameof(sites), "[z]")
	if(site.flight_destination_id)
		SSflight?.unregister_destination(site.flight_destination_id)
	if(site.origin_console() && site.origin_console().active_expedition() == site)
		rel_clear(site.origin_console(), nameof(/datum/flight_vessel::active_expedition))
	if(site.assigned_flight_vessel()?.active_expedition() == site)
		rel_clear(site.assigned_flight_vessel(), nameof(/datum/flight_vessel::active_expedition))
	own_clear(site, nameof(site.landing_waypoint), OWN_DELETE)
	own_clear(site, nameof(site.overmap_sector), OWN_DELETE)
	// Every relation view naming a turf on this z (payout turfs, landing turfs, rich edges) is
	// cleared now, and again when the wiped z goes back into free_z (finish()).
	var/dropped = relation_drop_z(z)
	log_world("Expedition: relation_drop_z(z[z]) cleared [dropped] relation view(s) before teardown.")
	teardown_z["[z]"] = TRUE
	var/datum/expedition_teardown_job/job = new(site, reason)
	job.execute()
