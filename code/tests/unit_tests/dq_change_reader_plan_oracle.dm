// The change graph's reader plan (doc/rewrite/proposals/change_graph.md section 11 steps 3d and 3e: per type).
//
// state_changed() and publish_change() probe the reaction tables, the on_change() hook index and the lifecycle forms only for the classes the
// generated reader plan (plan_reader_bits(), code/engine/change/plan.dm) says may read a key. The plan is over-inclusive by construction; this
// proves it covers what the runtime builders register: every key of every built rx table (against its own type's plan) (reactions, derived and generated reads, sequences), of
// every built hook index and hop registration, and of every built lifeform watch carries its class. A key the plan misses would be a silently
// unpublished change.
//
// The normal tier checks what the test world built while it booted and ran (systems, the map's atoms) plus a curated spread; the exhaustive tier
// makes one fresh instance of every creatable type first (sharded, like dq_stat_index_oracle).

/datum/unit_test/dq_change_reader_plan_oracle
	tier = TEST_TIER_EXHAUSTIVE
	timeout = 3600
	is_sweep_test = TRUE

/// What the normal tier makes before it checks (each builds its tables).
/datum/unit_test/dq_change_reader_plan_oracle/proc/oracle_types()
	return sweep_types(dq_fresh_look_universe())

/datum/unit_test/dq_change_reader_plan_oracle/Run()
	var/turf/T = test_floor()
	var/made = 0
	for(var/type in oracle_types())
		made++
		dq_fresh_look_reset(T)
		try
			var/atom/A = dq_snapshot_allocate(type, T)
			if(!QDELETED(A))
				rx_readers(A, "dq_reader_plan_probe", PLAN_READ_ALL) // builds the rx table and the hook index
				lifeform_watching(A, "dq_reader_plan_probe") // builds the lifeform plan
				dq_fresh_look_delete(A)
		catch(var/exception/e)
			log_test("reader plan oracle: [type] runtimed: [e.name]")
		dq_fresh_look_drain(T)
	dq_fresh_look_reset(T)
	var/list/missing = dq_reader_plan_missing()
	log_test("reader plan oracle: [made] types made, [length(GLOB.plan_reader_keys)] plan keys, [length(missing)] missing")
	log_test("reader plan metric: [GLOB.plan_reader_probes] tracked writes asked the plan, [GLOB.plan_spared_reader_probes] read by no static reader of any type (no table probed)")
	TEST_ASSERT(!length(missing), "the reader plan misses keys the runtime tables register:\n[jointext(missing, "\n")]")

/// Normal tier: the tables the world built, after a curated spread.
/datum/unit_test/dq_change_reader_plan_oracle/representative
	is_sweep_test = FALSE
	tier = TEST_TIER_NORMAL
	timeout = 600

/datum/unit_test/dq_change_reader_plan_oracle/representative/oracle_types()
	return list(
		/obj/machinery/navbeacon,
		/obj/machinery/floodlight,
		/obj/machinery/door/airlock,
		/obj/machinery/power/apc,
		/obj/machinery/alarm,
		/obj/item/storage/toolbox/mechanical,
		/obj/item/cell,
		/obj/item/radio,
		/obj/structure/table,
		/mob/living/carbon/human,
	)

/// "<key> (<class> on <type>)" for every key a built runtime table registers that the reader plan does not give its class (a key that is not a
/// tracked var keeps every class, plan_reader_bits()).
/proc/dq_reader_plan_missing()
	. = list()
	if(!plan_reader_keys_build())
		. += "the reader plan could not be built"
		return
	for(var/type in GLOB.rx_tables)
		var/datum/rx_table/R = GLOB.rx_tables[type]
		if(!istype(R))
			continue
		for(var/key in R.read_keys)
			if(!(plan_reader_bits(key, type) & PLAN_READ_REACT))
				. |= "[key] (reaction on [type])"
	for(var/type in GLOB.change_index_by_type)
		var/list/index = GLOB.change_index_by_type[type]
		if(!islist(index))
			continue
		for(var/key in index)
			if(!(plan_reader_bits(key, type) & PLAN_READ_HOOK))
				. |= "[key] (hook on [type])"
	for(var/key in GLOB.change_hop_keys)
		// A hop's far end is read on whatever type it reaches: the far keys are in the rows for every type.
		if(GLOB.plan_tracked_names[key] && !(GLOB.plan_reader_keys[key] & PLAN_READ_HOOK))
			. |= "[key] (hook hop)"
	for(var/type in lifeform_plans)
		var/datum/lifeform_plan/P = lifeform_plans[type]
		for(var/key in P?.watch)
			if(!(plan_reader_bits(key, type) & PLAN_READ_LIFEFORM))
				. |= "[key] (lifeform on [type])"
