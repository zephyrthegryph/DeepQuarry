/// OM profiling panel (completion_plan sec 3.6, K2): per-behaviour and per-lane cost
/// from the scheduler's own counters (run_slot() measures TICK_USAGE per slot and
/// behaviour; profiled pipeline frames time each stage). Opened by the admin verb
/// "OM Profiler" (Debug); tgui interface OmProfiler.tsx.

/datum/controller/subsystem/behaviours
	/// world.time the profiler counters were last cleared (0: since boot).
	EXPIRY_DECLARE(profile_reset_time)

DECLARE_UI_STATE(/datum/controller/subsystem/behaviours, ADMIN_STATE(R_DEBUG))

DECLARE_UI(/datum/controller/subsystem/behaviours, "OmProfiler", UI_TITLE("Object Model Profiler"))

UI_DATA_REPLACE(/datum/controller/subsystem/behaviours, "merge:ui_data_datum_controller_subsystem_behaviours{elapsed_s:num,last_run_ms:num,error_count:num,behind:bool,behaviours:list,shared_bucket:bool,lanes:list,stages:list,services:list,caches:unknown,world_step:list}")

/// The computed part of /datum/controller/subsystem/behaviours's window data (declared on its UI_DATA row).
/datum/controller/subsystem/behaviours/proc/ui_data_datum_controller_subsystem_behaviours(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	var/datum/om/scheduler/sched = GLOB.om_live_sched
	var/datum/om/registry/reg = om_registry()
	var/static/list/lane_names = list("Urgent", "Simulation", "Derived", "Presentation", "Background")
	var/elapsed = max(world.time - profile_reset_time, 1) / (1 SECONDS)
	data["elapsed_s"] = round(elapsed, 0.1)
	data["last_run_ms"] = sched ? round(sched.last_run_ms, 0.001) : 0
	data["error_count"] = sched ? length(sched.errors) : 0
	data["behind"] = !last_done
	var/list/behaviours = list()
	var/list/lane_ms = new /list(OM_LANE_COUNT)
	var/list/lane_runs = new /list(OM_LANE_COUNT)
	var/list/lane_count = new /list(OM_LANE_COUNT)
	for(var/i in 1 to OM_LANE_COUNT)
		lane_ms[i] = 0
		lane_runs[i] = 0
		lane_count[i] = 0
	var/shared_bucket = FALSE
	if(sched && reg)
		for(var/datum/om/behaviour/B as anything in reg.behaviours)
			if(!B?.id)
				continue
			if(B.id >= OM_MAX_STAT_TYPES)
				shared_bucket = TRUE
			var/list/S = (length(sched.stats) >= min(B.id, OM_MAX_STAT_TYPES)) ? sched.stats[min(B.id, OM_MAX_STAT_TYPES)] : null
			var/ms = S ? S[OM_STAT_MS] : 0
			var/runs = S ? S[OM_STAT_RUNS] : 0
			var/lane = clamp(B.lane || LANE_SIMULATION, 1, OM_LANE_COUNT)
			var/population = 0
			if(B.id <= length(sched.rings))
				for(var/datum/om/ring/R as anything in sched.rings[B.id])
					population += R.population()
			var/parked = 0
			if(istype(B, /datum/om/pipeline))
				var/datum/om/pipeline/P = B
				parked = length(P.parked_on(sched))
			lane_ms[lane] += ms
			lane_runs[lane] += runs
			lane_count[lane] += 1
			behaviours += list(list(
				"name" = B.name || "[B.type]",
				"type" = "[B.type]",
				"lane" = lane_names[lane],
				"runs" = runs,
				"ms" = round(ms, 0.001),
				"ms_per_s" = round(ms / elapsed, 0.001),
				"us_per_run" = runs ? round(ms * 1000 / runs, 0.01) : 0,
				"call_max_ms" = S ? round(S[OM_STAT_CALL_MAX], 0.001) : 0,
				"late_max" = S ? S[OM_STAT_LATE_MAX] : 0,
				"deferrals" = S ? S[OM_STAT_DEFERRALS] : 0,
				"breaches" = S ? S[OM_STAT_BREACHES] : 0,
				"errors" = S ? S[OM_STAT_ERRORS] : 0,
				"wakes" = S ? S[OM_STAT_WAKES] : 0,
				"parks" = S ? S[OM_STAT_PARKS] : 0,
				"population" = population,
				"parked" = parked,
			))
	data["behaviours"] = behaviours
	data["shared_bucket"] = shared_bucket
	var/list/world_diag = sched ? om_world_diagnostics(sched) : null
	var/list/world_queued = world_diag?["queued"]
	var/list/lanes = list()
	for(var/i in 1 to OM_LANE_COUNT)
		lanes += list(list(
			"name" = lane_names[i],
			"share" = sched ? sched.lane_share[i] : 0,
			"behaviours" = lane_count[i],
			"runs" = lane_runs[i],
			"ms" = round(lane_ms[i], 0.001),
			"ms_per_s" = round(lane_ms[i] / elapsed, 0.001),
			"wake_queue" = sched ? length(sched.wake_q?[i]) : 0,
			"world_queue" = world_queued ? world_queued[i] : 0,
		))
	data["lanes"] = lanes
	var/list/stages = list()
	if(sched)
		for(var/key in sched.stage_cost)
			var/calls = sched.stage_calls[key] || 0
			var/cost = sched.stage_cost[key]
			stages += list(list(
				"key" = key,
				"calls" = calls,
				"ms" = round(cost, 0.001),
				"us_per_call" = calls ? round(cost * 1000 / calls, 0.01) : 0,
			))
	data["stages"] = stages
	// World services: the global state and world-level periodic work former subsystems held.
	var/datum/om/global_owner/owner = om_global_owner()
	var/list/services = list()
	for(var/datum/world_service/WS as anything in world_services())
		if(!WS)
			continue
		var/lane_parked = FALSE
		if(WS.lane && owner?.om_rec)
			var/i = owner.om_rec.att.Find(om_registry().behaviour(WS.lane))
			lane_parked = i ? !!(owner.om_rec.att_state[i] & OM_ATT_PARKED) : FALSE
		services += list(list(
			"name" = WS.name,
			"type" = "[WS.type]",
			"initialized" = WS.initialized,
			"on_demand" = WS.on_demand,
			"parked" = lane_parked,
			"resuming" = WS.resuming,
			"steps" = WS.steps,
			"ms" = round(WS.total_ms, 0.001),
			"ms_per_s" = round(WS.total_ms / max(world.time / (1 SECONDS), 1), 0.001),
			"avg_ms" = round(WS.cost, 0.001),
			"status" = WS.stat_line(),
		))
	data["services"] = services
	data["caches"] = shared_cache_stats()
	if(world_diag)
		data["world_step"] = list(
			"step_ms" = round(world_diag["step_ms"], 0.001),
			"total_wakes" = world_diag["total_wakes"],
			"last_wakes" = world_diag["last_wakes"],
			"dropped" = world_diag["dropped"],
		)
	return data

/datum/controller/subsystem/behaviours/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	if(!user || !check_rights_for(user.client, R_DEBUG))
		return FALSE
	return TRUE

UI_ACT(/datum/controller/subsystem/behaviours, "reset", ui_act_reset)
UI_ACT_PROC(/datum/controller/subsystem/behaviours, ui_act_reset)
	var/datum/om/scheduler/sched = GLOB.om_live_sched
	if(sched)
		sched.stats = list()
		sched.stage_cost = list()
		sched.stage_calls = list()
	EXPIRY_STAMP(src, profile_reset_time, CLOCK_WORLD)
	log_admin("[key_name(user)] reset the OM profiler counters.")
	return TRUE

ADMIN_VERB(om_profiler, R_DEBUG, "OM Profiler", "Opens the object-model profiler: cost per behaviour, per lane and per pipeline stage.", ADMIN_CATEGORY_DEBUG_INVESTIGATE)
	SSbehaviours.tgui_interact(user.mob)
	feedback_add_details("admin_verb","OMPROF") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!
