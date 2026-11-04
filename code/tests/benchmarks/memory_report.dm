// Where the private memory of a booted full-map world goes (measurement only, no gameplay effect).
//   DQ_BENCH_CONFIG_DIR=config/example tools/build/build.sh bench --scenario=memory_report -DCITESTING_FULL_MAP [--arg=settle=60] [--arg=idle=180] [--arg=sample=40]
// Builds on memory_breakdown (appearance and global-size helpers) and the boot_memory census. Every walk is a typed loop with
// CHECK_TICK; nothing here runs the reference search. The report that reads the output is E:/projects/dq-memory-report.md.

/datum/benchmark/memory_breakdown/report
	id = "memory_report"
	description = "Private memory by owner: process series, Rust allocator tags, DM instances and lists, appearances, globals"

/// One private-memory sample from the runner as a list of the fields worth keeping.
/datum/benchmark/memory_breakdown/report/proc/process_row(name)
	var/list/process = benchmark_process_memory()
	if(!islist(process))
		return list("name" = name)
	return list("name" = name, "private_mb" = process["private_mb"], "working_set_mb" = process["working_set_mb"], "peak_private_mb" = process["peak_private_mb"], "machine_cpu_pct" = process["machine_cpu_pct"], "t" = process["t"])

/datum/benchmark/memory_breakdown/report/Run()
	wait_for_assets()
	wait_fires(SSair, 10)
	var/list/series = list()
	series += list(process_row("booted"))
	detail("early_notes", benchmark_early_notes)
	wait_seconds(param("settle", 60))
	series += list(process_row("settled"))
	benchmark_rust_mark("memory_report settled")
	// Idle, sampled every 30 s, so growth after settling shows.
	var/idle_seconds = param("idle", 180)
	var/waited = 0
	while(waited < idle_seconds)
		wait_seconds(30)
		waited += 30
		series += list(process_row("idle+[waited]s"))
	detail("process_series", series)
	var/list/process = benchmark_process_memory()
	if(islist(process))
		metric("idle_private_mb", process["private_mb"], "MB")
		metric("peak_private_mb", process["peak_private_mb"], "MB")
		metric("idle_working_set_mb", process["working_set_mb"], "MB")
	rust_report()
	dm_census()
	list_census(param("sample", 40))
	appearance_report()
	engine_report()
	global_sizes()
	detail("rust_memory_marks", GLOB.benchmark_rust_marks)

/// Live Rust bytes by allocator tag (the Rust side of the process), in MB.
/datum/benchmark/memory_breakdown/report/proc/rust_report()
	var/list/rust = verdigris_metrics_list()
	var/list/tags = list()
	if(islist(rust))
		for(var/key in rust)
			if(findtext(key, "alloc.") == 1)
				tags[key] = rust[key]
		// Byte counts become MB for the tags that report bytes.
		var/list/mb = list()
		for(var/key in tags)
			var/value = tags[key]
			if(isnum(value) && findtext(key, "_bytes"))
				mb[key] = round(value / 1048576, 0.01)
		detail("rust_alloc_mb", mb)
		detail("rust_alloc_raw", tags)
		detail("rust_gas_stats", vg_gas_stats())
	var/list/heap = vg_verdigris_allocator_diagnostics()
	if(islist(heap))
		count_metric("rust_heap_mb", heap[1] / 1048576, "MB")
		count_metric("rust_heap_peak_mb", heap[2] / 1048576, "MB")

/// Instances by root and by type (typed loops over world and datums).
/datum/benchmark/memory_breakdown/report/proc/dm_census()
	var/list/census = benchmark_census(60)
	count_metric("instances_total", census["total"], "instances")
	for(var/root in census["by_root"])
		count_metric("instances_[root]", census["by_root"][root], "instances")
	detail("census_top_types", census["top_types"])
	var/list/types = benchmark_type_counts()
	for(var/kind in types)
		count_metric("types_[kind]", types[kind], "types")
	count_metric("types_total_typesof_datum", length(typesof(/datum)), "types")
	var/icons = 0
	for(var/icon/I)
		icons++
		CHECK_TICK
	var/images = 0
	for(var/image/I)
		images++
		CHECK_TICK
	var/mutables = 0
	for(var/mutable_appearance/M)
		mutables++
		CHECK_TICK
	count_metric("icon_objects", icons, "icons")
	count_metric("image_objects", images, "images")
	count_metric("mutable_appearance_objects", mutables, "objects")
	var/clients = 0
	for(var/client/C)
		clients++
	count_metric("clients", clients, "clients")

/// Lists held in vars, sampled `sample` instances per type and scaled by count: totals and the owners with the most lists and entries.
/// The sample reads every var of the sampled instances; a list is counted once per holder var (a shared list counts per holder, so shared tables overstate).
/datum/benchmark/memory_breakdown/report/proc/list_census(sample = 40)
	var/static/list/skip = list("vars" = TRUE, "contents" = TRUE, "overlays" = TRUE, "underlays" = TRUE, "verbs" = TRUE, "vis_contents" = TRUE, "vis_locs" = TRUE, "locs" = TRUE, "filters" = TRUE, "screen" = TRUE, "images" = TRUE, "group" = TRUE, "client_images" = TRUE, "transform" = TRUE, "type" = TRUE, "parent_type" = TRUE)
	// type -> list(count, sampled, lists, entries, empty lists, assoc entries)
	var/list/rows = list()
	for(var/datum/thing)
		list_census_visit(thing, rows, skip, sample)
		CHECK_TICK
	for(var/atom/thing in world)
		list_census_visit(thing, rows, skip, sample)
		CHECK_TICK
	var/lists = 0
	var/entries = 0
	var/empty = 0
	var/assoc = 0
	var/list/by_root = list("area" = 0, "turf" = 0, "obj" = 0, "mob" = 0, "datum" = 0)
	var/list/by_type = list()
	var/list/entries_by_type = list()
	for(var/path in rows)
		var/list/row = rows[path]
		var/scale = row[2] ? row[1] / row[2] : 0
		var/n_lists = row[3] * scale
		lists += n_lists
		entries += row[4] * scale
		empty += row[5] * scale
		assoc += row[6] * scale
		var/root = "datum"
		if(ispath(path, /area))
			root = "area"
		else if(ispath(path, /turf))
			root = "turf"
		else if(ispath(path, /obj))
			root = "obj"
		else if(ispath(path, /mob))
			root = "mob"
		by_root[root] += n_lists
		by_type["[path]"] = round(n_lists)
		entries_by_type["[path]"] = round(row[4] * scale)
	count_metric("lists_in_vars_est", round(lists), "lists")
	count_metric("lists_in_vars_empty_est", round(empty), "lists")
	count_metric("list_entries_est", round(entries), "entries")
	count_metric("list_assoc_entries_est", round(assoc), "entries")
	for(var/root in by_root)
		count_metric("lists_owner_[root]", round(by_root[root]), "lists")
	by_type = sortTim(by_type, GLOBAL_PROC_REF(cmp_numeric_desc), associative = TRUE)
	if(length(by_type) > 40)
		by_type.Cut(41)
	entries_by_type = sortTim(entries_by_type, GLOBAL_PROC_REF(cmp_numeric_desc), associative = TRUE)
	if(length(entries_by_type) > 40)
		entries_by_type.Cut(41)
	detail("lists_by_owner_type", by_type)
	detail("list_entries_by_owner_type", entries_by_type)
	var/list/model = benchmark_type_memory(40, sample)
	metric("dm_model_mb", model["total_est_mb"], "MB", "none")
	detail("type_memory_top", model["top"])

/datum/benchmark/memory_breakdown/report/proc/list_census_visit(datum/thing, list/rows, list/skip, sample)
	var/list/row = rows[thing.type]
	if(!row)
		row = list(0, 0, 0, 0, 0, 0)
		rows[thing.type] = row
	row[1]++
	if(row[2] >= sample)
		return
	row[2]++
	for(var/name in thing.vars)
		if(skip[name])
			continue
		var/value = thing.vars[name]
		if(!islist(value))
			continue
		var/list/L = value
		var/len = length(L)
		row[3]++
		row[4] += len
		if(!len)
			row[5]++
		else if(!isnum(L[1]) && !isnull(L[L[1]]))
			row[6] += len

/// Unique appearances of atoms and their overlays, and how many overlay references point at them.
/datum/benchmark/memory_breakdown/report/proc/appearance_report()
	var/list/own = list()
	var/list/overlay = list()
	var/atoms = 0
	var/overlay_refs = 0
	var/with_overlays = 0
	var/vis = 0
	for(var/atom/A in world)
		atoms++
		own[ref(A.appearance)] = TRUE
		var/n = length(A.overlays) + length(A.underlays)
		if(n)
			with_overlays++
		for(var/entry in A.overlays)
			overlay_refs++
			overlay[ref(entry)] = TRUE
		for(var/entry in A.underlays)
			overlay_refs++
			overlay[ref(entry)] = TRUE
		if(ismovable(A))
			var/atom/movable/AM = A
			vis += length(AM.vis_contents)
		CHECK_TICK
	count_metric("atoms_walked", atoms, "atoms")
	count_metric("unique_atom_appearances", length(own), "appearances")
	count_metric("unique_overlay_appearances", length(overlay), "appearances")
	count_metric("overlay_underlay_refs", overlay_refs, "refs")
	count_metric("atoms_with_overlays", with_overlays, "atoms")
	count_metric("vis_contents_refs", vis, "refs")

/// Sizes of the engine's own big globals: every GLOB list by length (shallow), the kernel's queues and the refresh queue.
/datum/benchmark/memory_breakdown/report/proc/engine_report()
	var/list/lengths = list()
	for(var/name in GLOB.vars)
		var/value = GLOB.vars[name]
		if(islist(value) && length(value) > 500)
			lengths[name] = length(value)
	lengths = sortTim(lengths, GLOBAL_PROC_REF(cmp_numeric_desc), associative = TRUE)
	if(length(lengths) > 50)
		lengths.Cut(51)
	detail("glob_list_lengths", lengths)
	count_metric("refresh_queue_len", length(GLOB.refresh_queue), "entries")
	count_metric("systems", length(kernel_pure_systems()), "systems")
