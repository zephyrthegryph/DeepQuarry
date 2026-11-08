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
	count_metric("base_atoms", length(world.contents), "atoms", "none")
	var/n = param("facts", 3000)
	var/list/kinds = splittext(param("kinds", "fact_strings,fact_suffix,fact_short_prefix,handle_only,ref_kept,ref_prefixed_kept,ref_suffixed_kept,window_prefix,window_suffix"), ",")
	for(var/kind in kinds)
		probe(kind, n, stall_ms, 0)
	drain_probe(param("drain", 0))

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
			if("num16_kept")
				keep[i] = num2text(2048576 + i * 7919, 16)
			if("pregrow_strings")
				keep[i] = "pregrow-[i]-[world.time]"
			if("num8_kept_b")
				keep[i] = num2text(5048576 + i * 7919, 8)
			if("num8_kept")
				keep[i] = num2text(3048576 + i * 7919, 8)
			if("num16_churn_low")
				var/t = num2text(1048576 + i * 7919 + 3, 16)
				t = null
			if("ref_kept")
				var/datum/alloc_stall_probe/R1 = new
				keep[i] = list(R1, REF(R1))
			if("ref_prefixed_kept")
				var/datum/alloc_stall_probe/R2 = new
				keep[i] = list(R2, "click:[REF(R2)]")
			if("ref_suffixed_kept")
				var/datum/alloc_stall_probe/R3 = new
				keep[i] = list(R3, "[REF(R3)]:click")
			if("window_prefix")
				// a timer-style key held while pending: about 1000 live at once, the oldest dropped
				keep[i] = "seq:[num2text(i + 7000000, 8)]:rewake"
				if(i > 1000)
					keep[i - 1000] = null
			if("window_suffix")
				keep[i] = "[num2text(i + 8000000, 8)]:seq:rewake"
				if(i > 1000)
					keep[i - 1000] = null
			if("same_string")
				// the same text every time (BYOND prints 7000001 as "7e+06"): no new string at all
				keep[i] = "seq:[7000000 + i]:rewake"
				if(i > 1000)
					keep[i - 1000] = null
			if("small_window_prefix")
				keep[i] = "seq:[i]:rewake"
				if(i > 1000)
					keep[i - 1000] = null
			if("fact_suffix")
				var/hs = 1048577 + i * 7919
				keep[i] = list("[handle_text(hs)]:infrastructure-damage", "[handle_text(hs)]:1:infrastructure-damage")
			if("fact_short_prefix")
				var/hp = 1048578 + i * 7919
				keep[i] = list("i:[handle_text(hp)]", "i:[handle_text(hp)]:1")
			if("handle_only")
				var/ho = 1048579 + i * 7919
				keep[i] = list(handle_text(ho), "[handle_text(ho)]:1")
			if("fact_strings_again")
				var/ha = 1048580 + i * 7919
				keep[i] = list("infrastructure-damage:[handle_text(ha)]", "infrastructure-damage:[handle_text(ha)]:1")
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
