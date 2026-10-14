// What the metrics service captures beyond its samples: the call stack of a runtime, the procs behind
// a tick that went far over budget (a short BYOND profile), and the split of every tick into time
// before the MC, the MC and after it (from /world/Tick, the last DM code of a tick).

// ---------------------------------------------------------------- runtimes

/// The "call stack:" lines of a runtime's desc, trimmed: at most METRICS_RUNTIME_STACK_LINES lines of at
/// most 160 characters. An empty list when the desc has none.
/proc/metrics_runtime_stack(desc)
	. = list()
	var/at = findtext(desc, "call stack:")
	if(!at)
		return
	for(var/line in splittext(copytext(desc, at + 11), "\n"))
		line = trim(line)
		if(!length(line))
			continue
		. += copytext(line, 1, 160)
		if(length(.) >= METRICS_RUNTIME_STACK_LINES)
			return

// ---------------------------------------------------------------- profile captures

/datum/system/server_metrics
	/// The profile capture running: list("reason", "from_t", "spike" = the tick record that started it, or null).
	var/list/profile_capture
	/// REALTIMEOFDAY the last spike capture started, for METRICS_PROFILE_COOLDOWN.
	var/last_spike_capture = -INFINITY
	/// REALTIMEOFDAY the next steady-play capture is due (maybe_profile_steady()); 0 before the round starts or once
	/// none is due again.
	var/next_steady_profile = 0

/// A tick went far over budget (note_overrun()): unless a capture is running or one ran recently, profile
/// the next few seconds, so a recurring cause is stored with the procs behind it.
/datum/system/server_metrics/proc/spike_seen(list/tick_record)
	var/list/spike = tick_record.Copy()
	spike["t"] = now_t()
	if(profile_capture)
		var/list/held = profile_capture["spike"]
		if(!held || held["usage"] < spike["usage"])
			profile_capture["spike"] = spike
		return
	var/seconds = CONFIG_GET(number/metrics_spike_profile)
	if(!seconds || REALTIMEOFDAY - last_spike_capture < METRICS_PROFILE_COOLDOWN)
		return
	last_spike_capture = REALTIMEOFDAY
	start_profile_capture("spike", seconds SECONDS, spike)

/// The round has started: profile its first minute (METRICS_PROFILE_ROUND_START), when the post-setup work
/// of the round start runs. A freeze in that window is stored with its procs (the capture keeps it).
/datum/system/server_metrics/proc/profile_round_start()
	var/seconds = CONFIG_GET(number/metrics_profile_round_start)
	if(seconds)
		start_profile_capture("round start", seconds SECONDS)
	next_steady_profile = REALTIMEOFDAY + METRICS_PROFILE_STEADY_FIRST

/// Each sample: once the round has run METRICS_PROFILE_STEADY_FIRST, and then every metrics_profile_steady_every
/// minutes, profile metrics_profile_steady seconds of ordinary play. Idle cost spread thinly over many procs never
/// starts a spike capture; this stores it anyway. Waits for a running capture to finish.
/datum/system/server_metrics/proc/maybe_profile_steady()
	if(!next_steady_profile || REALTIMEOFDAY < next_steady_profile || profile_capture)
		return
	var/seconds = CONFIG_GET(number/metrics_profile_steady)
	var/every = CONFIG_GET(number/metrics_profile_steady_every)
	next_steady_profile = (seconds && every) ? REALTIMEOFDAY + every MINUTES : 0
	if(seconds)
		start_profile_capture("steady", seconds SECONDS)

/// Clears and starts BYOND's proc profiler for `duration`, then finish_profile_capture() records the procs
/// that took the most time as a METRICS_EVENT_PROFILE event. Does nothing while AUTO_PROFILE owns the
/// profiler or another capture runs.
/datum/system/server_metrics/proc/start_profile_capture(reason, duration, list/spike)
	if(profile_capture || !wants_recording() || CONFIG_GET(flag/auto_profile))
		return FALSE
	if(Kernel?.init_stage_completed < INITSTAGE_MAX)
		return FALSE // boot is not a spike
	profile_capture = list("reason" = reason, "from_t" = now_t(), "spike" = spike)
	world.Profile(PROFILE_CLEAR)
	world.Profile(PROFILE_START)
	var/datum/time_scheduler/sched = GLOB.om_live_sched
	if(sched)
		sched.type_costs = list()
	after(null, duration, GLOBAL_PROC_REF(metrics_finish_profile_capture))
	return TRUE

/proc/metrics_finish_profile_capture()
	SSserver_metrics?.finish_profile_capture()

/datum/system/server_metrics/proc/finish_profile_capture()
	if(!profile_capture)
		return
	var/list/capture = profile_capture
	profile_capture = null
	var/list/rows = json_decode(world.Profile(PROFILE_REFRESH, format = "json"))
	if(!CONFIG_GET(flag/auto_profile))
		world.Profile(PROFILE_STOP)
	var/list/top = metrics_profile_top(rows, METRICS_PROFILE_TOP)
	var/datum/time_scheduler/sched = GLOB.om_live_sched
	var/list/type_costs = sched?.type_costs
	if(sched)
		sched.type_costs = null
	var/self_total = 0
	for(var/list/row as anything in rows)
		self_total += row["self"]
	var/list/spike = capture["spike"]
	var/list/payload = list(
		"reason" = capture["reason"],
		"from_t" = capture["from_t"],
		"to_t" = now_t(),
		// Every proc's self time, so the top list can be read as a share of all DM time in the window.
		"self_total" = round(self_total * 1000, 0.1),
		"procs" = length(rows),
		"top" = top,
		// The object-model steps, wakes and deadlines behind those procs: behaviour and entity type, by time.
		"om_types" = metrics_type_costs_top(type_costs, METRICS_PROFILE_TOP),
	)
	var/message = "[capture["reason"]] profile, [now_t() - capture["from_t"]] s"
	if(spike)
		payload["spike"] = list("t" = spike["t"], "usage" = spike["usage"], "cause" = spike["cause"], "top_systems" = spike["top_systems"])
		message += ", worst tick [round(spike["usage"])]% ([spike["cause"]])"
	METRICS_EVENT(METRICS_EVENT_PROFILE, capture["reason"], "", "", message, payload)

/// The `count` costliest entries of a scheduler type_costs table ("behaviour|type" -> tick usage), as
/// list(list("behaviour", "type", "ms")), most first.
/proc/metrics_type_costs_top(list/type_costs, count)
	. = list()
	if(!length(type_costs))
		return
	var/list/sorted = sortTim(type_costs.Copy(), GLOBAL_PROC_REF(cmp_numeric_desc), associative = TRUE)
	for(var/key in sorted)
		var/at = findtext(key, "|")
		. += list(list("behaviour" = copytext(key, 1, at), "type" = copytext(key, at + 1), "ms" = round(TICK_DELTA_TO_MS(sorted[key]), 0.01)))
		if(length(.) >= count)
			return

/// The `count` procs of a world.Profile() JSON table with the most self time, as list(list("name", "self",
/// "total", "real", "calls")) with times in ms, most first.
/proc/metrics_profile_top(list/rows, count)
	var/list/top = list()
	for(var/list/row as anything in rows)
		var/self = row["self"]
		if(!self)
			continue
		// The kept entries are in ms; the profiler's rows are in seconds.
		var/self_ms = round(self * 1000, 0.01)
		if(length(top) >= count)
			var/list/least = top[length(top)]
			if(self_ms <= least["self"])
				continue
			top.Cut(length(top))
		var/list/entry = list("name" = row["name"], "self" = self_ms, "total" = round(row["total"] * 1000, 0.01), "real" = round(row["real"] * 1000, 0.01), "calls" = row["calls"])
		var/at = length(top) + 1
		for(var/i in 1 to length(top))
			var/list/other = top[i]
			if(entry["self"] > other["self"])
				at = i
				break
		top.Insert(at, null)
		top[at] = entry
	return top

// ---------------------------------------------------------------- the frame outside the MC

/// Where each tick's proc time went, split at the MC's iteration, accumulated between samples (read and
/// reset by the frame metrics source). All in percent of a tick, summed over ticks.
/datum/tick_frame
	/// Before the MC's iteration (or the whole tick when the MC did not run): resumed sleeping procs, verbs
	/// run on the spot, Topic, clicks.
	var/pre = 0
	var/mc = 0
	/// After the MC recorded the tick, up to /world/Tick: sleeping procs resumed later in the tick.
	var/post = 0
	/// /world/Tick's own callbacks (world_next_tick()).
	var/callbacks = 0
	/// Topic calls (client/Topic), wherever in the tick they ran. Part of pre or post.
	var/topic = 0
	/// BYOND's map send (world.map_cpu), which runs after /world/Tick.
	var/map = 0
	var/ticks = 0
	/// Ticks whose time outside the MC alone was over budget.
	var/outside_overruns = 0

GLOBAL_DATUM_INIT(tick_frame, /datum/tick_frame, new)

/// Called by /world/Tick with TICK_USAGE: every DM proc due this tick has run, SendMaps has not. Must stay
/// cheap: it runs every tick.
/datum/tick_frame/proc/frame_end(usage)
	ticks++
	map += world.map_cpu
	var/before
	var/after = 0
	if(Kernel?.perf_tick_end_time == world.time)
		before = Kernel.perf_tick_start_usage
		mc += max(Kernel.perf_tick_end_usage - before, 0)
		after = max(usage - Kernel.perf_tick_end_usage, 0)
	else
		before = usage
	pre += before
	post += after
	// Boot (map load, MC init) runs outside the MC loop in ticks hundreds of times over budget: those are
	// not overruns of a running server, and would crowd every real one out of the first flush.
	if(Kernel?.init_stage_completed < INITSTAGE_MAX || Kernel.perf_tick_end_time < 0)
		return
	if(before + after > KM_OVERRUN_USAGE && (Kernel.perf_tick_end_time != world.time || after > KM_OVERRUN_USAGE))
		outside_overrun(usage, before, after)

/// A tick whose time outside the MC alone went over budget, which the MC's record of the tick does not show
/// (it ran before the time after it, or not at all). Recorded as an overrun caused by PERF_OUTSIDE_MC.
/datum/tick_frame/proc/outside_overrun(usage, before, after)
	outside_overruns++
	var/list/breakdown = list(list("name" = PERF_OUTSIDE_MC, "usage" = before + after))
	if(Kernel?.perf_tick_end_time == world.time)
		breakdown += list(list("name" = "MC", "usage" = max(usage - before - after, 0)))
	SSserver_metrics?.note_overrun(list(
		"world_time" = world.time, // ALLOW(sys_world_time_write): reports the clock in a diagnostic record, not a stored expiry
		"usage" = usage,
		"overrun" = max(usage - 100, 0),
		"cause" = PERF_OUTSIDE_MC,
		"pre_mc" = before,
		"post_mc" = after,
		"maptick" = world.map_cpu,
		"breakdown" = breakdown,
		"streak" = 1,
	))

/// ms per second of each part since the last call, then starts over. `dt` is seconds.
/datum/tick_frame/proc/take_rates(dt)
	var/factor = world.tick_lag / dt // percent of a tick summed over ticks -> ms per second
	. = list(
		"pre_mc" = pre * factor,
		"mc" = mc * factor,
		"post_mc" = post * factor,
		"world_tick_callbacks" = callbacks * factor,
		"topic" = topic * factor,
		"maptick" = map * factor,
		"ticks" = ticks,
		"outside_overruns" = outside_overruns,
	)
	pre = 0
	mc = 0
	post = 0
	callbacks = 0
	topic = 0
	map = 0
	ticks = 0
	outside_overruns = 0

/// The tick split at the MC: ms per second before the MC, in it, after it, in /world/Tick callbacks, in Topic
/// and in BYOND's map send. What runs outside the MC is what pre_mc and post_mc measure; Topic and the
/// callbacks are the parts of it that can be named, the rest is resumed sleeping procs and verbs.
/datum/metrics_source/frame

/datum/metrics_source/frame/collect(datum/system/server_metrics/M, dt)
	var/list/rates = GLOB.tick_frame.take_rates(dt)
	for(var/part in list("pre_mc", "mc", "post_mc", "world_tick_callbacks", "topic", "maptick"))
		M.gauge("frame/[part]/ms_per_s", rates[part], METRICS_CAT_SERVER, "frame", "ms/s")
	M.gauge("frame/outside_overruns", rates["outside_overruns"], METRICS_CAT_SERVER, "frame", "ticks")

/// Times every Topic call for the tick frame. This wraps the client's Topic in client procs.dm (compiled
/// earlier, so ..() runs it). A call that slept is not counted: its delta is not its cost.
// ALLOW(sys_topic_override): measurement wrapper around BYOND's href entry; it dispatches nothing itself.
/client/Topic(href, href_list, hsrc)
	var/started = TICK_USAGE
	var/started_time = world.time
	. = ..()
	if(world.time == started_time)
		GLOB.tick_frame.topic += max(TICK_USAGE - started, 0)

/// Each tick-meter system's cost in ms per second (code/controllers/measure/): every OM behaviour group, the
/// scheduler core (om_core), the appearance drain (om_appearance), the Rust world step (om_native) and clicks (input). Unlike the lane and
/// behaviour sources this includes om_core and om_native, which no behaviour owns.
/datum/metrics_source/systems

/datum/metrics_source/systems/collect(datum/system/server_metrics/M, dt)
	var/datum/km_stats_set/live = km_meter().live
	if(!live)
		return
	for(var/datum/system_stats/S as anything in live.systems)
		if(!S)
			continue
		var/ms_per_s = rate("s:[S.key]", S.ms_total(), dt)
		if(ms_per_s >= METRICS_BEHAVIOUR_MIN_MS_PER_S)
			M.gauge("system/[S.key]/ms_per_s", ms_per_s, METRICS_CAT_LANE, "systems", "ms/s")

/// The host, on Linux: how much CPU the server process got and how long its main thread waited for a CPU
/// (/proc/self/schedstat: run ns, run-queue wait ns), and the load average. Tick usage is wall time, so a
/// busy host shows up as tick usage no proc accounts for; the wait time says how much of it that is.
/// (Read through rust-g: procfs files report size 0, which file2text() takes as empty.)
/datum/metrics_source/host

/datum/metrics_source/host/collect(datum/system/server_metrics/M, dt)
	if(world.system_type != UNIX)
		return
	var/list/sched = splittext(trim(rustg_file_read("/proc/self/schedstat")), " ")
	if(length(sched) >= 2)
		var/run_ms = rate("run", text2num(sched[1]) / 1e6, dt)
		var/wait_ms = rate("wait", text2num(sched[2]) / 1e6, dt)
		if(!isnull(run_ms))
			M.gauge("host/main_thread_run/ms_per_s", run_ms, METRICS_CAT_SERVER, "host", "ms/s")
			M.gauge("host/main_thread_wait/ms_per_s", wait_ms, METRICS_CAT_SERVER, "host", "ms/s")
	var/list/load = splittext(rustg_file_read("/proc/loadavg"), " ")
	if(length(load))
		M.gauge("host/load_1m", text2num(load[1]), METRICS_CAT_SERVER, "host", "load")
