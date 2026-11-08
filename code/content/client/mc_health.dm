// The data of the MC Health panel (tgui-panel/statpanel/McHealth.tsx; the Health page of the stat panel's Server view). Built only while an
// admin has the panel open (statpanel_service.dm sends it to a client whose stat_tab is "MC"), at most once a second, from numbers the
// kernel, the garbage collector, the registries and the Rust metrics already keep. The few new readings: the entity census below (every
// MC_HEALTH_CENSUS_EVERY), the Rust process memory and frame histogram (verdigris/ffi/src/frame.rs) and a churn read that leaves the
// metrics source's window alone (/datum/churn_census/proc/peek()).

/// How long one census of objects, turfs and areas is used before it is taken again.
#define MC_HEALTH_CENSUS_EVERY (1 MINUTES)
/// The recorded ticks the panel draws.
#define MC_HEALTH_TICKS 120
/// The busiest keys of each churn kind the panel lists.
#define MC_HEALTH_CHURN_TOP 5

/// The Rust metric families the panel reads, in one call that refreshes the sampled gauges first (verdigris_metrics_panel(), about once a
/// second while the panel is open; it does not wait for the server metrics source, which may be off).
GLOBAL_LIST_INIT(mc_health_rust_families, list("sim.", "frame.", "ffi.calls_total", "ffi.errors_total", "jobs.pending", "alloc.", "process.", "world.awake.", "world.stepped."))

/// The whole payload of the panel.
/proc/mc_health_data()
	var/list/history = Kernel.perf_tick_usage
	var/list/kernel_data = km_panel_data()
	var/list/systems = kernel_data["systems"]
	var/list/shown_systems = systems.Copy(1, min(length(systems), 8) + 1) // the panel's top 8 expand
	return list(
		"tick_budget_ms" = world.tick_lag * 100,
		"target_tps" = world.fps,
		"current_usage" = history.len ? history[history.len] : 0,
		"maptick" = MAPTICK_LAST_INTERNAL_TICK_USAGE,
		"tidi" = time_track_time_dilation_current(),
		"tidi_fast" = time_track_time_dilation_avg_fast(),
		"tidi_medium" = time_track_time_dilation_avg(),
		"tidi_slow" = time_track_time_dilation_avg_slow(),
		"window_5s" = Kernel.performance_window(5),
		"window_30s" = Kernel.performance_window(30),
		"window_5m" = Kernel.performance_window(300),
		"ticks" = mc_health_recent_ticks(),
		"outliers" = Kernel.perf_outliers.Copy(),
		"subsystems" = mc_health_subsystems(),
		"kernel" = kernel_data,
		"attribution" = mc_health_attribution(shown_systems),
		"gc" = mc_health_gc(),
		"entities" = mc_health_entities(),
		"churn" = mc_health_churn(),
		"rust" = mc_health_rust(),
		"runtime" = list(
			"cpu" = world.cpu,
			"clients" = length(GLOB.clients),
			"tick_drift" = Kernel.tickdrift,
			"kernel_ticks" = kernel().ticks,
			"kernel_last_tick_ms" = kernel().last_tick_ms,
		),
	)

/// The last MC_HEALTH_TICKS ticks of the flight recorder: list(usage, list(top keys), list(top ms)) each, oldest first.
/proc/mc_health_recent_ticks()
	var/list/entries = km_meter().recorded_entries()
	var/first = max(1, length(entries) - MC_HEALTH_TICKS + 1)
	. = list()
	for(var/i in first to length(entries))
		var/list/entry = entries[i]
		var/list/mss = list()
		for(var/ms in entry[8])
			mss += round(ms, 0.01)
		. += list(list(round(entry[3], 0.1), entry[7], mss))

/// The hosted systems with periodic work: their cost per fire and that cost as a share of one tick ("usage", % of the tick budget).
/proc/mc_health_subsystems()
	. = list()
	var/budget_ms = world.tick_lag * 100
	for(var/datum/system/S as anything in kernel_pure_systems())
		if(!S.times_fired && !S.fire_cost)
			continue
		. += list(list(
			"name" = S.name,
			"usage" = budget_ms ? round(S.fire_cost / budget_ms * 100, 0.01) : 0,
			"overrun" = S.tick_overrun,
			"cost" = S.fire_cost,
			"fires" = S.times_fired,
			"ref" = handle_of(S),
		))

/// The garbage collector, as numbers the panel says in words.
/proc/mc_health_gc()
	var/datum/system/garbage/G = SSgarbage
	if(!G)
		return null
	var/list/queued = list()
	for(var/list/queue as anything in G.queues)
		queued += length(queue)
	return list(
		"queued" = queued,
		"deleted_cleanly" = G.totalgcs,
		"forced" = G.totaldels,
		"leaks" = G.total_leaks,
	)

/// Players and the registries every tick keeps, plus the census of objects, turfs and areas (taken at most every MC_HEALTH_CENSUS_EVERY), with
/// the previous census so the panel shows growth.
/proc/mc_health_entities()
	var/list/census = mc_health_census()
	return list(
		"players" = length(GLOB.clients),
		"mobs" = REGISTRY_COUNT(REGISTRY_MOBS),
		"living" = REGISTRY_COUNT(REGISTRY_LIVING_MOBS),
		"humans" = REGISTRY_COUNT(REGISTRY_HUMANS),
		"machines" = REGISTRY_COUNT(REGISTRY_MACHINES),
		"census" = census[1],
		"previous" = census[2],
	)

/// list(the latest census, the one before) of objects, turfs and areas, each list("objects", "turfs", "areas", "at" = now, "ms"). Turfs are
/// the map's size; areas a walk of the area atoms (a few hundred); objects what world.contents holds besides them and the mobs.
/proc/mc_health_census()
	var/static/list/latest
	var/static/list/previous
	var/now = TIME_NOW(CLOCK_WORLD)
	if(latest && now - latest["at"] < MC_HEALTH_CENSUS_EVERY)
		return list(latest, previous)
	var/started = TICK_USAGE_REAL
	var/turfs = world.maxx * world.maxy * world.maxz
	var/areas = 0
	for(var/area/A in world)
		areas++
	var/objects = max(0, length(world.contents) - turfs - areas - REGISTRY_COUNT(REGISTRY_MOBS))
	previous = latest
	latest = list("objects" = objects, "turfs" = turfs, "areas" = areas, "at" = now, "ms" = round(TICK_DELTA_TO_MS(TICK_USAGE_REAL - started), 0.01))
	return list(latest, previous)

/// The busiest MC_HEALTH_CHURN_TOP keys of each churn kind in the current window, read without ending the window (the metrics source owns it).
/proc/mc_health_churn()
	. = list()
	var/list/kinds = GLOB.churn_census.peek()
	for(var/kind in kinds)
		var/list/counts = kinds[kind]
		var/list/top = list()
		for(var/key in counts)
			var/n = counts[key]
			var/at = length(top) + 1
			for(var/i in 1 to length(top))
				if(n > top[i][2])
					at = i
					break
			if(at <= MC_HEALTH_CHURN_TOP)
				top.Insert(at, list(list("[key]", n)))
				if(length(top) > MC_HEALTH_CHURN_TOP)
					top.len = MC_HEALTH_CHURN_TOP
		.[kind] = top

/// The Rust metrics of the families the panel reads, flat (name -> number; a histogram as its list), or null when the library did not answer.
/proc/mc_health_rust()
	var/list/out = verdigris_metrics_panel(GLOB.mc_health_rust_families)
	return length(out) ? out : null

/// The callbacks and redraws behind each of the busiest systems (the attribution table, code/world/kernel/measure/attribution.dm): system key ->
/// list of list(source, kind, count, total ms, max ms), heaviest first. What a row of the panel's system table expands into.
/proc/mc_health_attribution(list/systems, per_system = 5)
	. = list()
	var/datum/km_attr/attr = km_meter().attr
	var/datum/km_systems/registry = km_systems()
	if(!attr)
		return
	for(var/list/S as anything in systems)
		var/sys = registry.index_by_key?[S["key"]]
		if(!sys)
			continue
		var/list/rows = list()
		for(var/list/row as anything in attr.select_top(per_system, KA_BY_TOTAL, sys))
			var/list/data = attr.row_data(row)
			rows += list(list(data["source"], data["kind"], data["count"], data["total_ms"], data["max_ms"]))
		if(length(rows))
			.[S["key"]] = rows

// ---- the Advanced section's links: View Variables of a controller named by the link, not by a ref (the server resolves the name) ----

CAPABILITIES_PART(/datum/admins, mc_health)
	op("mc_vv", topic("mc_vv", arg("mc_vv", schema_text(16))), needs(req_rights(R_DEBUG)), then(PROC_REF(topic_mc_vv)))

/// The datum a MC Health link names: "kernel", "globals" or "config"; null for any other name.
/proc/mc_health_vv_target(name)
	switch(name)
		if("kernel")
			return Kernel
		if("globals")
			return GLOB
		if("config")
			return config
	return null

/// "View Kernel vars" and its siblings: View Variables of the named controller for the admin who clicked.
/datum/admins/proc/topic_mc_vv(datum/act/op/A, href_mc_vv)
	var/datum/target = mc_health_vv_target(href_mc_vv)
	if(!target)
		log_admin("[key_name(A.actor)] asked the MC Health panel for View Variables of an unknown name '[href_mc_vv]'.")
		return
	owner()?.debug_variables(target)

#undef MC_HEALTH_CENSUS_EVERY
#undef MC_HEALTH_TICKS
#undef MC_HEALTH_CHURN_TOP
