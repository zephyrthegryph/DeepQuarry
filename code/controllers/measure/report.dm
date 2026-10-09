// Kernel measurement: reading the numbers.
//
// One source feeds every surface: the "Kernel" view of the MC stat panel, the Tick Report admin verb,
// scheduler_diagnostics() and the benchmark metrics. Each reads a stats set (the live one, or a benchmark window)
// through km_report_systems() / km_report_input(), so they cannot disagree.

// Columns of a km_rollup() row.
#define KM_ROLL_BEHAVIOURS 1
#define KM_ROLL_RUNS 2
#define KM_ROLL_SLOT_MS 3
#define KM_ROLL_LATE_MAX 4
#define KM_ROLL_DEFERRALS 5
#define KM_ROLL_BREACHES 6
#define KM_ROLL_WAKES 7
#define KM_ROLL_DEADLINES 8
#define KM_ROLL_ERRORS 9
#define KM_ROLL_LEN 9

/// The scheduler's per-behaviour counters rolled up to their systems: a list indexed by system index whose entries
/// are KM_ROLL_* rows (null for a system with no behaviours). Counters are cumulative since the scheduler's stats
/// were last cleared; a stats set subtracts the roll-up it opened with. Behaviours past OM_MAX_STAT_TYPES share one
/// counter bucket in the scheduler, so they cannot be attributed and are left out (km_unrolled_behaviours()).
/proc/km_rollup(datum/om/scheduler/sched)
	var/list/rows = new /list(KM_MAX_SYSTEMS)
	var/datum/om/registry/reg = definition_registry()
	var/list/stats = sched.stats
	for(var/datum/om/behaviour/B as anything in reg.behaviours)
		if(!B || B.id >= OM_MAX_STAT_TYPES)
			continue
		var/idx = B.system_idx || KM_SYS_OTHER
		var/list/row = rows[idx]
		if(!row)
			row = new /list(KM_ROLL_LEN)
			for(var/i in 1 to KM_ROLL_LEN)
				row[i] = 0
			rows[idx] = row
		row[KM_ROLL_BEHAVIOURS]++
		var/list/S = B.id <= length(stats) ? stats[B.id] : null
		if(!S)
			continue
		row[KM_ROLL_RUNS] += S[OM_STAT_RUNS]
		row[KM_ROLL_SLOT_MS] += S[OM_STAT_MS]
		row[KM_ROLL_LATE_MAX] = max(row[KM_ROLL_LATE_MAX], S[OM_STAT_LATE_MAX])
		row[KM_ROLL_DEFERRALS] += S[OM_STAT_DEFERRALS]
		row[KM_ROLL_BREACHES] += S[OM_STAT_BREACHES]
		row[KM_ROLL_WAKES] += S[OM_STAT_WAKES]
		row[KM_ROLL_DEADLINES] += S[OM_STAT_DEADLINES]
		row[KM_ROLL_ERRORS] += S[OM_STAT_ERRORS]
	return rows

/// How many registered behaviours km_rollup() cannot attribute (ids past the scheduler's stat table).
/proc/km_unrolled_behaviours()
	. = 0
	for(var/datum/om/behaviour/B as anything in definition_registry().behaviours)
		if(B && B.id >= OM_MAX_STAT_TYPES)
			.++

/// Sorts report rows by overrun share, then total ms, both descending.
/proc/cmp_km_rows(list/a, list/b)
	var/by_share = b["overrun_share"] - a["overrun_share"]
	if(by_share)
		return by_share
	return b["ms_total"] - a["ms_total"]

/// One row per system charged in `stats_set` (ordered by overrun share, then ms). With `sched`, the OM counters
/// (runs, breaches, deferrals, ...) come from the behaviours rolled up since the set opened.
/proc/km_report_systems(datum/km_stats_set/stats_set, datum/om/scheduler/sched)
	var/datum/km_systems/registry = km_systems()
	var/elapsed = stats_set.elapsed_seconds()
	var/list/roll = sched ? km_rollup(sched) : null
	var/list/base = stats_set.rollup_base
	var/total_over = 0
	for(var/datum/system_stats/S as anything in stats_set.systems)
		if(S)
			total_over += S.overrun_ms
	var/list/rows = list()
	for(var/idx in 1 to registry.count())
		var/datum/system_stats/S = stats_set.systems[idx]
		var/list/R = roll?[idx]
		var/list/R0 = base?[idx]
		if(!S && (!R || !R[KM_ROLL_RUNS]))
			continue
		var/list/row = list(
			"key" = registry.keys[idx],
			"kind" = registry.kinds[idx] == KM_KIND_MC ? "mc" : (registry.kinds[idx] == KM_KIND_OM ? "om" : "pseudo"),
			"lane" = registry.lane_label(idx),
			"ticks" = S?.ticks || 0,
			"ms_total" = S ? round(S.ms_total(), 0.001) : 0,
			"ms_per_s" = S ? round(S.ms_total() / elapsed, 0.001) : 0,
			"p50_ms" = S ? round(S.hist.percentile(0.50), 0.001) : 0,
			"p95_ms" = S ? round(S.hist.percentile(0.95), 0.001) : 0,
			"p99_ms" = S ? round(S.hist.percentile(0.99), 0.001) : 0,
			"max_ms" = S ? round(S.hist.max_seen, 0.001) : 0,
			"late_max_ds" = S?.late_max || 0,
			"overrun_ms" = S ? round(S.overrun_ms, 0.001) : 0,
			"overrun_share" = (S && total_over) ? round(S.overrun_ms / total_over, 0.0001) : 0,
			"overrun_top_ticks" = S?.overrun_top_ticks || 0,
			"behaviours" = R ? R[KM_ROLL_BEHAVIOURS] : 0,
			"runs" = R ? R[KM_ROLL_RUNS] - (R0 ? R0[KM_ROLL_RUNS] : 0) : 0,
			"breaches" = R ? R[KM_ROLL_BREACHES] - (R0 ? R0[KM_ROLL_BREACHES] : 0) : 0,
			"deferrals" = R ? R[KM_ROLL_DEFERRALS] - (R0 ? R0[KM_ROLL_DEFERRALS] : 0) : 0,
			"errors" = R ? R[KM_ROLL_ERRORS] - (R0 ? R0[KM_ROLL_ERRORS] : 0) : 0,
		)
		rows += list(row)
	return sortTim(rows, GLOBAL_PROC_REF(cmp_km_rows))

/// The input record of `stats_set`: wait in ms and in ticks, where in the tick input ran, and the verb queue.
/proc/km_report_input(datum/km_stats_set/stats_set)
	var/datum/input_stats/I = stats_set.input
	var/tick_ms = world.tick_lag * 100
	var/p50 = I.wait.percentile(0.50)
	var/p95 = I.wait.percentile(0.95)
	var/p99 = I.wait.percentile(0.99)
	return list(
		"samples" = I.wait.count,
		"clicks" = I.clicks,
		"verbs_queued" = I.verbs_queued,
		"verbs_direct" = I.verbs_direct,
		"verbs_run" = I.verbs_run,
		"queue_hwm" = I.queue_hwm,
		"queue_now" = km_verb_queue_length(),
		"wait_p50_ms" = round(p50, 0.001),
		"wait_p95_ms" = round(p95, 0.001),
		"wait_p99_ms" = round(p99, 0.001),
		"wait_max_ms" = round(I.wait.max_seen, 0.001),
		"wait_p50_ticks" = round(p50 / tick_ms, 0.0001),
		"wait_p95_ticks" = round(p95 / tick_ms, 0.0001),
		"wait_p99_ticks" = round(p99 / tick_ms, 0.0001),
		"click_p99_ms" = round(I.click_wait.percentile(0.99), 0.001),
		"verb_p99_ms" = round(I.verb_wait.percentile(0.99), 0.001),
		"depth_p50" = I.depth.percentile(0.50),
		"depth_p95" = I.depth.percentile(0.95),
	)

/// The Kernel view of the MC stat panel: the top `top_n` systems, the input row and the tick counters.
/proc/km_panel_data(top_n = 14)
	var/datum/tick_meter/meter = km_meter()
	var/datum/km_stats_set/stats_set = meter.live
	var/list/systems = km_report_systems(stats_set, GLOB.om_live_sched)
	if(length(systems) > top_n)
		systems.Cut(top_n + 1)
	return list(
		"systems" = systems,
		"input" = km_report_input(stats_set),
		"ticks" = stats_set.ticks,
		"overruns" = stats_set.overruns,
		"streak" = meter.streak,
		"max_streak" = stats_set.max_streak,
		"byond_reserve" = round(meter.byond_reserve(), 0.1),
		"maptick" = round(MAPTICK_LAST_INTERNAL_TICK_USAGE, 0.1),
		"recorded" = meter.ring_count,
		"last_overrun" = meter.last_overrun_line,
		"elapsed_s" = round(stats_set.elapsed_seconds(), 0.1),
		"unrolled_behaviours" = km_unrolled_behaviours(),
	)

/// Everything the live set knows, as data (scheduler_diagnostics(), tests): all systems, the input record and the meter.
/proc/km_diagnostics(datum/om/scheduler/sched)
	var/datum/tick_meter/meter = sched?.meter || km_meter()
	var/datum/km_stats_set/stats_set = meter.live
	return list(
		"systems" = km_report_systems(stats_set, sched),
		"input" = km_report_input(stats_set),
		"ticks" = stats_set.ticks,
		"overruns" = stats_set.overruns,
		"streak" = meter.streak,
		"max_streak" = stats_set.max_streak,
		"byond_reserve" = round(meter.byond_reserve(), 0.1),
		"recorded" = meter.ring_count,
		"last_overrun" = meter.last_overrun_line,
		"last_overrun_top" = LAZYCOPY(meter.last_overrun_top),
		"unrolled_behaviours" = km_unrolled_behaviours(),
	)

// ---------------------------------------------------------------- Tick Report

/// The flight recorder as an HTML table, newest tick first.
/proc/km_tick_report_html(overruns_only = FALSE)
	var/datum/tick_meter/meter = km_meter()
	var/list/entries = meter.recorded_entries(overruns_only)
	var/tick_ms = world.tick_lag * 100
	var/html = "<h2>Tick report</h2>"
	html += "<p>The last [meter.ring_count] recorded ticks ([round(meter.ring_count * tick_ms / 1000, 0.1)] s), newest first[overruns_only ? ", overruns only" : ""]. "
	html += "[length(entries)] shown. Overrun: usage over [KM_OVERRUN_USAGE]%. BYOND reserve (peak maptick): [round(meter.byond_reserve(), 0.1)]%.</p>"
	html += "<table border='1' cellspacing='0' cellpadding='3'><tr><th>Tick</th><th>Time (s)</th><th>Usage</th><th>Maptick</th><th>Input ms</th><th>Streak</th><th>1st</th><th>2nd</th><th>3rd</th></tr>"
	for(var/n in length(entries) to 1 step -1)
		var/list/entry = entries[n]
		var/usage = entry[3]
		var/list/keys = entry[7]
		var/list/mss = entry[8]
		var/style = usage > KM_OVERRUN_USAGE ? " style='background:#f4c7c3'" : (usage > 85 ? " style='background:#fce8b2'" : "")
		html += "<tr[style]><td>[entry[1]]</td><td>[round(entry[2] / 10, 0.1)]</td><td>[round(usage, 0.1)]%</td><td>[round(entry[4], 0.1)]%</td><td>[round(entry[5], 0.01)]</td><td>[entry[6]]</td>"
		for(var/k in 1 to KM_TOP_N)
			html += k <= length(keys) ? "<td>[html_encode(keys[k])] [round(mss[k], 0.1)] ms</td>" : "<td></td>"
		html += "</tr>"
	html += "</table>"
	return html

ADMIN_VERB(tick_report, R_DEBUG, "Tick Report", "Shows the flight recorder: the last minute of ticks with usage, maptick, input cost and the top systems of each.", ADMIN_CATEGORY_DEBUG_INVESTIGATE, mode as null|anything in list("Overruns only", "All ticks"))
	user.mob << browse(km_tick_report_html(mode != "All ticks"), "window=tick_report;size=900x700")
	feedback_add_details("admin_verb", "TICKREP")

#undef KM_ROLL_BEHAVIOURS
#undef KM_ROLL_RUNS
#undef KM_ROLL_SLOT_MS
#undef KM_ROLL_LATE_MAX
#undef KM_ROLL_DEFERRALS
#undef KM_ROLL_BREACHES
#undef KM_ROLL_WAKES
#undef KM_ROLL_DEADLINES
#undef KM_ROLL_ERRORS
#undef KM_ROLL_LEN
