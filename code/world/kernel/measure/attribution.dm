// Kernel measurement: attribution inside sched_core and appearance_drain, and the post-init settle record.
//
// The tick meter (meter.dm) says WHICH system a tick went to. sched_core (timers, after(), every(), after_init(), the
// scheduler's own work) and appearance_drain (the redraw drain and change reactions) are each one lump, and the lumps
// are where a heavy tick usually hides. This table names what is inside them:
//  - KA_KIND_CALLBACK: one timer callback (after() / every() / after_init() / a keyed timer), keyed by the owner's
//    type and the proc it ran, or the declared entry for an every() / after_init() fire. Charged to sched_core.
//  - KA_KIND_REACTION: one change reaction (on_change / observe), keyed by the holder's type and its handler.
//  - KA_KIND_DRAW: one queued redraw, keyed by the atom's type and why it was queued (a class of the DEP_* bits).
// The last two are charged to appearance_drain, where the drain runs them.
//
// A row is a fixed-length list (KA_* indices) found through rows[owner type][proc or reason]. The hot call, note(),
// does two lookups and a handful of additions: keys are type paths, proc-name texts, interned entries and constant
// reason texts, so it builds no string and allocates nothing once a key has been seen. The table is bounded
// (KA_MAX_ROWS): a key past the bound lands on a per-kind overflow row, and at the end of the tick the cheaper half of
// the rows is dropped so the heavy ones are kept.
//
// Every row also keeps the cost that ran AFTER "Initializations complete" (post_*: count, ms, when it last ran, and
// how much of it ran past KA_SETTLE_FIRST): the settle table. SETTLE: summaries are logged ~2 and ~10 minutes after
// init complete, so something heavy that keeps running long after start is visible without a profiler.
//
// Nothing here changes what runs or when; it only reads TICK_USAGE and REALTIMEOFDAY.

/// Set by a dispatcher that knows better than the timer engine which callback it is running (rx_timer_fire() names the
/// real handler, an every() or after_init() fire names its entry); read and cleared by the timer loop that charges the call.
GLOBAL_VAR(km_attr_a)
GLOBAL_VAR(km_attr_b)
GLOBAL_DATUM(km_attr_entry, /datum/entry)
/// Timer callbacks running now (the timer loop is one: after_init_fire() charges itself only when none is).
GLOBAL_VAR_INIT(km_attr_depth, 0)

/datum/km_attr
	/// Owner type -> (proc / reason -> row).
	var/list/rows
	var/n_rows = 0
	/// The rows charged this tick: the first n_touched are live. Fixed size.
	var/list/touched
	var/n_touched = 0
	var/tick_serial = 1
	/// Kind -> the row a key past KA_MAX_ROWS lands on.
	var/list/overflow
	var/needs_prune = FALSE
	var/prunes = 0
	var/overflowed = 0
	var/notes = 0
	/// REALTIMEOFDAY (ds) when "Initializations complete" was logged; 0 before.
	var/init_real = 0
	var/settle_stage = 0
	var/next_settle = 0
	var/last_settle_line

/datum/km_attr/New()
	rows = list()
	touched = new /list(KA_MAX_ROWS + 8)
	overflow = list(
		km_attr_new_row(KA_KIND_CALLBACK, KM_SYS_SCHED_CORE, "(overflow)", "(overflow)"),
		km_attr_new_row(KA_KIND_REACTION, KM_SYS_APPEARANCE, "(overflow)", "(overflow)"),
		km_attr_new_row(KA_KIND_DRAW, KM_SYS_APPEARANCE, "(overflow)", "(overflow)"),
	)

/proc/km_attr_new_row(kind, sys, a, b)
	return list(kind, sys, a, b, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)

/// Why a draw was queued, as a constant text: the DEP_* bits of the queued refresh folded into 7 flags (run, draw, ui, push, legacy,
/// any derived value, fresh), so a reason is a lookup, never a string built per redraw.
/proc/km_attr_reason(pending)
	var/static/list/names
	if(!names)
		names = new /list(128)
		for(var/i in 1 to 128)
			var/flags = i - 1
			var/list/parts = list()
			if(flags & 1)
				parts += "run"
			if(flags & 2)
				parts += "draw"
			if(flags & 4)
				parts += "ui"
			if(flags & 8)
				parts += "push"
			if(flags & 16)
				parts += "legacy"
			if(flags & 32)
				parts += "values"
			if(flags & 64)
				parts += "created"
			names[i] = length(parts) ? jointext(parts, "+") : "none"
	return names[1 + (pending & 31) + ((pending & DEP_VALUES) ? 32 : 0) + ((pending & DEP_CREATED) ? 64 : 0)]

/// Charges `ms` to the row (kind, a, b), making it on first sight. `sys` is the system the work is charged to in the meter.
/// The hot call: no allocation once the key exists, no string.
/datum/km_attr/proc/note(kind, sys, a, b, ms)
	var/list/row
	var/list/by_a = rows[a]
	if(by_a)
		row = by_a[b]
	if(!row)
		row = add_row(kind, sys, a, b)
	if(ms < 0)
		ms = 0 // the tick usage wrapped (the callee slept across a tick boundary): not a cost
	notes++
	row[KA_COUNT] += 1
	var/lo = row[KA_MS] + ms
	if(lo >= KM_FLUSH_MS)
		lo -= KM_FLUSH_MS
		row[KA_MS_HI] += KM_FLUSH_MS
	row[KA_MS] = lo
	if(ms > row[KA_MAX])
		row[KA_MAX] = ms
	if(row[KA_TSER] != tick_serial)
		row[KA_TSER] = tick_serial
		row[KA_TMS] = ms
		touched[++n_touched] = row
	else
		row[KA_TMS] += ms
	if(init_real)
		var/now = REALTIMEOFDAY
		row[KA_POST_COUNT] += 1
		row[KA_LAST] = now
		var/post = row[KA_POST_MS] + ms
		if(post >= KM_FLUSH_MS)
			post -= KM_FLUSH_MS
			row[KA_POST_MS_HI] += KM_FLUSH_MS
		row[KA_POST_MS] = post
		if(now - init_real >= KA_SETTLE_FIRST)
			row[KA_LATE_COUNT] += 1
			var/late = row[KA_LATE_MS] + ms
			if(late >= KM_FLUSH_MS)
				late -= KM_FLUSH_MS
				row[KA_LATE_MS_HI] += KM_FLUSH_MS
			row[KA_LATE_MS] = late

/// A key seen for the first time (or the overflow row when the table is full).
/datum/km_attr/proc/add_row(kind, sys, a, b)
	if(isnull(b))
		b = "?"
	if(n_rows >= KA_MAX_ROWS)
		needs_prune = TRUE
		overflowed++
		return overflow[kind]
	var/list/by_a = rows[a]
	if(!by_a)
		by_a = list()
		rows[a] = by_a
	var/list/row = by_a[b]
	if(row)
		return row
	row = km_attr_new_row(kind, sys, a, b)
	by_a[b] = row
	n_rows++
	return row

/// Closes the tick: returns the overrun line's attribution text when `overrun` (null otherwise), advances the tick stamp, prunes a full
/// table and logs a due SETTLE summary.
/datum/km_attr/proc/end_tick(overrun)
	. = null
	if(overrun && n_touched)
		. = tick_text()
	tick_serial = tick_serial % 1000000 + 1
	n_touched = 0
	if(needs_prune)
		prune()
	if(next_settle && REALTIMEOFDAY >= next_settle)
		settle_due()

/// The overrun line's tail: the top KM_ATTR_TOP_N callbacks behind sched_core and the top redrawn types / reactions behind appearance_drain this tick.
/datum/km_attr/proc/tick_text()
	var/list/parts = list()
	for(var/sys in list(KM_SYS_SCHED_CORE, KM_SYS_APPEARANCE))
		var/list/top = select_top(KM_ATTR_TOP_N, KA_BY_TICK, sys)
		if(!length(top))
			continue
		var/list/names = list()
		for(var/list/row as anything in top)
			names += "[km_attr_describe(row)] [round(row[KA_TMS], 0.1)]ms"
		parts += "[km_systems().key_of(sys)] top: [jointext(names, "; ")]"
	return length(parts) ? " | [jointext(parts, " | ")]" : null

/// The rows, best first, up to `n`: `by` is KA_BY_TICK (this tick's ms), KA_BY_TOTAL (all ms) or KA_BY_POST (ms since init complete, rows that ran then
/// only); `sys` 0 = any system, else only rows charged to it. Allocates: reporting, never the tick path.
/datum/km_attr/proc/select_top(n, by, sys = 0, kind_mask = 0)
	var/list/best = list()
	var/list/best_value = list()
	if(by == KA_BY_TICK)
		for(var/i in 1 to n_touched)
			consider(touched[i], by, sys, kind_mask, n, best, best_value)
	else
		for(var/a in rows)
			var/list/by_a = rows[a]
			for(var/b in by_a)
				consider(by_a[b], by, sys, kind_mask, n, best, best_value)
		for(var/list/row as anything in overflow)
			consider(row, by, sys, kind_mask, n, best, best_value)
	return best

/// The heaviest `n` rows (all ms) of each system in `wanted` ("[system index]" -> TRUE), in one walk of the table: list("[system index]" -> list(rows)),
/// best first. What the MC Health panel expands its system rows into; select_top() per system walked the table once per system.
/datum/km_attr/proc/select_top_by_system(n, list/wanted)
	var/list/best = list()
	var/list/best_value = list()
	for(var/key in wanted)
		best[key] = list()
		best_value[key] = list()
	for(var/a in rows)
		var/list/by_a = rows[a]
		for(var/b in by_a)
			var/list/row = by_a[b]
			var/key = "[row[KA_SYS]]"
			if(wanted[key])
				consider(row, KA_BY_TOTAL, row[KA_SYS], 0, n, best[key], best_value[key])
	for(var/list/row as anything in overflow)
		var/key = "[row[KA_SYS]]"
		if(wanted[key])
			consider(row, KA_BY_TOTAL, row[KA_SYS], 0, n, best[key], best_value[key])
	return best

/datum/km_attr/proc/consider(list/row, by, sys, kind_mask, n, list/best, list/best_value)
	if(sys && row[KA_SYS] != sys)
		return
	if(kind_mask && !(kind_mask & (1 << row[KA_KIND])))
		return
	var/value
	switch(by)
		if(KA_BY_TICK)
			value = row[KA_TMS]
		if(KA_BY_POST)
			if(!row[KA_POST_COUNT])
				return
			value = row[KA_POST_MS] + row[KA_POST_MS_HI]
		else
			value = row[KA_MS] + row[KA_MS_HI]
	if(value <= 0 && by != KA_BY_POST)
		return
	var/at = length(best) + 1
	while(at > 1 && best_value[at - 1] < value)
		at--
	if(at > n)
		return
	best.Insert(at, list(row))
	best_value.Insert(at, value)
	if(length(best) > n)
		best.Cut(n + 1)
		best_value.Cut(n + 1)

/// A full table drops the cheaper half (by total ms) so the heavy callbacks and types stay. At the end of a tick: no row is live then.
/datum/km_attr/proc/prune()
	needs_prune = FALSE
	prunes++
	var/list/totals = list()
	for(var/a in rows)
		var/list/by_a = rows[a]
		for(var/b in by_a)
			var/list/row = by_a[b]
			totals += row[KA_MS] + row[KA_MS_HI]
	if(!length(totals))
		return
	totals = sortTim(totals, GLOBAL_PROC_REF(cmp_numeric_asc))
	var/cut = totals[max(1, round(length(totals) / 2))]
	var/list/dead_a = list()
	for(var/a in rows)
		var/list/by_a = rows[a]
		var/list/drop = list()
		for(var/b in by_a)
			var/list/row = by_a[b]
			if(row[KA_MS] + row[KA_MS_HI] <= cut)
				drop += b
		for(var/b in drop)
			by_a -= b
			n_rows--
		if(!length(by_a))
			dead_a += a
	for(var/a in dead_a)
		rows -= a

// ---------------------------------------------------------------- naming (reporting only)

/// "/obj/machinery/light -> process" for a callback, "/obj/item/x draw (draw+values)" for a redraw: built when a report is written.
/proc/km_attr_describe(list/row)
	var/b = row[KA_B]
	if(istype(b, /datum/entry))
		var/datum/entry/E = b
		b = "[E.kind]: [copytext(E.sig, 1, 100)]"
	switch(row[KA_KIND])
		if(KA_KIND_DRAW)
			return "[row[KA_A]] draw ([b])"
		if(KA_KIND_REACTION)
			return "[row[KA_A]] on_change -> [b]"
	return "[row[KA_A]] -> [b]"

/proc/km_attr_kind_name(kind)
	switch(kind)
		if(KA_KIND_CALLBACK)
			return "callback"
		if(KA_KIND_REACTION)
			return "reaction"
	return "draw"

/// One report row of a table row.
/datum/km_attr/proc/row_data(list/row)
	var/list/out = list(
		"source" = km_attr_describe(row),
		"owner" = "[row[KA_A]]",
		"kind" = km_attr_kind_name(row[KA_KIND]),
		"system" = km_systems().key_of(row[KA_SYS]),
		"count" = row[KA_COUNT],
		"total_ms" = round(row[KA_MS] + row[KA_MS_HI], 0.01),
		"max_ms" = round(row[KA_MAX], 0.01),
	)
	if(row[KA_POST_COUNT])
		out["post_init_count"] = row[KA_POST_COUNT]
		out["post_init_ms"] = round(row[KA_POST_MS] + row[KA_POST_MS_HI], 0.01)
		out["last_seconds_after_init"] = round((row[KA_LAST] - init_real) * 0.1, 0.1)
		out["after_2min_count"] = row[KA_LATE_COUNT]
		out["after_2min_ms"] = round(row[KA_LATE_MS] + row[KA_LATE_MS_HI], 0.01)
	return out

/// The sections of PERF_PROFILE: top callbacks (timers and reactions by total ms), top redrawn types (count, total ms, max ms; the dominant
/// reason), the post-init settle table and the table's own health.
/datum/km_attr/proc/report(top = 20)
	var/datum/km_attr_walk/W = walk_begin(top)
	walk_step(W, INFINITY)
	return walk_result(W)

/// A report() being walked a few rows at a time: the profiler builds one a minute, and the whole walk (4096 rows) held one tick for 60-170 ms (debug.log
/// PROFILER SAMPLE, 2026-11-13). The table's keys are fixed at the start; a row that is pruned meanwhile is skipped.
/datum/km_attr_walk
	var/top = 20
	/// The next owner type of the table (by position: a table the size of this one is never copied), and the one being walked: its table and the next row of it.
	/// A row pruned meanwhile moves the rest of the table up a place, so the walk may skip a row or see one twice (a smear, like the panel's own reads).
	var/at = 1
	var/overflow_done = FALSE
	var/list/call_best
	var/list/call_value
	var/list/post_best
	var/list/post_value
	var/list/folded
	var/cur_a
	var/list/cur_table
	var/cur_at = 1
	var/list/cur_entry
	/// Rows visited, for the profile's own trace line.
	var/visited = 0

/datum/km_attr/proc/walk_begin(top = 20)
	var/datum/km_attr_walk/W = new
	W.top = top
	W.call_best = list()
	W.call_value = list()
	W.post_best = list()
	W.post_value = list()
	W.folded = list()
	return W

/// Walks rows for `budget_ms`, checked every KA_WALK_CHECK_ROWS rows. TRUE when the table has been walked to its end.
/// One walk of the table feeds all three sections (three walks and a text per row cost ~75 ms of one tick).
/datum/km_attr/proc/walk_step(datum/km_attr_walk/W, budget_ms)
	var/started = TICK_USAGE_REAL
	var/top = W.top
	var/since_check = 0
	while(W.cur_table || W.at <= length(rows))
		if(!W.cur_table)
			W.cur_a = rows[W.at++]
			W.cur_table = rows[W.cur_a]
			if(!W.cur_table)
				continue
			W.cur_at = 1
			W.cur_entry = null
		var/a = W.cur_a
		var/list/table = W.cur_table
		while(W.cur_at <= length(table))
			var/list/row = table[table[W.cur_at++]]
			if(row)
				W.visited++
				consider(row, KA_BY_TOTAL, 0, KA_CALLBACK_KINDS, top, W.call_best, W.call_value)
				if(row[KA_POST_COUNT])
					consider(row, KA_BY_POST, 0, 0, top, W.post_best, W.post_value)
				if(row[KA_KIND] == KA_KIND_DRAW)
					var/ms = row[KA_MS] + row[KA_MS_HI]
					var/list/entry = W.cur_entry
					if(!entry)
						entry = list("type" = a, "count" = 0, "total_ms" = 0, "max_ms" = 0, "reason" = row[KA_B], "reason_ms" = -1)
						W.folded[a] = entry
						W.cur_entry = entry
					entry["count"] += row[KA_COUNT]
					entry["total_ms"] += ms
					entry["max_ms"] = max(entry["max_ms"], row[KA_MAX])
					if(ms > entry["reason_ms"])
						entry["reason"] = row[KA_B]
						entry["reason_ms"] = ms
			if(!(++since_check % KA_WALK_CHECK_ROWS) && TICK_DELTA_TO_MS(TICK_USAGE_REAL - started) >= budget_ms)
				if(W.cur_at > length(table))
					W.cur_table = null
				return FALSE
		W.cur_table = null
		if(W.at <= length(rows) && TICK_DELTA_TO_MS(TICK_USAGE_REAL - started) >= budget_ms)
			return FALSE
	if(!W.overflow_done)
		W.overflow_done = TRUE
		for(var/list/row as anything in overflow)
			consider(row, KA_BY_TOTAL, 0, KA_CALLBACK_KINDS, top, W.call_best, W.call_value)
			if(row[KA_POST_COUNT])
				consider(row, KA_BY_POST, 0, 0, top, W.post_best, W.post_value)
	return TRUE

/// The heaviest rows of each system in "wanted" ("[system index]" -> anything), being found a slice at a time (select_top_by_system(), walked the way walk_step() does).
/datum/km_attr_sys_walk
	var/n = 5
	var/list/wanted
	var/list/best
	var/list/best_value
	var/at = 1
	var/list/cur_table
	var/cur_at = 1
	var/overflow_done = FALSE
	var/visited = 0

/datum/km_attr/proc/sys_walk_begin(n, list/wanted)
	var/datum/km_attr_sys_walk/W = new
	W.n = n
	W.wanted = wanted
	W.best = list()
	W.best_value = list()
	for(var/key in wanted)
		W.best[key] = list()
		W.best_value[key] = list()
	return W

/// Walks rows for `budget_ms`, checked every KA_WALK_CHECK_ROWS rows. TRUE when the table has been walked to its end.
/datum/km_attr/proc/sys_walk_step(datum/km_attr_sys_walk/W, budget_ms)
	var/started = TICK_USAGE_REAL
	var/list/wanted = W.wanted
	var/since_check = 0
	while(W.cur_table || W.at <= length(rows))
		if(!W.cur_table)
			W.cur_table = rows[rows[W.at++]]
			if(!W.cur_table)
				continue
			W.cur_at = 1
		var/list/table = W.cur_table
		while(W.cur_at <= length(table))
			var/list/row = table[table[W.cur_at++]]
			if(row)
				W.visited++
				var/key = "[row[KA_SYS]]"
				if(wanted[key])
					consider(row, KA_BY_TOTAL, row[KA_SYS], 0, W.n, W.best[key], W.best_value[key])
			if(!(++since_check % KA_WALK_CHECK_ROWS) && TICK_DELTA_TO_MS(TICK_USAGE_REAL - started) >= budget_ms)
				if(W.cur_at > length(table))
					W.cur_table = null
				return FALSE
		W.cur_table = null
		if(W.at <= length(rows) && TICK_DELTA_TO_MS(TICK_USAGE_REAL - started) >= budget_ms)
			return FALSE
	if(!W.overflow_done)
		W.overflow_done = TRUE
		for(var/list/row as anything in overflow)
			var/overflow_key = "[row[KA_SYS]]"
			if(wanted[overflow_key])
				consider(row, KA_BY_TOTAL, row[KA_SYS], 0, W.n, W.best[overflow_key], W.best_value[overflow_key])
	return TRUE

/// The finished walk as report() returns it.
/datum/km_attr/proc/walk_result(datum/km_attr_walk/W)
	var/top = W.top
	var/list/callbacks = list()
	for(var/list/row as anything in W.call_best)
		callbacks += list(row_data(row))
	var/list/settle = list()
	for(var/list/row as anything in W.post_best)
		settle += list(row_data(row))
	return list(
		"callbacks" = callbacks,
		"redrawn_types" = type_rows_of(W.folded, top),
		"settle" = settle,
		"init_complete_seconds_ago" = init_real ? round((REALTIMEOFDAY - init_real) * 0.1, 0.1) : null,
		"rows" = n_rows,
		"notes" = notes,
		"prunes" = prunes,
		"overflowed" = overflowed,
	)

/// Redraw rows folded per atom type, best total ms first.
/datum/km_attr/proc/type_rows(top)
	var/list/folded = list()
	for(var/a in rows)
		var/list/by_a = rows[a]
		var/list/entry = null
		for(var/b in by_a)
			var/list/row = by_a[b]
			if(row[KA_KIND] != KA_KIND_DRAW)
				continue
			var/ms = row[KA_MS] + row[KA_MS_HI]
			if(!entry)
				entry = list("type" = a, "count" = 0, "total_ms" = 0, "max_ms" = 0, "reason" = row[KA_B], "reason_ms" = -1)
				folded[a] = entry
			entry["count"] += row[KA_COUNT]
			entry["total_ms"] += ms
			entry["max_ms"] = max(entry["max_ms"], row[KA_MAX])
			if(ms > entry["reason_ms"])
				entry["reason"] = row[KA_B]
				entry["reason_ms"] = ms
	return type_rows_of(folded, top)

/// The folded redraw rows (type path -> entry) as report rows: best total first, `top` of them, the path written out as text.
/datum/km_attr/proc/type_rows_of(list/folded, top)
	var/list/out = list()
	for(var/name in folded)
		var/list/entry = folded[name]
		entry["type"] = "[name]"
		entry["total_ms"] = round(entry["total_ms"], 0.01)
		entry["max_ms"] = round(entry["max_ms"], 0.01)
		entry -= "reason_ms"
		out += list(entry)
	out = sortTim(out, GLOBAL_PROC_REF(cmp_km_attr_total_dsc))
	if(length(out) > top)
		out.Cut(top + 1)
	return out

/proc/cmp_km_attr_total_dsc(list/a, list/b)
	return b["total_ms"] - a["total_ms"]

// ---------------------------------------------------------------- settle

/// "Initializations complete" was logged: from here every row also counts what it costs after init, and the SETTLE summaries are due.
/datum/km_attr/proc/init_complete()
	init_real = max(REALTIMEOFDAY, 1)
	settle_stage = 0
	next_settle = init_real + KA_SETTLE_FIRST

/datum/km_attr/proc/settle_due()
	var/stage = ++settle_stage
	next_settle = stage == 1 ? init_real + KA_SETTLE_SECOND : 0
	last_settle_line = settle_summary()
	log_world(last_settle_line)

/// "SETTLE: +120s after init: 41 sources ran since init (88ms); 6 still ran after +2min (3.1ms); top: ..." Built when it is due.
/datum/km_attr/proc/settle_summary()
	var/n = 0
	var/total = 0
	var/late_n = 0
	var/late_total = 0
	for(var/a in rows)
		var/list/by_a = rows[a]
		for(var/b in by_a)
			var/list/row = by_a[b]
			if(!row[KA_POST_COUNT])
				continue
			n++
			total += row[KA_POST_MS] + row[KA_POST_MS_HI]
			if(row[KA_LATE_COUNT])
				late_n++
				late_total += row[KA_LATE_MS] + row[KA_LATE_MS_HI]
	var/list/names = list()
	for(var/list/row as anything in select_top(5, KA_BY_POST))
		names += "[km_attr_describe(row)] [row[KA_POST_COUNT]]x [round(row[KA_POST_MS] + row[KA_POST_MS_HI], 0.1)]ms (last +[round((row[KA_LAST] - init_real) * 0.1)]s[row[KA_LATE_COUNT] ? ", [row[KA_LATE_COUNT]]x past +2min" : ""])"
	return "SETTLE: +[round((REALTIMEOFDAY - init_real) * 0.1)]s after init: [n] sources ran since init complete ([round(total, 0.1)]ms); [late_n] still ran past +[KA_SETTLE_FIRST / 10]s ([round(late_total, 0.1)]ms there); top: [length(names) ? jointext(names, "; ") : "none"]"

/// Slow single calls logged so far this round (the log keeps the first KM_SLOW_CALL_LOG_MAX).
GLOBAL_VAR_INIT(km_slow_calls_logged, 0)
#define KM_SLOW_CALL_LOG_MAX 60

/// What a holder adds to its slow-call line (where it stands, what it was doing). Overridden by the types whose slow calls need more than a type.
/datum/proc/slow_call_detail()
	return ""

/atom/slow_call_detail()
	var/turf/where = get_turf(src)
	return where ? "at ([where.x],[where.y],[where.z]) in [get_area(where)]" : "in nullspace"

/// Logs one callback that took `ms` or more (KM_SLOW_CALL_MS): the holder, the callback, how long after init it ran, and the holder's own detail, so a
/// single 1 s call in a settle table is named by what it was holding and where, which a total by type cannot show.
/proc/km_slow_call(datum/holder, what, ms)
	if(GLOB.km_slow_calls_logged >= KM_SLOW_CALL_LOG_MAX)
		return
	if(!km_meter().attr.init_real)
		return // during init the settle table and the boot logs account for every call; a line each would bury the round
	GLOB.km_slow_calls_logged++
	var/init_real = km_meter().attr.init_real
	var/since = init_real ? "+[round((REALTIMEOFDAY - init_real) * 0.1)]s after init" : "during init"
	if(istype(what, /datum/entry))
		var/datum/entry/E = what
		what = "[E.kind]: [copytext(E.sig, 1, 160)]" // the entry by what it declares (an every(), a started_work() step), not "/datum/entry"
	log_world("SLOW CALL: [round(ms, 0.1)] ms [holder?.type] -> [what] ([since]) [holder?.slow_call_detail()] clients [length(GLOB.clients)]")

/// The proc profile as it stands (world.Profile, running under AUTO_PROFILE) as one line: the `self_rows` procs with the most self time and the `total_rows`
/// with the most total time, seconds and calls. The caller clears the profile (PROFILE_CLEAR) where the stretch it wants named begins.
/proc/km_profile_text(self_rows = 14, total_rows = 10)
	var/list/rows = json_decode(world.Profile(PROFILE_REFRESH, format = "json"))
	if(!islist(rows))
		return "no profile (AUTO_PROFILE is off)"
	var/list/by_self = sortTim(rows.Copy(), GLOBAL_PROC_REF(cmp_profile_self), FALSE)
	var/list/by_total = sortTim(rows.Copy(), GLOBAL_PROC_REF(cmp_profile_total), FALSE)
	var/text = "by self:"
	for(var/i in 1 to min(self_rows, length(by_self)))
		var/list/row = by_self[i]
		text += " [row["name"]] self [row["self"]] total [row["total"]] x[row["calls"]];"
	text += " by total:"
	for(var/i in 1 to min(total_rows, length(by_total)))
		var/list/row = by_total[i]
		text += " [row["name"]] total [row["total"]] x[row["calls"]];"
	return text

/proc/cmp_profile_self(list/a, list/b)
	return b["self"] - a["self"]

/proc/cmp_profile_total(list/a, list/b)
	return b["total"] - a["total"]
