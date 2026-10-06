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
	spent(validation)

	var/z = acquire_z()
	if(!isnum(z) || z < 1)
		if(validation_messages)
			validation_messages += "No expedition z-level was available."
		spent(spec)
		spent(planner)
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
		spent(materializer)
	spent(planner)
	if(!materialization?.entry())
		if(validation_messages)
			validation_messages += materialization ? "The materialized station has no docking entry." : "Station materialization failed[materialization_failure ? ": [materialization_failure]" : "."]"
		spent(materialization)
		wipe_z(z)
		spent(spec)
		spec = generated_station_emergency_spec(seed)
		materialization = generated_station_emergency_materialization(spec, z)

	var/datum/expedition_site/site = new(z, EXP_DIFF_LOW, get_turf(materialization.entry()))
	site.name = spec.name
	site.generation_seed = seed
	rel_set(site, nameof(site.station_spec), spec)
	rel_set(site, nameof(site.station_materialization), materialization)
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
	rel_add(src, nameof(sites), site, "[z]")
	demand()
	return site

ADMIN_VERB(generate_procedural_station, R_DEBUG, "Generate Procedural Station", "Generate a station on an expedition z-level and move to its docking entry.", ADMIN_CATEGORY_DEBUG_GAME)
	var/list/replay_answers = list()
	if(length(args) >= 2)
		var/datum/request/resumed = args[2]
		if(istype(resumed, /datum/prompt/text/expedition_debug_seed) && resumed.owner == src && resumed.answerer == user.mob && resumed.outcome == REQ_ANSWERED && !resumed.is_open() && !QDELETED(resumed) && resumed.handler == PROC_REF(expedition_seed_answered))
			replay_answers = resumed.captured.Copy()
			replay_answers[resumed.step_name] = resumed.value
	if(!("seed" in replay_answers))
		open_request(src, /datum/prompt/text/expedition_debug_seed, PROC_REF(expedition_seed_answered), answerer = user.mob, captured = replay_answers.Copy(), step_name = "seed", question = "Enter a numeric seed, or leave blank for a random seed.", title = "Generated Station", max_len = 20, name_text = TRUE)
		return
	var/seed_text = replay_answers["seed"]
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
	var/list/replay_answers = list()
	if(length(args) >= 2)
		var/datum/request/resumed = args[2]
		if(istype(resumed, /datum/prompt/choice/expedition_debug_mission) && resumed.owner == src && resumed.answerer == user.mob && resumed.outcome == REQ_ANSWERED && !resumed.is_open() && !QDELETED(resumed) && resumed.handler == PROC_REF(expedition_mission_answered))
			replay_answers = resumed.captured.Copy()
			replay_answers[resumed.step_name] = resumed.value
	var/list/mission_types = GLOB.expedition_mission_types
	if(!("mission" in replay_answers))
		open_request(src, /datum/prompt/choice/expedition_debug_mission, PROC_REF(expedition_mission_answered), answerer = user.mob, captured = replay_answers.Copy(), step_name = "mission", question = "Mission type?", title = "Expedition Mission", choices = mission_types)
		return
	var/mission_type = replay_answers["mission"]
	if(!mission_type)
		return
	if(!("difficulty" in replay_answers))
		open_request(src, /datum/prompt/choice/expedition_debug_mission, PROC_REF(expedition_mission_answered), answerer = user.mob, captured = replay_answers.Copy(), step_name = "difficulty", question = "Difficulty?", title = "Expedition Mission", choices = list(EXP_DIFF_LOW, EXP_DIFF_MED, EXP_DIFF_HIGH))
		return
	var/diff = replay_answers["difficulty"]
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

/datum/prompt/text/expedition_debug_seed
	timeout = 0
	rights = R_DEBUG
	recheck_on_open = TRUE

/datum/prompt/text/expedition_debug_seed/recheck_extra()
	if(!owner || QDELETED(owner) || !answerer || QDELETED(answerer))
		return "gone"
	return admin_can(answerer.client, 0) ? null : "no admin rights"

/datum/prompt/text/expedition_debug_seed/normalize(given)
	return istext(given) ? strip_name_tokens(given) : given

/datum/prompt/text/expedition_debug_seed/refusal(given)
	return null

/datum/admin_verb/generate_procedural_station/proc/expedition_seed_answered(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/actor = A.request.answerer
	var/client/user = actor?.client
	if(!user)
		return
	world.push_usr(actor, new /datum/callback(SSadmin_verbs, TYPE_PROC_REF(/datum/system/admin_verbs, dynamic_invoke_verb)), user, src.type, A.answer)

/datum/prompt/choice/expedition_debug_mission
	timeout = 0
	rights = R_DEBUG
	recheck_on_open = TRUE

/datum/prompt/choice/expedition_debug_mission/recheck_extra()
	if(!owner || QDELETED(owner) || !answerer || QDELETED(answerer))
		return "gone"
	return admin_can(answerer.client, 0) ? null : "no admin rights"

/datum/prompt/choice/expedition_debug_mission/normalize(given)
	return given

/datum/prompt/choice/expedition_debug_mission/refusal(given)
	return null

/datum/admin_verb/generate_expedition_mission/proc/expedition_mission_answered(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/actor = A.request.answerer
	var/client/user = actor?.client
	if(!user)
		return
	world.push_usr(actor, new /datum/callback(SSadmin_verbs, TYPE_PROC_REF(/datum/system/admin_verbs, dynamic_invoke_verb)), user, src.type, A.answer)
