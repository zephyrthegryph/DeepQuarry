// Kernel measurement: the tick ledger.
//
// The tick meter (meter.dm) charges systems; its remainder against the tick's usage was "not attributed", and in a live round that remainder
// was most of the tick. The ledger closes it by keeping one exclusive timeline for the kernel's iteration: from the start of the
// BYOND tick to the end of the kernel's iteration (the same interval as the `usage` the performance windows average), every ms belongs
// to exactly one category, so the categories add up to the window by construction and what no marked region covers is
// KM_CAT_UNATTRIBUTED, a number that is meant to stay small.
//
// How: the code that does a kind of work brackets it with km_ledger_enter(category, owner type, proc) / km_ledger_leave(token). Entering
// charges the time since the last switch to the category that was current, so a bracket inside another (an on_change hook inside a drain,
// a Move inside a timer callback) takes its own time out of the outer one. A leave that was skipped by a runtime is repaired by the
// leave of the bracket around it (the token is the depth before the enter). The ledger runs only between begin() (top of the loop
// iteration) and finish() (record_performance_tick); an enter outside it does nothing.
//
// Cost: one TICK_USAGE read and a few list writes per bracket, no string built (names are type paths, proc names, entries). Per tick:
// one pass over the categories (the totals, the moving average, the zeroing). Rows (name -> count, ms, max) are bounded per category.
// Totals are cumulative since boot; the moving average (KM_LEDGER_EMA) is the "now" the panel draws.
//
// Outside the window: time after the kernel's iteration (resumed procs, /world/Tick) and BYOND's map send are noted from
// /datum/tick_frame/frame_end() (note_outside()), so the panel can say where the whole tick went, not only the part up to the kernel's end.

/// The one ledger. Made at world setup, never deleted in a round.
LIFECYCLE_KEEP_UNLESS_FORCED(/datum/km_ledger)
/datum/km_ledger
	/// TRUE between begin() and finish().
	var/active = FALSE
	/// The category, owner and proc being charged now.
	var/cur = KM_CAT_UNATTRIBUTED
	var/cur_a
	var/cur_b
	/// Where the last switch happened, in ms into the tick.
	var/cursor = 0
	var/depth = 0
	var/list/stack_cat
	var/list/stack_a
	var/list/stack_b
	/// Per category: this tick's ms, the moving average, cumulative ms (low and high part, see KM_FLUSH_MS), times charged.
	var/list/tick_ms
	var/list/ema
	var/list/lo
	var/list/hi
	var/list/counts
	/// Category -> owner -> proc -> row (KL_*).
	var/list/rows
	var/list/n_rows
	var/list/needs_prune
	var/prunes = 0
	var/overflowed = 0
	/// Closed windows, their cumulative ms, and the last one's length.
	var/ticks = 0
	var/window_lo = 0
	var/window_hi = 0
	var/window_ema = 0
	var/last_window_ms = 0
	/// Enters past KM_LEDGER_DEPTH (they are not charged separately).
	var/too_deep = 0
	/// Outside the window: BYOND ticks, ms after the kernel's iteration, ms of ticks the kernel did not close, ms of map send.
	var/world_ticks = 0
	var/post_lo = 0
	var/post_hi = 0
	var/post_ema = 0
	var/idle_lo = 0
	var/idle_hi = 0
	var/idle_ema = 0
	var/map_lo = 0
	var/map_hi = 0
	var/map_ema = 0
	/// REALTIMEOFDAY (ds) of the first window, for per-second rates.
	var/started_real = 0
	/// Where outside_since_mark() last read: BYOND ticks, ms after the kernel's iteration, ms of ticks the kernel did not close.
	var/mark_world_ticks = 0
	var/mark_post = 0
	var/mark_idle = 0

GLOBAL_DATUM_INIT(km_ledger, /datum/km_ledger, new)
/// The kernel phases' names as ledger rows, by KERNEL_PHASE_*.
GLOBAL_LIST_INIT(km_phase_labels, list("phase K", "phase S", "phase N", "phase U", "phase D", "phase P", "phase R", "phase G"))

/datum/km_ledger/New()
	stack_cat = new /list(KM_LEDGER_DEPTH)
	stack_a = new /list(KM_LEDGER_DEPTH)
	stack_b = new /list(KM_LEDGER_DEPTH)
	tick_ms = new /list(KM_CAT_COUNT)
	ema = new /list(KM_CAT_COUNT)
	lo = new /list(KM_CAT_COUNT)
	hi = new /list(KM_CAT_COUNT)
	counts = new /list(KM_CAT_COUNT)
	rows = new /list(KM_CAT_COUNT)
	n_rows = new /list(KM_CAT_COUNT)
	needs_prune = new /list(KM_CAT_COUNT)
	for(var/i in 1 to KM_CAT_COUNT)
		tick_ms[i] = 0
		ema[i] = 0
		lo[i] = 0
		hi[i] = 0
		counts[i] = 0
		rows[i] = list()
		n_rows[i] = 0
		needs_prune[i] = FALSE

/// Forgets everything recorded (a test, the profiler's reset).
/datum/km_ledger/proc/reset()
	active = FALSE
	depth = 0
	cur = KM_CAT_UNATTRIBUTED
	for(var/i in 1 to KM_CAT_COUNT)
		tick_ms[i] = 0
		ema[i] = 0
		lo[i] = 0
		hi[i] = 0
		counts[i] = 0
		rows[i] = list()
		n_rows[i] = 0
		needs_prune[i] = FALSE
	prunes = 0
	overflowed = 0
	ticks = 0
	window_lo = 0
	window_hi = 0
	window_ema = 0
	last_window_ms = 0
	too_deep = 0
	world_ticks = 0
	post_lo = 0
	post_hi = 0
	post_ema = 0
	idle_lo = 0
	idle_hi = 0
	idle_ema = 0
	map_lo = 0
	map_hi = 0
	map_ema = 0
	started_real = 0
	mark_world_ticks = 0
	mark_post = 0
	mark_idle = 0

// ---------------------------------------------------------------- the timeline

/// The kernel's iteration begins: everything before `now` (a TICK_USAGE, percent of a tick) is BYOND's (procs resumed ahead of the loop, verbs,
/// Topic), and the timeline goes on in the kernel's own residual.
/datum/km_ledger/proc/begin(now = TICK_USAGE)
	active = TRUE
	depth = 0
	var/ms = now * world.tick_lag
	if(ms > 0)
		tick_ms[KM_CAT_BYOND_PRE] += ms
		note(KM_CAT_BYOND_PRE, "BYOND", "before the kernel loop", ms)
	cur = KM_CAT_UNATTRIBUTED
	cur_a = "kernel"
	cur_b = "between marked regions"
	cursor = ms

/// Charges the time since the last switch to the current category.
/datum/km_ledger/proc/charge_segment(ms)
	var/seg = ms - cursor
	if(seg <= 0)
		return
	tick_ms[cur] += seg
	if(cur == KM_CAT_TIMER && GLOB.km_attr_a)
		// A dispatcher inside the call names the real handler (rx_timer_fire(), an every() or after_init() fire): the name the callback table uses.
		note(cur, GLOB.km_attr_a, GLOB.km_attr_entry || GLOB.km_attr_b || cur_b, seg)
	else
		note(cur, cur_a, cur_b, seg)

/// A region of `cat` begins (`a`: the owner's type or a constant text, `b`: the proc, an entry or a constant text). Returns the token that leave() takes.
/datum/km_ledger/proc/enter(cat, a = null, b = null, now = TICK_USAGE)
	if(!active)
		return 0
	var/ms = now * world.tick_lag
	charge_segment(ms)
	cursor = max(cursor, ms)
	if(depth >= KM_LEDGER_DEPTH)
		too_deep++
		return depth
	var/token = depth
	depth++
	stack_cat[depth] = cur
	stack_a[depth] = cur_a
	stack_b[depth] = cur_b
	cur = cat
	cur_a = a
	cur_b = b
	counts[cat]++
	return token

/// The region entered with `token` ends (and any region inside it that never got its own leave).
/datum/km_ledger/proc/leave(token, now = TICK_USAGE)
	if(!active)
		return
	var/ms = now * world.tick_lag
	charge_segment(ms)
	cursor = max(cursor, ms)
	if(depth <= token)
		return
	var/base = token + 1
	cur = stack_cat[base]
	cur_a = stack_a[base]
	cur_b = stack_b[base]
	depth = token

/// The kernel's iteration is over: `now` is TICK_USAGE, `usage` the tick's usage the performance record takes (never less). The tail up to it is the
/// residual's; the window is folded into the totals, the moving averages and the rows' pruning. Returns the window in ms.
/datum/km_ledger/proc/finish(now = TICK_USAGE, usage = TICK_USAGE)
	if(!active)
		return 0
	var/ms = now * world.tick_lag
	charge_segment(ms)
	cursor = max(cursor, ms)
	// Whatever is open is closed into the residual: the timeline ends in the base category.
	depth = 0
	cur = KM_CAT_UNATTRIBUTED
	cur_a = "kernel"
	cur_b = "between marked regions"
	charge_segment(usage * world.tick_lag)
	cursor = max(cursor, usage * world.tick_lag)
	var/window = cursor
	active = FALSE
	if(!started_real)
		started_real = max(REALTIMEOFDAY, 1)
	ticks++
	last_window_ms = window
	window_lo += window
	if(window_lo >= KM_FLUSH_MS)
		window_lo -= KM_FLUSH_MS
		window_hi += KM_FLUSH_MS
	window_ema += (window - window_ema) * KM_LEDGER_EMA
	for(var/i in 1 to KM_CAT_COUNT)
		var/v = tick_ms[i]
		if(v)
			var/low = lo[i] + v
			if(low >= KM_FLUSH_MS)
				low -= KM_FLUSH_MS
				hi[i] += KM_FLUSH_MS
			lo[i] = low
		ema[i] += (v - ema[i]) * KM_LEDGER_EMA
		tick_ms[i] = 0
		if(needs_prune[i])
			prune(i)
	return window

/// A BYOND tick ended (/datum/tick_frame/frame_end()): `post_ms` is what ran after the kernel's iteration, `map_ms` the map send, and `kernel_ran` whether
/// the kernel closed this tick (a tick it did not close counts whole as `post_ms` of idle).
/datum/km_ledger/proc/note_outside(post_ms, map_ms, kernel_ran)
	world_ticks++
	if(kernel_ran)
		post_lo += post_ms
		if(post_lo >= KM_FLUSH_MS)
			post_lo -= KM_FLUSH_MS
			post_hi += KM_FLUSH_MS
		post_ema += (post_ms - post_ema) * KM_LEDGER_EMA
		idle_ema -= idle_ema * KM_LEDGER_EMA
	else
		idle_lo += post_ms
		if(idle_lo >= KM_FLUSH_MS)
			idle_lo -= KM_FLUSH_MS
			idle_hi += KM_FLUSH_MS
		idle_ema += (post_ms - idle_ema) * KM_LEDGER_EMA
		post_ema -= post_ema * KM_LEDGER_EMA
	map_lo += map_ms
	if(map_lo >= KM_FLUSH_MS)
		map_lo -= KM_FLUSH_MS
		map_hi += KM_FLUSH_MS
	map_ema += (map_ms - map_ema) * KM_LEDGER_EMA

// ---------------------------------------------------------------- rows

/// Charges `ms` to the row (cat, a, b), making it on first sight. A category past KM_LEDGER_ROWS names lands on its "(other)" row.
/datum/km_ledger/proc/note(cat, a, b, ms)
	if(isnull(a))
		a = "-"
	if(isnull(b))
		b = "-"
	var/list/by_a = rows[cat][a]
	var/list/row
	if(by_a)
		row = by_a[b]
	if(!row)
		row = add_row(cat, a, b)
	row[KL_COUNT]++
	var/low = row[KL_MS] + ms
	if(low >= KM_FLUSH_MS)
		low -= KM_FLUSH_MS
		row[KL_MS_HI] += KM_FLUSH_MS
	row[KL_MS] = low
	if(ms > row[KL_MAX])
		row[KL_MAX] = ms

/datum/km_ledger/proc/add_row(cat, a, b)
	var/list/cat_rows = rows[cat]
	if(n_rows[cat] >= KM_LEDGER_ROWS)
		needs_prune[cat] = TRUE
		overflowed++
		a = "(other)"
		b = "(other)"
	var/list/by_a = cat_rows[a]
	if(!by_a)
		by_a = list()
		cat_rows[a] = by_a
	var/list/row = by_a[b]
	if(!row)
		row = list(0, 0, 0, 0)
		by_a[b] = row
		n_rows[cat]++
	return row

/// A category past its bound drops the cheaper half of its rows (by total ms) at the end of a tick, so the heavy names stay.
/datum/km_ledger/proc/prune(cat)
	needs_prune[cat] = FALSE
	prunes++
	var/list/cat_rows = rows[cat]
	var/list/totals = list()
	for(var/a in cat_rows)
		var/list/by_a = cat_rows[a]
		for(var/b in by_a)
			var/list/row = by_a[b]
			totals += row[KL_MS] + row[KL_MS_HI]
	if(!length(totals))
		return
	totals = sortTim(totals, GLOBAL_PROC_REF(cmp_numeric_asc))
	var/cut = totals[max(1, round(length(totals) / 2))]
	var/list/dead_a = list()
	for(var/a in cat_rows)
		var/list/by_a = cat_rows[a]
		var/list/drop = list()
		for(var/b in by_a)
			var/list/row = by_a[b]
			if(row[KL_MS] + row[KL_MS_HI] <= cut && a != "(other)")
				drop += b
		for(var/b in drop)
			by_a -= b
			n_rows[cat]--
		if(!length(by_a))
			dead_a += a
	for(var/a in dead_a)
		cat_rows -= a

/// How a row's name reads: "/obj/machinery/light -> process", the owner alone when there is no proc.
/proc/km_ledger_describe(a, b)
	if(istype(b, /datum/entry))
		var/datum/entry/E = b
		b = "[E.kind]: [copytext(E.sig, 1, 100)]"
	if(b == "-")
		return "[a]"
	if(a == "-")
		return "[b]"
	return "[a] -> [b]"

/// The heaviest `n` names of category `cat` as list(list("source", count, total ms, max ms), ...). Allocates: reporting only.
/datum/km_ledger/proc/top_of(cat, n = KM_LEDGER_TOP)
	var/list/cat_rows = rows[cat]
	var/list/best = list()
	for(var/a in cat_rows)
		var/list/by_a = cat_rows[a]
		for(var/b in by_a)
			var/list/row = by_a[b]
			var/total = row[KL_MS] + row[KL_MS_HI]
			if(length(best) >= n && total <= best[length(best)][3])
				continue
			var/at = length(best) + 1
			while(at > 1 && best[at - 1][3] < total)
				at--
			best.Insert(at, list(list(a, b, total, row[KL_COUNT], row[KL_MAX])))
			if(length(best) > n)
				best.Cut(n + 1)
	var/list/out = list()
	for(var/list/row as anything in best)
		out += list(list(km_ledger_describe(row[1], row[2]), row[4], round(row[3], 0.01), round(row[5], 0.01)))
	return out

// ---------------------------------------------------------------- reading it

/// Category index -> list(key, label).
GLOBAL_LIST_INIT(km_cat_names, list(
	list("unattributed", "Not attributed (kernel loop between marked regions)"),
	list("byond_pre", "BYOND before the kernel (verbs, input, resumed procs)"),
	list("input", "Input (inbox resolve, verbs)"),
	list("kernel", "Kernel walking (phase lists, deadline wheel, slots)"),
	list("system", "System work items"),
	list("timers", "Timers: after(), every(), after_init()"),
	list("stat_drain", "Stat drain (marked recomputes)"),
	list("stat_eval", "Stat evaluations"),
	list("on_change", "on_change hooks"),
	list("notices", "Late notices"),
	list("reactions", "Change reactions (appearance drain)"),
	list("draws", "Redraws"),
	list("native", "Native frame (Rust world step)"),
	list("native_delivery", "Native delivery (changed, notices, crossings)"),
	list("lighting", "Lighting, shadows, overlays, skybox"),
	list("movement", "Movement (Move)"),
	list("garbage", "Garbage collection"),
	list("sched", "Scheduler passes (begin, end, wheel, lanes)"),
))

/proc/km_ledger_names()
	return GLOB.km_cat_names

/// The ledger as data for the MC Health panel, the Tick Report and PERF_PROFILE: per category its moving average, its mean per tick since boot,
/// its total and the heaviest `top_n` names; what BYOND spent outside the window; the kernel's phases. `windows` adds up to `window_avg_ms`.
/datum/km_ledger/proc/report(top_n = KM_LEDGER_TOP)
	var/datum/km_ledger_walk/W = walk_begin(top_n)
	walk_step(W, INFINITY)
	return walk_result(W)

/// A report() being built a category at a time: the profiler builds one a minute, and ranking every category's rows held one tick for tens of ms.
/// The categories' numbers are read as each is reached (a window closing between two of them is the same smear the panel's own reads have).
/datum/km_ledger_walk
	var/top_n = KM_LEDGER_TOP
	var/at = 1
	var/sum = 0
	var/list/cats
	/// The category being ranked: its table, the owner keys (a snapshot) and the next one, the current owner's table and keys, and the heaviest rows so far.
	/// One category can hold thousands of rows, so the ranking is a slice at a time too.
	var/in_cat = FALSE
	var/list/cat_table
	var/list/a_keys
	var/a_at = 1
	var/cur_a
	var/list/b_table
	var/list/b_keys
	var/b_at = 1
	var/list/best

/datum/km_ledger/proc/walk_begin(top_n = KM_LEDGER_TOP)
	var/datum/km_ledger_walk/W = new
	W.top_n = top_n
	W.cats = list()
	return W

/// Ranks categories for `budget_ms`, checked every KA_WALK_CHECK_ROWS rows. TRUE when every category is in.
/datum/km_ledger/proc/walk_step(datum/km_ledger_walk/W, budget_ms)
	var/list/names = km_ledger_names()
	var/n = max(ticks, 1)
	var/started = TICK_USAGE_REAL
	while(W.at <= KM_CAT_COUNT)
		var/i = W.at
		if(!W.in_cat)
			W.in_cat = TRUE
			W.best = list()
			W.b_keys = null
			W.a_at = 1
			W.cat_table = (i == KM_CAT_UNATTRIBUTED || i == KM_CAT_BYOND_PRE) ? null : rows[i]
			W.a_keys = W.cat_table ? W.cat_table.Copy() : list()
		if(!rank_slice(W, started, budget_ms))
			return FALSE
		var/total = lo[i] + hi[i]
		W.sum += total
		var/list/top = list()
		for(var/list/row as anything in W.best)
			top += list(list(km_ledger_describe(row[1], row[2]), row[4], round(row[3], 0.01), round(row[5], 0.01)))
		W.cats += list(list(
			"key" = names[i][1],
			"label" = names[i][2],
			"ema_ms" = round(ema[i], 0.001),
			"avg_ms" = round(total / n, 0.001),
			"total_ms" = round(total, 0.01),
			"count" = counts[i],
			"top" = top,
		))
		W.at++
		W.in_cat = FALSE
		if(W.at <= KM_CAT_COUNT && TICK_DELTA_TO_MS(TICK_USAGE_REAL - started) >= budget_ms)
			return FALSE
	return TRUE

/// Ranks the rest of the current category's rows into W.best. TRUE when they are all in, FALSE when `budget_ms` since `started` is spent.
/datum/km_ledger/proc/rank_slice(datum/km_ledger_walk/W, started, budget_ms)
	var/since_check = 0
	var/n = W.top_n
	var/list/best = W.best
	while(W.b_keys || W.a_at <= length(W.a_keys))
		if(!W.b_keys)
			W.cur_a = W.a_keys[W.a_at++]
			W.b_table = W.cat_table[W.cur_a]
			if(!W.b_table)
				continue
			W.b_keys = W.b_table.Copy()
			W.b_at = 1
		var/list/b_keys = W.b_keys
		while(W.b_at <= length(b_keys))
			var/b = b_keys[W.b_at++]
			var/list/row = W.b_table[b]
			if(row)
				var/total = row[KL_MS] + row[KL_MS_HI]
				if(length(best) < n || total > best[length(best)][3])
					var/at = length(best) + 1
					while(at > 1 && best[at - 1][3] < total)
						at--
					best.Insert(at, list(list(W.cur_a, b, total, row[KL_COUNT], row[KL_MAX])))
					if(length(best) > n)
						best.Cut(n + 1)
			if(!(++since_check % KA_WALK_CHECK_ROWS) && TICK_DELTA_TO_MS(TICK_USAGE_REAL - started) >= budget_ms)
				if(W.b_at > length(b_keys))
					W.b_keys = null
				return FALSE
		W.b_keys = null
	return TRUE

/// The finished walk as report() returns it.
/datum/km_ledger/proc/walk_result(datum/km_ledger_walk/W)
	var/n = max(ticks, 1)
	var/list/cats = W.cats
	var/sum = W.sum
	var/window_total = window_lo + window_hi
	var/list/phases = list()
	var/kernel_ticks = max(Kernel.ticks, 1)
	var/list/letters = KERNEL_PHASE_LETTERS
	for(var/p in 1 to KERNEL_PHASE_COUNT)
		phases += list(list("phase" = letters[p], "avg_ms" = round(Kernel.phase_ms_total[p] / kernel_ticks, 0.001), "last_ms" = round(Kernel.phase_ms_last[p], 0.001)))
	var/seconds = started_real ? max((REALTIMEOFDAY - started_real) * 0.1, 0.1) : 0.1
	return list(
		"ticks" = ticks,
		"world_ticks" = world_ticks,
		"budget_ms" = world.tick_lag * 100,
		"window_ema_ms" = round(window_ema, 0.001),
		"window_avg_ms" = round(window_total / n, 0.001),
		"window_total_ms" = round(window_total, 0.01),
		"categories_total_ms" = round(sum, 0.01),
		"seconds" = round(seconds, 0.1),
		"too_deep" = too_deep,
		"rows" = n_rows.Copy(),
		"prunes" = prunes,
		"overflowed" = overflowed,
		"outside" = list(
			"post_ema_ms" = round(post_ema, 0.001),
			"post_avg_ms" = round((post_lo + post_hi) / max(world_ticks, 1), 0.001),
			"idle_ema_ms" = round(idle_ema, 0.001),
			"idle_avg_ms" = round((idle_lo + idle_hi) / max(world_ticks, 1), 0.001),
			"map_ema_ms" = round(map_ema, 0.001),
			"map_avg_ms" = round((map_lo + map_hi) / max(world_ticks, 1), 0.001),
		),
		"phases" = phases,
		"categories" = cats,
	)

/// What ran outside the kernel's iteration per BYOND tick since the last call (the profile's own window), where "outside" in report() is the mean since boot: a
/// round start that held every tick for minutes (a login, a spawn) kept that mean at 17 ms a tick for the rest of a quiet round. Only the profiler calls it.
/datum/km_ledger/proc/outside_since_mark()
	var/post = post_lo + post_hi
	var/idle = idle_lo + idle_hi
	var/ticks_since = max(world_ticks - mark_world_ticks, 1)
	. = list(
		"recent_ticks" = world_ticks - mark_world_ticks,
		"post_recent_ms" = round((post - mark_post) / ticks_since, 0.001),
		"idle_recent_ms" = round((idle - mark_idle) / ticks_since, 0.001),
	)
	mark_world_ticks = world_ticks
	mark_post = post
	mark_idle = idle

/// The ledger as the lines of an HTML table (the Tick Report).
/datum/km_ledger/proc/report_html()
	var/list/data = report(3)
	var/html = "<h3>Where the tick goes (kernel iteration, [data["ticks"]] ticks, mean [data["window_avg_ms"]] ms of [data["budget_ms"]])</h3>"
	html += "<table border='1' cellspacing='0' cellpadding='3'><tr><th>Category</th><th>Now ms</th><th>Mean ms</th><th>Calls</th><th>Heaviest</th></tr>"
	for(var/list/cat as anything in data["categories"])
		var/list/tops = list()
		for(var/list/row as anything in cat["top"])
			tops += "[html_encode(row[1])] [row[3]] ms ([row[2]]x)"
		html += "<tr><td>[html_encode(cat["label"])]</td><td>[cat["ema_ms"]]</td><td>[cat["avg_ms"]]</td><td>[cat["count"]]</td><td>[jointext(tops, "<br>")]</td></tr>"
	var/list/outside = data["outside"]
	html += "<tr><td>After the kernel in the same tick (resumed procs, /world/Tick)</td><td>[outside["post_ema_ms"]]</td><td>[outside["post_avg_ms"]]</td><td></td><td></td></tr>"
	html += "<tr><td>Map send (BYOND maptick)</td><td>[outside["map_ema_ms"]]</td><td>[outside["map_avg_ms"]]</td><td></td><td></td></tr>"
	html += "</table>"
	return html

// ---------------------------------------------------------------- the calls the work sites make

/// Begins a region of `cat` on the one ledger; the value goes to km_ledger_leave().
/proc/km_ledger_enter(cat, a = null, b = null)
	return GLOB.km_ledger.enter(cat, a, b)

/// Ends the region km_ledger_enter() began.
/proc/km_ledger_leave(token)
	GLOB.km_ledger.leave(token)

/// The ledger category a work item of `owner_type` is charged to: the scheduler's own pieces, input, garbage, lighting and movement have their own;
/// everything else is system work, named by the item's key. Paths are text so the kernel names no content type.
/proc/km_ledger_item_category(owner_type)
	var/list/by_path = GLOB.km_item_categories
	return by_path["[owner_type]"] || KM_CAT_SYSTEM

GLOBAL_LIST_INIT(km_item_categories, list(
	"/datum/system/behaviours" = KM_CAT_SCHED,
	"/datum/system/input" = KM_CAT_INPUT,
	"/datum/system/garbage" = KM_CAT_GARBAGE,
	"/datum/system/lighting" = KM_CAT_LIGHTING,
	"/datum/system/overlays" = KM_CAT_LIGHTING,
	"/datum/system/skybox" = KM_CAT_LIGHTING,
	"/datum/system/vis_overlays" = KM_CAT_LIGHTING,
	"/datum/system/projectile_steps" = KM_CAT_MOVEMENT,
	"/datum/system/point_steps" = KM_CAT_MOVEMENT,
	"/datum/system/throw_steps" = KM_CAT_MOVEMENT,
))
