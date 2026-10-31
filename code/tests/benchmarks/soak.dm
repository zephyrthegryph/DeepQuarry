// Soak: a booted full-map world left running with some live humans, sampled every `bench_interval` seconds for `bench_minutes`
// minutes. Finds what grows without bound (the play server froze at its 2 GB address-space limit about 26 minutes into a round):
//   - the BYOND list id high water (a list nothing frees raises it; the pool is about 16M ids)
//   - the process memory sample the runner writes, and the Rust heap
//   - the live instance census by type at the start and the end: the types that grew are the leak's owners
//   - the lengths of every GLOB list at the start and the end: the registries that grew
// Run: tools/build/build.sh bench --scenario=soak --arg=minutes=10 --arg=humans=20 -DCITESTING_FULL_MAP

/// The highest list id among `count` lists held at once (see dq_list_id_high_water() in the unit tests: a list's ref carries its id).
/proc/benchmark_list_id_high_water(count = 64)
	var/list/held = list()
	var/high = 0
	for(var/i in 1 to count)
		var/list/L = list()
		held += list(L)
		var/id = text2num(copytext(ref(L), 6), 16) // "[0x5xxxxxx]": drop "[0x5"
		if(isnum(id) && id > high)
			high = id
	return high

/// Live instances by type: type text -> count.
/proc/benchmark_census_by_type()
	var/list/by_type = list()
	for(var/datum/thing)
		by_type["[thing.type]"]++
		CHECK_TICK
	for(var/atom/thing in world)
		by_type["[thing.type]"]++
		CHECK_TICK
	return by_type

/// GLOB var name -> length, for the list globals.
/proc/benchmark_glob_lengths()
	. = list()
	for(var/name in GLOB.vars)
		var/value = GLOB.vars[name]
		if(islist(value))
			.[name] = length(value)

/// The `top` largest increases from `before` to `after` (both name -> number), as "name: before -> after".
/proc/benchmark_growth_rows(list/before, list/after, top = 25)
	var/list/delta = list()
	for(var/name in after)
		var/grew = after[name] - (before[name] || 0)
		if(grew > 0)
			delta[name] = grew
	var/list/names = list()
	for(var/name in delta)
		var/at = 1
		while(at <= length(names) && delta[names[at]] >= delta[name])
			at++
		if(at > top)
			continue
		names.Insert(at, name)
		if(length(names) > top)
			names.Cut(top + 1)
	. = list()
	for(var/name in names)
		. += "[name]: [before[name] || 0] -> [after[name]] (+[delta[name]])"

/datum/benchmark/soak
	id = "soak"
	description = "Long run with live humans: list ids, memory and the census by type at the start and the end"

/datum/benchmark/soak/Run()
	wait_for_assets()
	wait_fires(SSair, 10)
	var/minutes = param("minutes", 10)
	var/interval = param("interval", 30)
	var/humans = param("humans", 20)
	var/list/floors = list()
	for(var/turf/simulated/floor/F in world)
		if(F.z <= 3 && !F.density)
			floors += F
		CHECK_TICK
	for(var/i in 1 to humans)
		if(!length(floors))
			break
		new /mob/living/carbon/human(pick(floors))
	benchmark_rust_mark("soak start")
	stoplag()
	var/list/census_start = benchmark_census_by_type()
	var/list/globs_start = benchmark_glob_lengths()
	var/ids_start = benchmark_list_id_high_water()
	var/list/series = list()
	var/samples = round(minutes * 60 / interval)
	for(var/i in 1 to samples)
		wait_seconds(interval)
		var/ids = benchmark_list_id_high_water()
		var/list/process = benchmark_process_memory()
		var/row = "t=[i * interval]s list_id=[ids] (+[ids - ids_start])"
		if(islist(process))
			row += " process=[json_encode(process)]"
		series += row
		log_world("SOAK: [row]")
		count_metric("soak_list_id_[i]", ids, "id")
	var/ids_end = benchmark_list_id_high_water()
	count_metric("soak_list_id_growth", ids_end - ids_start, "ids")
	metric("soak_list_id_growth_per_minute", (ids_end - ids_start) / max(minutes, 1), "ids/min", "lower", "count")
	var/list/census_end = benchmark_census_by_type()
	var/list/globs_end = benchmark_glob_lengths()
	var/list/type_growth = benchmark_growth_rows(census_start, census_end)
	var/list/glob_growth = benchmark_growth_rows(globs_start, globs_end)
	for(var/row in type_growth)
		log_world("SOAK: type grew: [row]")
	for(var/row in glob_growth)
		log_world("SOAK: GLOB list grew: [row]")
	detail("soak_series", series)
	detail("soak_type_growth", type_growth)
	detail("soak_glob_growth", glob_growth)
	benchmark_rust_mark("soak end")
	detail("rust_memory_marks", GLOB.benchmark_rust_marks)
