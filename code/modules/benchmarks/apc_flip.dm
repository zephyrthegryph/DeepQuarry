// E3's phase 1 spike (doc/rewrite/final_api.html, section 7 "Inline recompute is measured, not assumed"; section 19 "E3, stats"):
// one APC channel flips with 50 dependent machines. The same flip, three ways:
//
//   old     the legacy shape: the APC walks its machines and each one runs the body of power_change() (set_powered, changed, the event, heat);
//   inline  each machine's stat is a hop reader settled inline on the flip (the forced settle rule SETTLE_INLINE);
//   marked  each is marked by the flip and recomputed by the marked drain (the rule a collection edge gets: SETTLE_MARKED).
//
// Run: tools/build/build.sh bench --scenario=apc_flip_50 [--bench_flips=2000] [--bench_loads=50]
// The pass condition (section 19, phase 1 gate): inline recompute at or under the old path.

/// The old path's machine: a real machine taking the body of power_change() that follows the area lookup (the area answers `on`):
/// set_powered() writes NOPOWER and publishes, changed() marks it, the power event goes out, the heat output updates.
/obj/machinery/dx_bench_drawer/proc/old_power_change(on)
	if(!set_powered(on))
		return FALSE
	changed(src)
	if(has_stat(NOPOWER))
		PUBLISH_LEGACY(src, /datum/notice/machinery_power_lost)
	else
		PUBLISH_LEGACY(src, /datum/notice/machinery_power_restored)
	update_heat_output()
	return TRUE

/datum/benchmark/apc_flip_50
	id = "apc_flip_50"
	description = "One APC channel flip over N dependent machines: the old path, inline recompute, and marked recompute with its drain"

/datum/benchmark/apc_flip_50/Run()
	var/loads_n = param("loads", 50)
	var/flips = param("flips", 2000)
	// The old path: real machines, the body of power_change().
	var/list/old_loads = list()
	var/turf/origin = locate(10, 10, 1)
	for(var/i in 1 to loads_n)
		old_loads += new /obj/machinery/dx_bench_drawer(locate(origin.x + (i % 20), origin.y + round(i / 20), origin.z))
	begin_window()
	var/old_start = REALTIMEOFDAY
	var/on = TRUE
	for(var/f in 1 to flips)
		on = !on
		for(var/obj/machinery/dx_bench_drawer/L as anything in old_loads)
			L.old_power_change(on)
	var/old_ms = (REALTIMEOFDAY - old_start) * 100
	end_window("old")
	for(var/obj/machinery/dx_bench_drawer/L as anything in old_loads)
		qdel(L)
	refresh_flush()
	// The stat path: the same count of readers of one APC channel.
	var/obj/e3_apc/A = new
	var/list/loads = list()
	for(var/i in 1 to loads_n)
		var/obj/e3_load/L = new
		rel_set(L, "apc", A)
		loads += L
	// Inline.
	GLOB.stat_force_settle = SETTLE_INLINE
	begin_window()
	var/evals_before = GLOB.stat_evals
	var/inline_start = REALTIMEOFDAY
	on = TRUE
	for(var/f in 1 to flips)
		on = !on
		A.set_channel_on(on)
	var/inline_ms = (REALTIMEOFDAY - inline_start) * 100
	var/inline_evals = GLOB.stat_evals - evals_before
	end_window("inline")
	// Marked, drained with the lane budget lifted so the number is the recompute cost, not the spill.
	GLOB.stat_force_settle = SETTLE_MARKED
	evals_before = GLOB.stat_evals
	var/marked_start = REALTIMEOFDAY
	on = TRUE
	for(var/f in 1 to flips)
		on = !on
		A.set_channel_on(on)
		stat_drain_marked(LANE_SIMULATION)
	var/marked_ms = (REALTIMEOFDAY - marked_start) * 100
	var/marked_evals = GLOB.stat_evals - evals_before
	GLOB.stat_force_settle = null
	metric("old_ms_per_flip", old_ms / flips, "ms")
	metric("inline_ms_per_flip", inline_ms / flips, "ms")
	metric("marked_ms_per_flip", marked_ms / flips, "ms")
	count_metric("inline_recomputes_per_flip", inline_evals / flips, "recomputes")
	count_metric("marked_recomputes_per_flip", marked_evals / flips, "recomputes")
	count_metric("loads", loads_n, "machines")
	for(var/obj/e3_load/L as anything in loads)
		qdel(L)
	qdel(A)
