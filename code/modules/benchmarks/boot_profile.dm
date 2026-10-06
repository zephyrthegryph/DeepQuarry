// Boot and bulk-destroy profiling (doc/rewrite/init_and_turfs.md).
//
// boot_profile: per-subsystem init times, and with -DBENCHMARK_DEEP_PROFILE
// the per-type cost of Initialize(), materialize and the after_init() pass across
// the whole boot. With --profile the BYOND proc profiler runs from the
// Profiler subsystem's init (before map load) and its dump covers boot.
//
// explosion_dense: one large explosion (devastation 7) centred on the most
// furnished station block. The explosion subsystem's own phase timers, the
// destroy-transaction phases (exclusive of nested deletions, deep profile
// only), the garbage per-type deltas and the window's subsystem costs.
//
// Run on Southern Cross:
//   tools/build/build.sh bench -DCITESTING_FULL_MAP --scenario=boot_profile,explosion_dense --runs=3 --warmup=0
//   tools/build/build.sh bench -DCITESTING_FULL_MAP -DBENCHMARK_DEEP_PROFILE --profile --scenario=boot_profile,explosion_dense --runs=3 --warmup=0

// ---- Deep-profile instrumentation state (only touched with -DBENCHMARK_DEEP_PROFILE) ----

/// Timing frames for nested InitAtom()/after_init() calls. Initialize()
/// often creates and initializes other atoms, so each frame subtracts its
/// children to report self time.
/datum/benchmark_init_stats
	/// type -> list(count, init_self_us, materialize_self_us, late_count, late_self_us, inclusive_us, max_self_us)
	var/list/by_type = list()
	var/depth = 0
	/// child microseconds accumulated per depth
	var/list/child_us = list()
	/// qdel frames: child ms per depth and child ms at the last phase boundary
	var/qdel_depth = 0
	var/list/qdel_child_ms = list()
	var/list/qdel_phase_mark_ms = list()
	/// LIFECYCLE_PHASE_* id -> exclusive ms (children's time subtracted)
	var/list/phase_self_ms = list()
	/// type -> list(qdels, self ms)
	var/list/qdel_by_type = list()

GLOBAL_DATUM_INIT(bench_init_stats, /datum/benchmark_init_stats, new)

/// Rust heap marks through boot: list(name, current MB, peak MB, parts), where
/// parts are Rust structures above 1 MB (empty until the shared World binds a
/// memory report). The peak is process-wide and monotonic, so
/// the first mark whose peak jumps names the stage that set it.
GLOBAL_LIST_EMPTY(benchmark_rust_marks)

/// Marks once a second for `seconds`, naming the subsystems that fired
/// since the previous mark and their cost, to place growth after round start.
/proc/benchmark_mark_seconds(seconds)
	// Keyed by subsystem type text: a deferred call's arguments may not hold datum assoc keys.
	var/list/fired = list()
	for(var/datum/system/S as anything in kernel_pure_systems())
		fired["[S.type]"] = S.times_fired
	// A mark a second, on timers (nothing sleeps).
	after(null, 1 SECONDS, GLOBAL_PROC_REF(benchmark_mark_second), with = list(list(fired), 1, seconds))

/proc/benchmark_mark_second(list/fired_box, i, seconds)
	var/list/fired = fired_box[1]
	var/list/names = list()
	for(var/datum/system/S as anything in kernel_pure_systems())
		var/key = "[S.type]"
		var/delta = S.times_fired - fired[key]
		if(delta > 0)
			names += "[S.name] x[delta] ([round(S.fire_cost, 0.1)] ms)"
		fired[key] = S.times_fired
	benchmark_rust_mark("t+[i]s: [jointext(names, ", ")]")
	if(i < seconds)
		after(null, 1 SECONDS, GLOBAL_PROC_REF(benchmark_mark_second), with = list(fired_box, i + 1, seconds))

/proc/benchmark_rust_mark(name)
	var/list/heap = vg_verdigris_allocator_diagnostics()
	if(!islist(heap))
		return
	// Per-structure parts need a Rust memory report, which the shared World (rust-core2)
	// does not bind yet: the marks carry the allocator totals only.
	var/list/parts = list()
	var/list/process = benchmark_process_memory()
	GLOB.benchmark_rust_marks += list(list(
		"name" = name,
		"private_mb" = islist(process) ? process["private_mb"] : null,
		"current_mb" = round(heap[1] / 1048576, 0.1),
		"peak_mb" = round(heap[2] / 1048576, 0.1),
		"parts" = parts,
	))
	// Also in the log: a boot whose scenario never starts still keeps its marks.
	log_world("BENCH_RUST_MARK [name]: current [round(heap[1] / 1048576, 0.1)] MB, peak [round(heap[2] / 1048576, 0.1)] MB, private [islist(process) ? process["private_mb"] : "?"] MB")

/proc/benchmark_init_frame_begin()
	var/datum/benchmark_init_stats/S = GLOB.bench_init_stats
	if(!S)
		return 0
	var/d = ++S.depth
	if(length(S.child_us) < d)
		S.child_us.len = d
	S.child_us[d] = 0
	rustg_time_reset("bench_init_[d]")
	return d

/// Marks the end of Initialize() inside a frame: list(elapsed_us, child_us so far).
/proc/benchmark_init_frame_mark(d)
	var/datum/benchmark_init_stats/S = GLOB.bench_init_stats
	if(!S || !d)
		return null
	return list(rustg_time_microseconds("bench_init_[d]"), S.child_us[d])

/proc/benchmark_init_frame_end(d, type, list/mark)
	var/datum/benchmark_init_stats/S = GLOB.bench_init_stats
	if(!S || !d || !mark)
		return
	var/total = rustg_time_microseconds("bench_init_[d]")
	var/children = S.child_us[d]
	var/init_self = mark[1] - mark[2]
	var/post_self = (total - mark[1]) - (children - mark[2])
	var/list/row = S.by_type[type]
	if(!row)
		row = S.by_type[type] = list(0, 0, 0, 0, 0, 0, 0)
	row[1]++
	row[2] += init_self
	row[3] += post_self
	row[6] += total
	if(init_self + post_self > row[7])
		row[7] = init_self + post_self
	S.depth = d - 1
	if(d > 1)
		S.child_us[d - 1] += total

/proc/benchmark_late_frame_end(d, type)
	var/datum/benchmark_init_stats/S = GLOB.bench_init_stats
	if(!S || !d)
		return
	var/total = rustg_time_microseconds("bench_init_[d]")
	var/list/row = S.by_type[type]
	if(!row)
		row = S.by_type[type] = list(0, 0, 0, 0, 0, 0, 0)
	row[4]++
	row[5] += total - S.child_us[d]
	row[6] += total
	if(total - S.child_us[d] > row[7])
		row[7] = total - S.child_us[d]
	S.depth = d - 1
	if(d > 1)
		S.child_us[d - 1] += total

/proc/benchmark_qdel_frame_begin()
	var/datum/benchmark_init_stats/S = GLOB.bench_init_stats
	if(!S)
		return 0
	var/d = ++S.qdel_depth
	if(length(S.qdel_child_ms) < d)
		S.qdel_child_ms.len = d
		S.qdel_phase_mark_ms.len = d
	S.qdel_child_ms[d] = 0
	S.qdel_phase_mark_ms[d] = 0
	return d

/proc/benchmark_qdel_frame_end(d, type_name, elapsed_ms)
	var/datum/benchmark_init_stats/S = GLOB.bench_init_stats
	if(!S || !d)
		return
	var/list/row = S.qdel_by_type[type_name]
	if(!row)
		row = S.qdel_by_type[type_name] = list(0, 0)
	row[1]++
	row[2] += elapsed_ms - S.qdel_child_ms[d]
	S.qdel_depth = d - 1
	if(d > 1)
		S.qdel_child_ms[d - 1] += elapsed_ms

/// One destroy-transaction phase just ended in the current qdel frame.
/proc/benchmark_qdel_phase(id, elapsed_ms)
	var/datum/benchmark_init_stats/S = GLOB.bench_init_stats
	if(!S)
		return
	var/d = S.qdel_depth
	if(d < 1)
		return
	var/children = S.qdel_child_ms[d] - S.qdel_phase_mark_ms[d]
	S.qdel_phase_mark_ms[d] = S.qdel_child_ms[d]
	if(length(S.phase_self_ms) < LIFECYCLE_PHASE_COUNT)
		S.phase_self_ms.len = LIFECYCLE_PHASE_COUNT
	S.phase_self_ms[id] += elapsed_ms - children

// ---- Helpers ----

/// Top `count` keys of `table` by `value_proc(row)`, descending.
/proc/benchmark_top_rows(list/table, index, count)
	var/list/keys = list()
	for(var/key in table)
		keys += key
	var/list/scores = list()
	for(var/key in keys)
		var/list/row = table[key]
		scores[key] = islist(row) ? row[index] : row
	sortTim(scores, GLOBAL_PROC_REF(cmp_numeric_desc), TRUE)
	var/list/top = list()
	for(var/key in scores)
		top += key
		if(length(top) >= count)
			break
	return top

/// Decodes the current proc profile. Entries: name, self, total, real, over, calls.
/proc/benchmark_proc_profile()
	var/text = world.Profile(PROFILE_REFRESH, format = "json")
	if(!length(text))
		return null
	try
		return json_decode(text)
	catch
		return null

/// Summarises a proc profile: the top procs by self and by total time.
/proc/benchmark_profile_summary(list/profile, count = 60)
	if(!islist(profile))
		return null
	var/list/by_self = list()
	var/list/by_total = list()
	var/list/rows = list()
	for(var/list/entry as anything in profile)
		if(!islist(entry))
			continue
		var/name = "[entry["name"]]"
		rows[name] = entry
		by_self[name] = entry["self"]
		by_total[name] = entry["total"]
	sortTim(by_self, GLOBAL_PROC_REF(cmp_numeric_desc), TRUE)
	sortTim(by_total, GLOBAL_PROC_REF(cmp_numeric_desc), TRUE)
	var/list/top_self = list()
	for(var/name in by_self)
		top_self[name] = rows[name]
		if(length(top_self) >= count)
			break
	var/list/top_total = list()
	for(var/name in by_total)
		top_total[name] = rows[name]
		if(length(top_total) >= count)
			break
	return list("top_self" = top_self, "top_total" = top_total)

// ---- boot_profile ----

/datum/benchmark/boot_profile
	id = "boot_profile"
	description = "Per-subsystem init time; per-type Initialize/materialize/after_init cost (deep profile)"

/datum/benchmark/boot_profile/Run()
	// Read the boot profile before anything else runs.
	if(profiling)
		detail("boot_proc_profile", benchmark_profile_summary(benchmark_proc_profile(), 150))
		SSprofiler.DumpFile(allow_yield = FALSE)
		world.Profile(PROFILE_CLEAR)
	metric("init_seconds", Kernel.initializations_seconds, "s")
	var/list/subsystems = benchmark_subsystem_init_times()
	for(var/name in subsystems)
		metric("init_ms_[name]", subsystems[name], "ms")
	for(var/phase in SSair.init_phase_ms)
		metric("air_init_ms_[phase]", SSair.init_phase_ms[phase], "ms")
	benchmark_rust_mark("booted")
	detail("rust_memory_marks", GLOB.benchmark_rust_marks)
	detail("early_notes", benchmark_early_notes)
	var/list/rust_now = vg_verdigris_allocator_diagnostics()
	if(islist(rust_now))
		metric("booted_rust_heap_mb", rust_now[1] / 1048576, "MB")
		metric("booted_rust_heap_peak_mb", rust_now[2] / 1048576, "MB")
	var/list/process = benchmark_process_memory()
	if(islist(process) && !isnull(process["private_mb"]))
		metric("booted_private_mb", process["private_mb"], "MB")
	metric("booted_ffi_calls", __verdigris_ffi_calls, "calls")
	var/turfs = world.maxx * world.maxy * world.maxz
	metric("world_turfs", turfs, "turfs", "none")
	var/movables = 0
	for(var/atom/movable/AM in world)
		movables++
		CHECK_TICK
	metric("world_movables", movables, "atoms", "none")
	var/list/lighting = list("objects" = 0, "corners" = 0, "sources" = 0)
	for(var/datum/lighting_object/O)
		lighting["objects"]++
		CHECK_TICK
	for(var/datum/lighting_corner/C)
		lighting["corners"]++
		CHECK_TICK
	for(var/datum/light_source/L)
		lighting["sources"]++
		CHECK_TICK
	detail("lighting_counts", lighting)
	for(var/key in lighting)
		metric("lighting_[key]", lighting[key], "datums", "none")
	record_init_types()

/// Per-type init table (deep profile builds only).
/datum/benchmark/boot_profile/proc/record_init_types()
	var/datum/benchmark_init_stats/S = GLOB.bench_init_stats
	var/list/table = S.by_type
	if(!length(table))
		detail("init_types_note", "build without -DBENCHMARK_DEEP_PROFILE: no per-type table")
		return
	// Snapshot: later scenarios create atoms too.
	var/list/snapshot = list()
	var/list/totals = list("count" = 0, "init_us" = 0, "materialize_us" = 0, "late_count" = 0, "late_us" = 0)
	var/list/by_root = list()
	for(var/path in table)
		var/list/row = table[path]
		var/self = row[2] + row[3] + row[5]
		snapshot[path] = list(row[1], row[2], row[3], row[4], row[5], self, row[7], row[6])
		totals["count"] += row[1]
		totals["init_us"] += row[2]
		totals["materialize_us"] += row[3]
		totals["late_count"] += row[4]
		totals["late_us"] += row[5]
		var/root = ispath(path, /turf) ? "turf" : ispath(path, /obj/machinery) ? "machinery" : ispath(path, /obj/structure) ? "structure" : ispath(path, /obj/item) ? "item" : ispath(path, /obj/effect) ? "effect" : ispath(path, /obj) ? "obj_other" : ispath(path, /mob) ? "mob" : ispath(path, /area) ? "area" : "other"
		if(!by_root[root])
			by_root[root] = list("count" = 0, "init_ms" = 0, "materialize_ms" = 0, "late_ms" = 0)
		var/list/root_row = by_root[root]
		root_row["count"] += row[1]
		root_row["init_ms"] += row[2] / 1000
		root_row["materialize_ms"] += row[3] / 1000
		root_row["late_ms"] += row[5] / 1000
	metric("atoms_initialized", totals["count"], "atoms", "none")
	metric("atoms_init_self_ms", totals["init_us"] / 1000, "ms")
	metric("atoms_materialize_self_ms", totals["materialize_us"] / 1000, "ms")
	metric("atoms_late_self_ms", totals["late_us"] / 1000, "ms")
	detail("init_by_root", by_root)
	// Self time (children subtracted) ranks the types whose own Initialize is hot.
	detail("init_types_by_total", format_rows(snapshot, benchmark_top_rows(snapshot, 6, 60)))
	detail("init_types_by_max", format_rows(snapshot, benchmark_top_rows(snapshot, 7, 20)))
	var/list/top_init = list()
	for(var/path in benchmark_top_rows(snapshot, 6, 20))
		var/list/row = snapshot[path]
		top_init["[path]"] = round(row[6] / 1000, 0.01)
	detail("top_init_types_ms", top_init)
	detail("init_types_by_count", format_rows(snapshot, benchmark_top_rows(snapshot, 1, 60)))

/datum/benchmark/boot_profile/proc/format_rows(list/snapshot, list/keys)
	var/list/out = list()
	for(var/path in keys)
		var/list/row = snapshot[path]
		out += list(list(
			"type" = "[path]",
			"count" = row[1],
			"init_ms" = round(row[2] / 1000, 0.01),
			"materialize_ms" = round(row[3] / 1000, 0.01),
			"late_count" = row[4],
			"late_ms" = round(row[5] / 1000, 0.01),
			"total_ms" = round(row[6] / 1000, 0.01),
			"max_ms" = round(row[7] / 1000, 0.01),
			"inclusive_ms" = round(row[8] / 1000, 0.01),
		))
	return out

// ---- explosion_dense ----

/datum/benchmark/explosion_dense
	id = "explosion_dense"
	description = "Devastation-7 explosion on the most furnished station block (bench_devastation; bench_x/y/z override the site)"

/datum/benchmark/explosion_dense/Run()
	wait_for_assets()
	var/devastation = param("devastation", 7)
	var/turf/center = pick_center(devastation)
	if(param("x", 0))
		center = locate(param("x", 0), param("y", 0), param("z", 0))
	if(!center)
		fail("no station turf to bomb")
	var/list/block_counts = block_census(center, devastation * 2)
	detail("site", list("x" = center.x, "y" = center.y, "z" = center.z, "area" = "[get_area(center)]") + block_counts)
	// Let the world settle, then snapshot what the explosion will change.
	wait_fires(SSair, 5)
	var/list/garbage_before = garbage_snapshot()
	var/datum/benchmark_init_stats/S = GLOB.bench_init_stats
	var/list/phase_before = S.phase_self_ms.Copy()
	var/list/qdel_types_before = deep_copy_rows(S.qdel_by_type)
	var/list/lighting_before = list("sources" = SSlighting.times_fired)
	mark("before_explosion")
	benchmark_rust_mark("before explosion")
	begin_window()
	var/started = REALTIMEOFDAY
	explosion(center, devastation, devastation * 2, devastation * 3, 0, FALSE, 0)
	// Resolve: explosions idle, then lighting queues empty.
	var/deadline = REALTIMEOFDAY + 3000
	while(SSexplosions.awake || SSexplosions.pending_blast_count())
		if(REALTIMEOFDAY > deadline)
			fail("explosion did not resolve within 300s")
		stoplag()
	var/resolved_at = REALTIMEOFDAY
	while(length(SSlighting.sources_queue) || length(SSlighting.corners_queue) || length(SSlighting.objects_queue))
		if(REALTIMEOFDAY > deadline)
			fail("lighting did not settle within 300s")
		stoplag()
	var/lit_at = REALTIMEOFDAY
	wait_fires(SSair, 3)
	var/list/profile
	if(profiling)
		profile = benchmark_proc_profile()
	end_window("explosion")
	mark("after_explosion")
	benchmark_rust_mark("after explosion")
	detail("rust_memory_marks", GLOB.benchmark_rust_marks)
	metric("explosion_resolve_wall_ms", (resolved_at - started) * 100, "ms")
	metric("explosion_lighting_settle_wall_ms", (lit_at - resolved_at) * 100, "ms")
	var/list/diagnostics = SSexplosions.performance_diagnostics()
	detail("explosion_epoch", diagnostics)
	metric("explosion_prepare_ms", diagnostics["epoch_prepare_ms"], "ms")
	metric("explosion_turf_resolve_ms", diagnostics["epoch_resolve_ms"], "ms")
	metric("explosion_atom_collect_ms", diagnostics["epoch_atom_collect_ms"], "ms")
	metric("explosion_atom_resolve_ms", diagnostics["epoch_atom_resolve_ms"], "ms")
	metric("explosion_turfs_resolved", diagnostics["epoch_turfs_resolved"], "turfs", "none")
	metric("explosion_atoms_resolved", diagnostics["epoch_atoms_resolved"], "atoms", "none")
	detail("lighting_fires", SSlighting.times_fired - lighting_before["sources"])
	record_garbage_delta(garbage_before)
	if(length(S.phase_self_ms))
		var/list/phases = list()
		for(var/id in 1 to LIFECYCLE_PHASE_COUNT)
			var/before = (length(phase_before) >= id) ? phase_before[id] : 0
			var/after = S.phase_self_ms[id]
			phases[LIFECYCLE_PHASE_NAME(id)] = round((after || 0) - (before || 0), 0.01)
			metric("destroy_phase_self_ms_[LIFECYCLE_PHASE_NAME(id)]", phases[LIFECYCLE_PHASE_NAME(id)], "ms")
		detail("destroy_phase_self_ms", phases)
		var/list/type_delta = list()
		for(var/type_name in S.qdel_by_type)
			var/list/row = S.qdel_by_type[type_name]
			var/list/prior = qdel_types_before[type_name]
			var/count = row[1] - (prior ? prior[1] : 0)
			if(!count)
				continue
			type_delta[type_name] = list(count, row[2] - (prior ? prior[2] : 0))
		var/list/top = list()
		for(var/type_name in benchmark_top_rows(type_delta, 2, 40))
			var/list/row = type_delta[type_name]
			top += list(list("type" = type_name, "qdels" = row[1], "self_ms" = round(row[2], 0.01)))
		detail("destroy_types_by_self_ms", top)
	if(profile)
		detail("explosion_proc_profile", benchmark_profile_summary(profile, 150))

/// The station turf whose (2r+1)^2 block holds the most furnishings (structures,
/// items, non-atmos machinery), excluding
/// blocks with a supermatter (it would chain into a delamination).
/datum/benchmark/explosion_dense/proc/pick_center(radius)
	var/list/station_z = using_map.station_levels
	var/list/station_areas = list()
	for(var/area/A as anything in get_station_areas(list()))
		station_areas[A] = TRUE
	var/best_score = -1
	var/turf/best
	for(var/z in station_z)
		// Prefix sums of movable counts over the level.
		var/w = world.maxx
		var/h = world.maxy
		var/list/sums = new /list((w + 1) * (h + 1))
		for(var/i in 1 to length(sums))
			sums[i] = 0
		var/list/forbidden = list()
		for(var/y in 1 to h)
			var/row_sum = 0
			for(var/x in 1 to w)
				var/turf/T = locate(x, y, z)
				var/count = 0
				FOR_CONTENTS(var/atom/movable/AM as anything, T)
					// Furnishings: pipes and cables would make every block an
					// engineering corridor.
					if(istype(AM, /obj/machinery/atmospherics) || istype(AM, /obj/structure/cable))
						continue
					if(istype(AM, /obj/structure) || istype(AM, /obj/item) || istype(AM, /obj/machinery))
						count++
					if(istype(AM, /obj/machinery/power/supermatter))
						forbidden += T
				row_sum += count
				sums[y * (w + 1) + x + 1] = sums[(y - 1) * (w + 1) + x + 1] + row_sum
			CHECK_TICK
		for(var/y in (radius + 1) to (h - radius) step 2)
			for(var/x in (radius + 1) to (w - radius) step 2)
				var/turf/T = locate(x, y, z)
				if(!istype(T, /turf/simulated/floor))
					continue
				if(!station_areas[T.loc])
					continue
				var/x1 = x - radius - 1
				var/y1 = y - radius - 1
				var/x2 = x + radius
				var/y2 = y + radius
				var/score = sums[y2 * (w + 1) + x2 + 1] - sums[y1 * (w + 1) + x2 + 1] - sums[y2 * (w + 1) + x1 + 1] + sums[y1 * (w + 1) + x1 + 1]
				if(score <= best_score)
					continue
				var/blocked = FALSE
				for(var/turf/F as anything in forbidden)
					if(abs(F.x - x) <= radius * 3 && abs(F.y - y) <= radius * 3)
						blocked = TRUE
						break
				if(blocked)
					continue
				best_score = score
				best = T
			CHECK_TICK
	return best

/datum/benchmark/explosion_dense/proc/block_census(turf/center, radius)
	var/turfs = 0
	var/walls = 0
	var/movables = 0
	var/objs = 0
	var/machines = 0
	for(var/turf/T as anything in RANGE_TURFS(radius, center))
		turfs++
		if(T.density)
			walls++
		FOR_CONTENTS(var/atom/movable/AM as anything, T)
			movables++
			if(isobj(AM))
				objs++
			if(istype(AM, /obj/machinery))
				machines++
	return list("block_turfs" = turfs, "block_walls" = walls, "block_movables" = movables, "block_objs" = objs, "block_machines" = machines)

/datum/benchmark/explosion_dense/proc/garbage_snapshot()
	var/list/snapshot = list()
	for(var/path in SSgarbage.items)
		var/datum/qdel_item/item = SSgarbage.items[path]
		snapshot[path] = list(item.qdels, item.destroy_time, item.phase_ms ? item.phase_ms.Copy() : null)
	return snapshot

/datum/benchmark/explosion_dense/proc/deep_copy_rows(list/table)
	var/list/copy = list()
	for(var/key in table)
		var/list/row = table[key]
		copy[key] = row.Copy()
	return copy

/// qdel counts and inclusive destroy time per type over the explosion, plus
/// per-phase inclusive totals for top-level-by-type (nested time counts in
/// both parent and child: use destroy_phase_self_ms for exclusive numbers).
/datum/benchmark/explosion_dense/proc/record_garbage_delta(list/before)
	var/list/delta = list()
	var/total_qdels = 0
	for(var/path in SSgarbage.items)
		var/datum/qdel_item/item = SSgarbage.items[path]
		var/list/prior = before[path]
		var/qdels = item.qdels - (prior ? prior[1] : 0)
		if(!qdels)
			continue
		total_qdels += qdels
		delta[path] = list(qdels, item.destroy_time - (prior ? prior[2] : 0))
	metric("explosion_qdels", total_qdels, "qdels", "none")
	var/list/by_count = list()
	for(var/path in benchmark_top_rows(delta, 1, 40))
		var/list/row = delta[path]
		by_count += list(list("type" = "[path]", "qdels" = row[1], "inclusive_ms" = round(row[2], 0.01)))
	detail("destroy_types_by_count", by_count)
	var/list/by_time = list()
	for(var/path in benchmark_top_rows(delta, 2, 40))
		var/list/row = delta[path]
		by_time += list(list("type" = "[path]", "qdels" = row[1], "inclusive_ms" = round(row[2], 0.01)))
	detail("destroy_types_by_inclusive_ms", by_time)
