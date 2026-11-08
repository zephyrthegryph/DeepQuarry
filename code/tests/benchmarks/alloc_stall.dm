// A probe for one-off stalls in BYOND's own tables: allocates datums, then unique strings, then lists, each op timed alone, and records
// every op slower than `bench_stall_ms` (default 20) with how many of its kind existed then. A table that doubles shows as stalls at
// counts that double; machine noise shows as stalls at no pattern. Full map (the station's ~515k atoms are what the tables already hold).
//   tools/build/build.sh bench --scenario=alloc_stall -DCITESTING_FULL_MAP [--arg=datums=400000] [--arg=strings=1000000] [--arg=lists=400000]

/datum/benchmark/alloc_stall
	id = "alloc_stall"
	description = "Allocation stall probe: datums, unique strings and lists, each op timed, stalls listed with the live count"

/datum/alloc_stall_probe

/datum/benchmark/alloc_stall/Run()
	wait_for_assets()
	wait_seconds(10)
	var/stall_ms = param("stall_ms", 20)
	var/base_datums = 0
	for(var/datum/D)
		base_datums++
	count_metric("base_datums", base_datums, "datums", "none")
	count_metric("base_atoms", length(world.contents), "atoms", "none")
	probe("datums", param("datums", 400000), stall_ms, base_datums)
	probe("strings", param("strings", 1000000), stall_ms, 0)
	probe("lists", param("lists", 400000), stall_ms, 0)

/datum/benchmark/alloc_stall/proc/probe(kind, count, stall_ms, base)
	var/list/keep = new /list(count)
	var/list/stalls = list()
	var/worst = 0
	var/started_rt = REALTIMEOFDAY
	for(var/i in 1 to count)
		var/before = TICK_USAGE_REAL
		switch(kind)
			if("datums")
				keep[i] = new /datum/alloc_stall_probe
			if("strings")
				keep[i] = "alloc-stall-[i]-[world.time]"
			if("lists")
				keep[i] = list(i)
		var/ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - before)
		if(ms > worst)
			worst = ms
		if(ms >= stall_ms)
			stalls += list(list("index" = i, "live" = base + i, "ms" = round(ms, 0.1)))
			log_runtime("ALLOC_STALL [kind] #[i] (live about [base + i]) took [round(ms, 0.1)] ms")
		if(!(i % 5000))
			stoplag() // keep the world ticking; a stall is one op, never the yield
	metric("[kind]_worst_op_ms", worst, "ms")
	count_metric("[kind]_stalls", length(stalls), "stalls")
	metric("[kind]_wall_s", (REALTIMEOFDAY - started_rt) / 10, "s", "none")
	detail("[kind]_stalls", stalls)
	keep.Cut()
