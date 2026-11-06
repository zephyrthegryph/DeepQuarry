// Kernel measurement: the slow-tick trace.
//
// The overrun line (meter.dm) names the top three systems of a tick and the top callbacks behind sched_core; a tick that
// takes seconds needs more: every piece of work that ran in it, by what it was, with its time, and the time that no
// piece accounts for. This keeps that. While a tick runs, the places that time a piece of work add a span to a fixed
// ring (span(): four list writes, no string built: the name is a key that already exists). When the tick closes over the
// threshold (config slow_tick_trace_percent, default 200% of a tick, 0 = off) trace() joins the spans with the tick meter's
// own records (systems charged, timer callbacks, reactions, redraws), the kernel's view of the tick (the phases, what ran
// outside them) and the native frame's parts, ranks them by ms and writes ONE line to the debug log (not the runtime log):
//   SLOW_TICK 1840% (920ms, t=5120, maptick 3ms) | pre-MC 3.1 | kernel.tick 900 (...) | after tick 17 | phases K=2.1 N=410 ... | top: ...
// A phase's time that its itemised work does not cover is a row of its own ("phase N time not itemised"), so unattributed
// time is shown where it happened instead of as "MC other". Below the threshold a tick costs the spans only; nothing is built.

/datum/slow_tick
	/// Percent of a tick a closed tick must pass to be traced; 0 is off.
	var/threshold = KM_SLOW_TRACE_PERCENT
	/// The ring of this tick's spans (fixed size KM_SLOW_SPANS); the first `n` are live.
	var/list/span_kind
	var/list/span_name
	var/list/span_phase
	var/list/span_ms
	var/n = 0
	/// Spans that did not fit this tick, and the smallest ms held once the ring is full.
	var/dropped = 0
	var/floor_ms = 0
	/// The kernel's view of this tick (note_kernel()), null when it was not asked for.
	var/list/kview
	/// Traces made, held back by the per-minute limit, and the window that limit counts in.
	var/traces = 0
	var/held_back = 0
	var/window_start = 0
	var/window_lines = 0
	/// The last trace made: its text, and its ranked rows as list(kind, name, ms, phase).
	var/last_trace
	var/list/last_rows

/datum/slow_tick/New()
	span_kind = new /list(KM_SLOW_SPANS)
	span_name = new /list(KM_SLOW_SPANS)
	span_phase = new /list(KM_SLOW_SPANS)
	span_ms = new /list(KM_SLOW_SPANS)

/// Records one piece of work that took `ms` (finished now). The hot call: list writes only. A full ring keeps the heaviest.
/datum/slow_tick/proc/span(kind, name, ms, phase = 0)
	var/at
	if(n < KM_SLOW_SPANS)
		at = ++n
	else
		dropped++
		if(ms <= floor_ms)
			return
		at = 1
		for(var/i in 2 to KM_SLOW_SPANS)
			if(span_ms[i] < span_ms[at])
				at = i
	span_kind[at] = kind
	span_name[at] = name
	span_phase[at] = phase
	span_ms[at] = ms
	if(n >= KM_SLOW_SPANS)
		var/low = span_ms[1]
		for(var/i in 2 to KM_SLOW_SPANS)
			if(span_ms[i] < low)
				low = span_ms[i]
		floor_ms = low

/// The tick is over (traced or not): the next starts empty.
/datum/slow_tick/proc/clear()
	n = 0
	dropped = 0
	floor_ms = 0
	kview = null

/// What the kernel knows of this tick that the meter does not: `phase_ms` (K S N U D P R G, ms), the sizes of the tick's parts in ms
/// (total, before the MC, the kernel.tick() call, the scheduler's own pieces) and the native frame's parts as name -> ms. Called only
/// on a tick that will be traced, so it may allocate.
/datum/slow_tick/proc/note_kernel(list/phase_ms, total_ms, pre_ms, kernel_ms, sched_ms, list/native)
	kview = list("phase_ms" = phase_ms.Copy(), "total_ms" = total_ms, "pre_ms" = pre_ms, "kernel_ms" = kernel_ms, "sched_ms" = sched_ms, "native" = native)

/proc/km_span_kind_name(kind)
	switch(kind)
		if(KM_SPAN_ITEM)
			return "item"
		if(KM_SPAN_SYSTEM)
			return "system"
		if(KM_SPAN_ATTR)
			return "callback"
		if(KM_SPAN_NATIVE)
			return "native"
		if(KM_SPAN_LOOP)
			return "loop"
		if(KM_SPAN_REST)
			return "rest"
		if(KM_SPAN_STEP)
			return "step"
		if(KM_SPAN_DRAIN)
			return "drain"
		if(KM_SPAN_INNER)
			return "inner"
	return "?"

/proc/cmp_slow_row_ms_dsc(list/a, list/b)
	return b[3] - a[3]

/// Joins the spans with the meter's records and writes the trace if the rate limit allows. Returns the text (also in last_trace),
/// or null when the limit held it back. Allocates: the exception, never the tick path.
/datum/slow_tick/proc/trace(datum/tick_meter/meter, usage, maptick)
	var/list/rows = list()
	var/list/item_by_phase = new /list(KERNEL_PHASE_COUNT)
	for(var/i in 1 to n)
		var/kind = span_kind[i]
		var/phase = span_phase[i]
		rows += list(list(km_span_kind_name(kind), "[span_name[i]]", span_ms[i], phase))
		if((kind == KM_SPAN_ITEM || kind == KM_SPAN_DRAIN) && phase >= 1 && phase <= KERNEL_PHASE_COUNT)
			item_by_phase[phase] = (item_by_phase[phase] || 0) + span_ms[i]
	var/datum/km_systems/registry = km_systems()
	for(var/i in 1 to meter.n_touched)
		var/idx = meter.touched[i]
		rows += list(list("system", "[registry.keys[idx]]", meter.tick_ms[idx], 0))
	for(var/list/row as anything in meter.attr.select_top(KM_SLOW_TRACE_TOP, KA_BY_TICK))
		rows += list(list(km_attr_kind_name(row[KA_KIND]), km_attr_describe(row), row[KA_TMS], 0))
	var/header = ""
	if(kview)
		var/list/phase_ms = kview["phase_ms"]
		var/list/parts = list()
		var/phase_total = 0
		for(var/p in 1 to KERNEL_PHASE_COUNT)
			var/ms = phase_ms[p] || 0
			phase_total += ms
			if(ms >= 0.05)
				parts += "[phase_letter(p)]=[round(ms, 0.1)]"
			// Time in the phase that its itemised work (spans of KM_SLOW_SPAN_MIN_MS or more) does not cover: small items, list walks, host services.
			var/rest = ms - (item_by_phase[p] || 0)
			if(rest >= KM_SLOW_TRACE_REST_MS)
				rows += list(list("rest", "phase [phase_letter(p)] time not itemised", rest, p))
		var/pre_ms = kview["pre_ms"]
		var/kernel_ms = kview["kernel_ms"]
		var/outside = max(kview["total_ms"] - pre_ms - kernel_ms, 0)
		if(outside >= KM_SLOW_TRACE_REST_MS)
			rows += list(list("rest", "after kernel.tick (loop work, the record, time the tick ran on before it closed)", outside, 0))
		if(pre_ms >= KM_SLOW_TRACE_REST_MS)
			rows += list(list("rest", "before the MC (other procs resumed ahead of the kernel loop)", pre_ms, 0))
		var/between = kernel_ms - phase_total
		if(between >= KM_SLOW_TRACE_REST_MS)
			rows += list(list("rest", "kernel.tick between phases (scheduler pass begin/end, stat drains)", between, 0))
		var/list/native = kview["native"]
		for(var/name in native)
			if(native[name] >= 0.05)
				rows += list(list("native", "[name]", native[name], KERNEL_PHASE_N))
		header = " | pre-MC [round(pre_ms, 0.1)] | kernel.tick [round(kernel_ms, 0.1)] (scheduler pieces [round(kview["sched_ms"], 0.1)]) | after tick [round(outside, 0.1)] | phases [jointext(parts, " ")]"
	rows = sortTim(rows, GLOBAL_PROC_REF(cmp_slow_row_ms_dsc))
	if(length(rows) > KM_SLOW_TRACE_TOP)
		rows.Cut(KM_SLOW_TRACE_TOP + 1)
	var/list/shown = list()
	for(var/list/row as anything in rows)
		shown += "[row[1]] [row[2]] [round(row[3], 0.1)]ms"
	var/text = "SLOW_TICK [round(usage)]% ([round(TICK_DELTA_TO_MS(usage))]ms, t=[world.time], maptick [round(TICK_DELTA_TO_MS(maptick), 0.1)]ms)[header] | [n] spans[dropped ? " ([dropped] dropped)" : ""] | top: [length(shown) ? jointext(shown, "; ") : "nothing recorded"]"
	last_trace = text
	last_rows = rows
	traces++
	if(abs(REALTIMEOFDAY - window_start) >= 1 MINUTES)
		window_start = REALTIMEOFDAY
		window_lines = 0
	if(window_lines >= KM_SLOW_TRACE_PER_MINUTE)
		held_back++
		return null
	window_lines++
	if(held_back)
		text += " (+[held_back] slow ticks not written this minute)"
		held_back = 0
	logger.Log(LOG_CATEGORY_DEBUG, text, list("usage" = usage, "spans" = rows))
	return text

/// Before the meter closes the tick: refreshes the threshold from config now and then, and hands a tick that will be traced the kernel's view of it.
/datum/controller/kernel/proc/slow_tick_prepare(datum/tick_meter/meter, usage)
	var/datum/slow_tick/S = meter.slow
	if(!(perf_samples_total % KM_SLOW_TRACE_REFRESH_TICKS))
		S.threshold = CONFIG_GET(number/slow_tick_trace_percent)
	if(!S.threshold || usage <= S.threshold)
		return
	var/list/native
	if(last_native == world.time)
		var/datum/system/native/N = native_system()
		native = alist("vg_frame" = N.last_vg_ms, "delivery changed" = N.delivery_changed_ms, "delivery notices" = N.delivery_notices_ms, "delivery crossed" = N.delivery_crossed_ms)
		if(N.last_slowest_ms >= 1)
			native["slowest record: [N.last_slowest]"] = N.last_slowest_ms
	var/list/step = sched?.slow_step
	if(step && step["world_time"] == world.time)
		S.span(KM_SPAN_STEP, "[step["kind"]] [step["behaviour"]] on [step["entity"]] ([step["name"]])", step["ms"] || 0)
	S.note_kernel(phase_ms_last, TICK_DELTA_TO_MS(usage), TICK_DELTA_TO_MS(perf_tick_start_usage), last_tick_ms, sched_ms_tick, native)
