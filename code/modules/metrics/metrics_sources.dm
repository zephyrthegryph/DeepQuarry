// What the metrics service measures. Each concrete subtype is instantiated once and its
// collect() runs every sample (METRICS_SAMPLE_INTERVAL); it reports values with
// M.gauge(name, value, category, subcategory, unit). Names are "category/subcategory/what",
// and category/subcategory are what the admin viewer breaks performance down by.
// To measure something new, add a subtype here (or next to the feature it measures).

/datum/metrics_source
	abstract_type = /datum/metrics_source
	/// rate()'s memory: the last total seen for each counter key.
	var/list/last_totals
	/// What collect() cost since the service last reported it, ms.
	var/cost_ms = 0
	/// The source's name in its own cost metric (metrics/source/<name>/ms), from its type.
	var/name

/// The name the service reports this source's cost under: the type's path after /datum/metrics_source/.
/datum/metrics_source/proc/metric_name()
	if(!name)
		name = replacetext("[type]", "/datum/metrics_source/", "")
	return name

/// Reports this source's values for the sample. `dt` is the seconds since the last sample.
/datum/metrics_source/proc/collect(datum/system/server_metrics/M, dt)
	return

/// Rate of a cumulative counter: (total - last seen) / dt, remembering `total` under `key`.
/// Null on the first sight of a counter. A counter that went backwards (a profiler reset)
/// restarts from zero.
/datum/metrics_source/proc/rate(key, total, dt)
	var/previous = LAZYACCESS(last_totals, key)
	LAZYSET(last_totals, key, total)
	if(isnull(previous))
		return null
	var/delta = total - previous
	if(delta < 0)
		delta = total
	return delta / dt

// ---------------------------------------------------------------- server

/// Tick usage, CPU, MC drift and runtimes. (Time dilation is reported by its own service,
/// code/modules/logging/time_track_service.dm.)
/datum/metrics_source/server
	var/last_runtimes
	/// The first sample's window reaches back into MC init (seconds-long ticks), which would skew
	/// every round's tick statistics; tick usage is reported from the second sample on.
	var/first_sample = TRUE

/datum/metrics_source/server/collect(datum/system/server_metrics/M, dt)
	if(first_sample)
		first_sample = FALSE
	else if(Kernel)
		var/list/window = Kernel.performance_window(dt)
		M.gauge("server/tick/avg", window["avg"], METRICS_CAT_SERVER, "tick", "%")
		M.gauge("server/tick/p95", window["p95"], METRICS_CAT_SERVER, "tick", "%")
		M.gauge("server/tick/max", window["max"], METRICS_CAT_SERVER, "tick", "%")
		M.gauge("server/tick/tps", window["tps"], METRICS_CAT_SERVER, "tick", "tps")
		M.gauge("server/mc/tickdrift", Kernel.tickdrift, METRICS_CAT_SERVER, "mc", "ticks")
	M.gauge("server/cpu", world.cpu, METRICS_CAT_SERVER, "cpu", "%")
	M.gauge("server/map_cpu", world.map_cpu, METRICS_CAT_SERVER, "cpu", "%")
	var/runtimes = GLOB.total_runtimes + GLOB.total_runtimes_skipped
	M.gauge("errors/runtimes", isnull(last_runtimes) ? 0 : max(runtimes - last_runtimes, 0), METRICS_CAT_ERRORS, "runtime", "count")
	last_runtimes = runtimes

// ---------------------------------------------------------------- systems

/// Each system's work cost (ms per run, smoothed).
/datum/metrics_source/mc

/datum/metrics_source/mc/collect(datum/system/server_metrics/M, dt)
	for(var/datum/system/system as anything in kernel_pure_systems())
		if(!system.times_fired)
			continue
		M.gauge("mc/[system.name]/cost_ms", system.fire_cost, METRICS_CAT_MC, system.name, "ms")

// ---------------------------------------------------------------- systems

/// Each system's work cost (the kernel work items it owns), in ms per second of real time.
/datum/metrics_source/services

/datum/metrics_source/services/collect(datum/system/server_metrics/M, dt)
	for(var/datum/system/system as anything in kernel_pure_systems())
		var/list/cost = kernel().work_cost_of(system.type)
		var/ms_per_s = rate(system.name, cost["total_ms"], dt)
		if(!isnull(ms_per_s))
			M.gauge("service/[system.name]/ms_per_s", ms_per_s, METRICS_CAT_SERVICE, system.name, "ms/s")

// ---------------------------------------------------------------- OM lanes and behaviours

/// Each OM lane's cost and wake backlog, and each behaviour busy enough to matter
/// (METRICS_BEHAVIOUR_MIN_MS_PER_S), filed under its lane.
/datum/metrics_source/om
	/// Each behaviour's last OM_STAT_MS total, by behaviour id (a flat list: this runs over every behaviour
	/// each sample, so no string keys).
	var/list/last_behaviour_ms
	/// Each behaviour's metric name, by behaviour id, built once.
	var/list/behaviour_metric

/datum/metrics_source/om/collect(datum/system/server_metrics/M, dt)
	var/datum/time_scheduler/sched = GLOB.om_live_sched
	var/datum/definition_registry/reg = definition_registry()
	if(!sched || !reg)
		return
	var/static/list/lane_names = list("urgent", "simulation", "derived", "presentation", "background", "world")
	var/list/lane_ms = new /list(OM_LANE_COUNT)
	for(var/i in 1 to OM_LANE_COUNT)
		lane_ms[i] = 0
	var/list/stats = sched.stats
	var/stat_count = length(stats)
	if(length(last_behaviour_ms) < stat_count)
		LAZYINITLIST(last_behaviour_ms)
		LAZYINITLIST(behaviour_metric)
		last_behaviour_ms.len = stat_count
		behaviour_metric.len = stat_count
	for(var/datum/scheduled_behaviour/B as anything in reg.behaviours)
		var/id = B?.id
		if(!id || id > stat_count)
			continue
		var/list/S = stats[min(id, OM_MAX_STAT_TYPES)]
		if(!S)
			continue
		var/lane = clamp(B.lane || LANE_SIMULATION, 1, OM_LANE_COUNT)
		var/total = S[OM_STAT_MS]
		lane_ms[lane] += total
		var/previous = last_behaviour_ms[id]
		last_behaviour_ms[id] = total
		if(isnull(previous) || total == previous)
			continue
		var/ms_per_s = (total >= previous ? total - previous : total) / dt
		if(ms_per_s < METRICS_BEHAVIOUR_MIN_MS_PER_S)
			continue
		var/metric = behaviour_metric[id]
		if(!metric)
			metric = "behaviour/[B.name || B.type]/ms_per_s"
			behaviour_metric[id] = metric
		M.gauge(metric, ms_per_s, METRICS_CAT_BEHAVIOUR, lane_names[lane], "ms/s")
	for(var/i in 1 to OM_LANE_COUNT)
		var/ms_per_s = rate(lane_names[i], lane_ms[i], dt)
		if(!isnull(ms_per_s))
			M.gauge("lane/[lane_names[i]]/ms_per_s", ms_per_s, METRICS_CAT_LANE, lane_names[i], "ms/s")
		M.gauge("lane/[lane_names[i]]/backlog", length(sched.wake_q?[i]), METRICS_CAT_LANE, lane_names[i], "wakes")
	M.gauge("lane/errors", length(sched.errors), METRICS_CAT_LANE, "scheduler", "count")

// ---------------------------------------------------------------- players and staff

/// Connected players, staff on duty and open tickets.
/datum/metrics_source/players

/datum/metrics_source/players/collect(datum/system/server_metrics/M, dt)
	M.gauge("players/online", length(GLOB.clients), METRICS_CAT_PLAYERS, "online", "players")
	var/living = 0
	for(var/mob/living/L in GLOB.registry_members[REGISTRY_PLAYERS])
		if(L.client && L.stat != DEAD)
			living++
	M.gauge("players/living", living, METRICS_CAT_PLAYERS, "online", "players")
	var/list/counts = get_admin_counts()
	M.gauge("staff/admins_present", length(counts["present"]), METRICS_CAT_STAFF, "admins", "admins")
	M.gauge("staff/admins_afk", length(counts["afk"]), METRICS_CAT_STAFF, "admins", "admins")
	if(GLOB.tickets)
		M.gauge("staff/tickets_open", length(GLOB.tickets.active_tickets), METRICS_CAT_STAFF, "tickets", "tickets")

// ---------------------------------------------------------------- native frame

/// Where the Rust frame (vg_frame, charged to the om_native system) spends its time: each phase's
/// microseconds per second (`frame.us.<phase>` counters, verdigris/ffi/src/frame.rs) and the world's
/// awake law items, so a change in om_native names the phase and the law that moved.
/datum/metrics_source/native

/datum/metrics_source/native/collect(datum/system/server_metrics/M, dt)
	var/list/rust = verdigris_metrics_list()
	for(var/name in rust)
		if(findtext(name, "frame.us.") != 1 && findtext(name, "world.awake.") != 1 && findtext(name, "world.stepped.") != 1)
			continue
		var/value = rust[name]
		if(!isnum(value))
			continue
		var/what = copytext(name, findtext(name, ".", findtext(name, ".") + 1) + 1)
		if(findtext(name, "frame.us.") == 1)
			var/per_s = rate(name, value, dt)
			if(!isnull(per_s))
				M.gauge("native/frame/[what]/us_per_s", per_s, METRICS_CAT_SERVER, "native", "us/s")
		else
			M.gauge("native/[findtext(name, "world.awake.") == 1 ? "awake" : "stepped"]/[what]", value, METRICS_CAT_SERVER, "native", "count")
