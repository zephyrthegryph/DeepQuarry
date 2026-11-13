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

/// How long the slow sections (the native walk, the attribution table, the longer windows, the collector, the counts) are kept before they are
/// built again. The fast ones (the header, the 5 s window, the recent ticks) are built on every send (about once a second).
#define MC_HEALTH_SLOW_EVERY (5 SECONDS)

/// The whole payload of the panel, by section. A section that did not change since a client last got it is the same list object, so the sender
/// (statpanel_service.dm) skips it without encoding it.
/proc/mc_health_data()
	return mc_health_fast() + mc_health_slow()

/// The sections built on every send: cheap, and changing every tick.
/proc/mc_health_fast()
	var/list/history = Kernel.perf_tick_usage
	return list(
		"header" = list(
			"tick_budget_ms" = world.tick_lag * 100,
			"target_tps" = world.fps,
			"current_usage" = history.len ? history[history.len] : 0,
			"maptick" = MAPTICK_LAST_INTERNAL_TICK_USAGE,
			"tidi" = time_track_time_dilation_current(),
		),
		"window_5s" = Kernel.performance_window(5),
		"ticks" = mc_health_recent_ticks(),
		"stalls" = km_meter().stalls || list(),
	)

/// The slow sections, in the groups that are rebuilt together. After the first send, at most one group is rebuilt per send (the stalest one past
/// MC_HEALTH_SLOW_EVERY), so their cost is spread over the seconds instead of landing in one.
GLOBAL_LIST_INIT(mc_health_slow_groups, list("ticks_long", "attribution_top", "counts", "attribution_rest", "rust"))

/// The sections kept for MC_HEALTH_SLOW_EVERY: the same list objects until their group is built again.
/proc/mc_health_slow()
	var/datum/system/statpanels/S = SSstatpanels
	var/now = TIME_NOW(CLOCK_WORLD)
	if(!S.mc_slow)
		S.mc_slow = list()
		S.mc_slow_built_at = list()
	// A group never built is built at once (the panel's first send is whole); after that, the stalest due group only.
	var/list/due = list()
	var/stalest
	for(var/group in GLOB.mc_health_slow_groups)
		var/at = S.mc_slow_built_at[group]
		if(isnull(at))
			due += group
		else if(now - at >= MC_HEALTH_SLOW_EVERY && (!stalest || at < S.mc_slow_built_at[stalest]))
			stalest = group
	if(!length(due) && stalest)
		due += stalest
	for(var/group in due)
		S.mc_slow_built_at[group] = now
		var/list/built = mc_health_slow_group(group)
		for(var/section in built)
			S.mc_slow[section] = built[section]
	return S.mc_slow

/// The sections of one slow group, built now.
/proc/mc_health_slow_group(group)
	switch(group)
		if("ticks_long")
			return list(
				"window_30s" = Kernel.performance_window(30),
				"window_5m" = Kernel.performance_window(300),
				"outliers" = Kernel.perf_outliers.Copy(),
				"subsystems" = mc_health_subsystems(),
				"kernel" = km_panel_data(),
				"ledger" = GLOB.km_ledger.report(KM_LEDGER_TOP),
				"runtime" = list(
					"cpu" = world.cpu,
					"clients" = length(GLOB.clients),
					"tick_drift" = Kernel.tickdrift,
					"kernel_ticks" = kernel().ticks,
					"kernel_last_tick_ms" = kernel().last_tick_ms,
				),
			)
		// The callbacks behind the panel's top 8 systems, as two groups of four: the costliest group, split over two sends.
		if("attribution_top")
			var/list/systems = km_panel_data(4)["systems"]
			return list("attribution" = mc_health_attribution(systems))
		if("attribution_rest")
			var/list/systems = km_panel_data(8)["systems"]
			return list("attribution_rest" = mc_health_attribution(systems.Copy(min(length(systems), 4) + 1)))
		if("counts")
			return list("gc" = mc_health_gc(), "entities" = mc_health_entities(), "churn" = mc_health_churn())
		if("rust")
			return list("rust" = mc_health_rust())
	return list()

/// The last MC_HEALTH_TICKS ticks of the flight recorder: list(usage, list(top keys), list(top ms), pre-kernel usage, map send usage) each, oldest first. Reads only those entries of
/// the ring (recorded_entries() copies all of it).
/proc/mc_health_recent_ticks()
	var/datum/tick_meter/meter = km_meter()
	var/datum/km_systems/registry = km_systems()
	. = list()
	for(var/n in max(1, meter.ring_count - MC_HEALTH_TICKS + 1) to meter.ring_count)
		var/at = meter.ring_index(n)
		var/list/keys = list()
		var/list/mss = list()
		var/base = (at - 1) * KM_TOP_N
		for(var/k in 1 to KM_TOP_N)
			var/idx = meter.fr_top_sys[base + k]
			if(!idx)
				continue
			keys += registry.keys[idx]
			mss += round(meter.fr_top_ms[base + k], 0.01)
		. += list(list(round(meter.fr_usage[at], 0.1), keys, mss, round(meter.fr_pre[at], 0.1), round(meter.fr_maptick[at], 0.1)))

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
	var/list/wanted = list()
	for(var/list/S as anything in systems)
		var/sys = registry.index_by_key?[S["key"]]
		if(sys)
			wanted["[sys]"] = S["key"]
	var/list/best = attr.select_top_by_system(per_system, wanted)
	for(var/sys_key in best)
		var/list/rows = list()
		for(var/list/row as anything in best[sys_key])
			var/list/data = attr.row_data(row)
			rows += list(list(data["source"], data["kind"], data["count"], data["total_ms"], data["max_ms"]))
		if(length(rows))
			.[wanted[sys_key]] = rows

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

#undef MC_HEALTH_SLOW_EVERY
#undef MC_HEALTH_CENSUS_EVERY
#undef MC_HEALTH_TICKS
#undef MC_HEALTH_CHURN_TOP
