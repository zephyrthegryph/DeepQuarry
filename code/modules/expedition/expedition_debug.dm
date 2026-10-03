// Debug entry points for the expedition system. The production flow is the
// launch console (auto-placed by SSexpedition); these verbs let an admin jump a
// site directly for testing the generator + missions.

/// Builds a generated station on an expedition-owned z-level. Registering the
/// result as a site gives the ordinary expedition lifecycle sole ownership of
/// the z-level, materialized areas, and entry landmark.
/datum/system/expedition/proc/generate_debug_station(seed, list/validation_messages)
	seed = round(seed)
	var/datum/generated_station_planner/planner = new
	var/datum/generated_station_spec/spec = planner.plan(seed, 160, 160)
	var/datum/generated_station_validation_result/validation = spec?.validate()
	if(!spec || !validation?.is_valid())
		if(validation_messages)
			if(!spec)
				var/error_suffix = planner.error_message ? ": [planner.error_message]" : "."
				validation_messages += "The planner returned no station specification[error_suffix]"
			else
				for(var/datum/generated_station_validation_issue/issue in validation.issues)
					validation_messages += "[issue.severity == GENERATED_STATION_ISSUE_ERROR ? "error" : "warning"] [issue.code][issue.subject_id ? " ([issue.subject_id])" : ""]: [issue.message]"
		if(!spec)
			spec = generated_station_emergency_spec(seed)
	qdel(validation)

	var/z = acquire_z()
	if(!isnum(z) || z < 1)
		if(validation_messages)
			validation_messages += "No expedition z-level was available."
		qdel(spec)
		qdel(planner)
		return null
	var/origin_x = max(1, round((world.maxx - spec.grid_width) / 2))
	var/origin_y = max(1, round((world.maxy - spec.grid_height) / 2))
	var/datum/generated_station_materialization/materialization
	var/materialization_failure
	if(spec.size_class == "emergency")
		materialization = generated_station_emergency_materialization(spec, z)
	else
		var/datum/generated_station_materializer/materializer = new
		// This verb exercises the live publication policy. Quality defects are
		// returned as degradation diagnostics, not as a discarded playable map.
		materializer.strict_room_contracts = FALSE
		materialization = materializer.materialize(spec, z, origin_x, origin_y)
		materialization_failure = materializer.last_failure_details
		qdel(materializer)
	qdel(planner)
	if(!materialization?.entry())
		if(validation_messages)
			validation_messages += materialization ? "The materialized station has no docking entry." : "Station materialization failed[materialization_failure ? ": [materialization_failure]" : "."]"
		qdel(materialization)
		wipe_z(z)
		qdel(spec)
		spec = generated_station_emergency_spec(seed)
		materialization = generated_station_emergency_materialization(spec, z)

	var/datum/expedition_site/site = new(z, EXP_DIFF_LOW, get_turf(materialization.entry()))
	site.name = spec.name
	site.generation_seed = seed
	own_set(site, nameof(site.station_spec), spec)
	own_set(site, nameof(site.station_materialization), materialization)
	if(!site.initialize_generated_station_utilities())
		materialization.degradation_events += "utility initialization failed"
	if(!site.initialize_generated_station_runtime())
		materialization.degradation_events += "strategic runtime initialization failed"
	if(site.station_director && !site.initialize_generated_station_infrastructure())
		materialization.degradation_events += "strategic infrastructure initialization failed"
	if(!site.repair_generated_station_runtime_access())
		materialization.degradation_events += "post-utility access repair was incomplete"
	if(site.station_director && !site.initialize_generated_station_defenders())
		materialization.degradation_events += "defender initialization failed"
	site.floors = scan_floors(z)
	site.status = EXP_STATUS_ACTIVE
	EXPIRY_STAMP(site, deployed_at, CLOCK_WORLD)
	EXPIRY_STAMP(site, last_occupied, CLOCK_WORLD)
	own_put(src, nameof(sites), "[z]", site)
	demand()
	return site

ADMIN_VERB(generate_procedural_station, R_DEBUG, "Generate Procedural Station", "Generate a station on an expedition z-level and move to its docking entry.", ADMIN_CATEGORY_DEBUG_GAME)
	var/seed_text = verb_ask(user, "seed", args, /datum/om/prompt/text, message = "Enter a numeric seed, or leave blank for a random seed.", title = "Generated Station", max_length = 20)
	if(isnull(seed_text))
		return
	var/seed = length(seed_text) ? text2num(seed_text) : rand(1, 2147483646)
	if(!isnum(seed) || seed <= 0)
		to_chat(user, span_warning("The station seed must be a positive number."))
		return
	seed = max(1, round(seed) % 2147483647)
	var/list/validation_messages = list()
	var/datum/expedition_site/site = SSexpedition.generate_debug_station(seed, validation_messages)
	if(!site)
		to_chat(user, span_warning("Generated station [seed] failed: [length(validation_messages) ? jointext(validation_messages, "; ") : "no diagnostic was returned"]."))
		return
	if(user.mob)
		user.mob.forceMove(site.landing())
	to_chat(user, span_notice("Generated station seed [seed] on z[site.z_level]; moved you to its docking entry. The expedition lifecycle will recycle it after it is vacated."))

ADMIN_VERB(generate_expedition_site, R_DEBUG, "Generate Expedition Site", "Generate an expedition site and move to its landing point.", ADMIN_CATEGORY_DEBUG_GAME)
	var/datum/expedition_site/site = SSexpedition.generate_site()
	if(!site || !site.landing())
		to_chat(user, span_warning("Expedition site generation failed (see world log)."))
		return

	if(user.mob)
		user.mob.forceMove(site.landing())
	to_chat(user, span_notice("Generated [site.name] on z[site.z_level]; moved you to its landing point."))

// Roll a chosen mission, generate its site, and drop the admin on the landing
// pad to play it through.
ADMIN_VERB(generate_expedition_mission, R_DEBUG, "Generate Expedition Mission", "Roll a chosen expedition mission, generate its site and move to the landing point.", ADMIN_CATEGORY_DEBUG_GAME)
	var/list/mission_types = GLOB.expedition_mission_types
	// Answers re-run this verb.
	var/mission_type = verb_ask(user, "mission", args, /datum/om/prompt/choice, message = "Mission type?", title = "Expedition Mission", choices = mission_types)
	if(!mission_type)
		return
	var/diff = verb_ask(user, "difficulty", args, /datum/om/prompt/choice, message = "Difficulty?", title = "Expedition Mission", choices = list(EXP_DIFF_LOW, EXP_DIFF_MED, EXP_DIFF_HIGH))
	if(isnull(diff))
		return

	var/datum/expedition_mission/mission = new mission_type(diff)
	var/datum/expedition_site/site = SSexpedition.generate_site(mission)
	if(!site || !site.landing())
		to_chat(user, span_warning("Expedition mission generation failed (see world log)."))
		return

	if(user.mob)
		user.mob.forceMove(site.landing())
	to_chat(user, span_notice("Generated mission '[mission.name]' on [site.name] (z[site.z_level]). Objective: [mission.objective_text()]"))
