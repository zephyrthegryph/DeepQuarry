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
	probe("slots", param("slots", 600000), stall_ms, length(handle_gens))
	probe("fact_strings", param("facts", 20000), stall_ms, 0)
	probe("fact_strings_churn", param("facts", 20000), stall_ms, 0)
	probe("string_churn", param("churn", 300000), stall_ms, 0)
	probe("datum_churn", param("churn", 300000), stall_ms, 0)
	probe("list_churn", param("churn", 300000), stall_ms, 0)
	drain_probe(param("drain", 3000))
	probe("contract_context", param("events", 8000), stall_ms, 0)
	probe("contract_events", param("events", 8000), stall_ms, 0)
	probe("plain_events", param("events", 8000), stall_ms, 0)

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
			if("fact_strings")
				var/h = 1048576 + i * 7919
				keep[i] = list("infrastructure-damage:[handle_text(h)]", "infrastructure-damage:[handle_text(h)]:1")
			if("fact_strings_churn")
				var/h2 = 9048576 + i * 7919
				var/list/pair = list("infrastructure-damage:[handle_text(h2)]", "infrastructure-damage:[handle_text(h2)]:1")
				pair = null
			if("string_churn")
				var/churned = "churn-[i]-[world.time]"
				churned = null
			if("datum_churn")
				var/datum/alloc_stall_probe/C = new
				C = null
			if("list_churn")
				var/list/L = list(i)
				L = null
			if("slots")
				var/datum/alloc_stall_probe/P = new
				slot_of(P)
				keep[i] = P
			if("contract_context")
				keep[i] = list("department" = DEPARTMENT_ENGINEERING, "atom_id" = i, "fact_id" = "probe:[i]", "metrics" = list("damage_amount" = i))
			if("contract_events")
				keep[i] = new /datum/contract_event(CONTRACT_EVENT_INFRASTRUCTURE_DAMAGED, null, null, null, list("department" = DEPARTMENT_ENGINEERING, "atom_id" = i, "fact_id" = "probe:[i]", "metrics" = list("damage_amount" = i)), "probe:[i]:1")
			if("plain_events")
				keep[i] = new /datum/contract_event
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

/// The real contract drain without a blast: `count` objects each take one damage report in one batch, which drains as a job.
/datum/benchmark/alloc_stall/proc/drain_probe(count)
	if(count <= 0)
		return
	var/turf/T = locate(world.maxx / 2, world.maxy / 2, 1)
	var/list/objs = list()
	for(var/i in 1 to count)
		objs += new /obj/structure/girder(T)
		if(!(i % 500))
			stoplag()
	var/start = REALTIMEOFDAY
	SScontracts.begin_contract_batch()
	for(var/obj/structure/girder/G as anything in objs)
		SScontracts.queue_damage_report(G, 40)
	SScontracts.end_contract_batch()
	while(SScontracts.is_contract_batching() && REALTIMEOFDAY < start + 120 SECONDS)
		stoplag()
	metric("drain_wall_s", (REALTIMEOFDAY - start) / 10, "s", "none")
	for(var/obj/structure/girder/G as anything in objs)
		qdel(G)
