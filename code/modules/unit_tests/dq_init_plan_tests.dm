// The compiled init plan (code/engine/declare/init_plan.dm) against the per-instance discovery it replaced.

/// Every compiled plan says what the discovery path finds for its type, step by step.
/datum/unit_test/dq_init_plan_matches_discovery

/datum/unit_test/dq_init_plan_matches_discovery/Run()
	var/list/cache = init_plan_cache()
	TEST_ASSERT(length(cache) > 50, "the map load compiled plans ([length(cache)])")
	var/checked = 0
	for(var/type in cache)
		var/datum/init_plan/P = cache[type]
		var/datum/type_table/T = type_table_cache()[type]
		TEST_ASSERT_NOTNULL(T, "[type] has a plan but no table")
		TEST_ASSERT_EQUAL(P.hook_flags, T.hook_flags, "[type] hook flags")
		var/list/pre = list()
		var/list/ini = list()
		for(var/datum/centry/C as anything in compiled_entries(T, ENTRY_CAPABILITY))
			var/datum/capability/def = C.item
			if(def.holder_hooks & HOLDER_HOOK_PREINIT)
				pre += def
			if(def.holder_hooks & HOLDER_HOOK_INIT)
				ini += def
		TEST_ASSERT(init_plan_same_list(pre, P.preinit_caps), "[type] preinit hooks")
		TEST_ASSERT(init_plan_same_list(ini, P.init_caps), "[type] init hooks")
		var/list/grants = list()
		for(var/datum/centry/C as anything in compiled_entries(T, ENTRY_REL_GRANTS))
			var/datum/entry/E = C.item
			grants += E.args["var"]
		TEST_ASSERT(init_plan_same_list(grants, P.rel_grant_vars), "[type] relation grants")
		TEST_ASSERT_EQUAL(P.change_baseline, !!GLOB.change_index_by_type[type], "[type] on_change baseline")
		var/every = FALSE
		for(var/datum/centry/C as anything in compiled_entries(T, ENTRY_EVERY))
			if(isnull(C.owner))
				every = TRUE
		TEST_ASSERT_EQUAL(P.every_arm, every, "[type] every() arming")
		if(ispath(type, /atom))
			TEST_ASSERT_EQUAL(P.verb_entries, !!GLOB.verb_entry_sets[type], "[type] verb entries")
		checked++
	log_world("dq_init_plan_matches_discovery: [checked] plans checked")

/proc/init_plan_same_list(list/a, list/b)
	if(LAZYLEN(a) != LAZYLEN(b))
		return FALSE
	for(var/i in 1 to LAZYLEN(a))
		if(a[i] != b[i])
			return FALSE
	return TRUE

/// An instance initialised through the plan ends in the state the discovery path leaves: representative map types, both ways.
/datum/unit_test/dq_init_plan_parity

/datum/unit_test/dq_init_plan_parity/Run()
	var/list/types = list(
		/obj/machinery/door/firedoor,
		/obj/machinery/light,
		/obj/machinery/atmospherics/pipe/simple/hidden,
		/obj/structure/grille,
		/obj/structure/table/standard,
		/obj/item/tool/wrench,
		/obj/machinery/vending/coffee,
	)
	var/turf/at = run_loc_floor_bottom_left
	for(var/type in types)
		if(!ispath(type))
			continue
		var/list/with_plan = init_plan_snapshot(type, at, FALSE)
		var/list/without = init_plan_snapshot(type, at, TRUE)
		var/list/diffs = list()
		for(var/key in with_plan | without)
			if(with_plan[key] != without[key])
				diffs += "[key]: plan [with_plan[key]] / discovery [without[key]]"
		TEST_ASSERT(!length(diffs), "[type] differs between the plan and the discovery path: [jointext(diffs, "; ")]")

/// The engine-visible state of a fresh `type` made with the plan on or off: primitive vars, and the engine records it was given.
/proc/init_plan_snapshot(type, turf/at, off)
	var/list/had = at.contents.Copy()
	var/was = GLOB.init_plan_off
	GLOB.init_plan_off = off
	var/atom/A
	rand_seed(4242) // both ways draw the same rolls (a light fixture's broken_chance)
	try
		A = new type(at)
	catch(var/exception/e)
		GLOB.init_plan_off = was
		throw e
	GLOB.init_plan_off = was
	. = list()
	var/static/list/skip = list("x", "y", "z", "loc", "vars", "type", "parent_type", "tag", "contents", "gc_destroyed", "serial", "weak_reference", "datum_id", "rx", "refresh_queued", "refresh_bits", "own_key_text")
	for(var/V in A.vars)
		if(V in skip)
			continue
		var/value = A.vars[V]
		if(istext(value) && findtext(value, "\[0x"))
			.[V] = "(instance ref)" // another instance's identity, not state
		else if(isnull(value) || isnum(value) || istext(value) || ispath(value))
			.[V] = value
		else if(islist(value))
			var/list/L = value
			.["[V].len"] = length(L)
	.["refresh_queued"] = !!A.refresh_queued
	.["setup_pending"] = !!setup_pending?[A]
	var/datum/rx_state/rx = A.rx
	.["change_last"] = rx ? LAZYLEN(rx.change_last) : 0
	.["every_parked"] = rx ? LAZYLEN(rx.every_parked) : 0
	.["activations"] = rx ? LAZYLEN(rx.activations) : 0
	.["verbs"] = length(A.verbs)
	qdel(A)
	// What its teardown dropped on the tile (a fixture's bulb) goes too: the next instance starts on the tile this one found.
	for(var/atom/movable/left in at.contents - had)
		log_world("dq_init_plan_parity: [type] left [left.type] on its tile; removed")
		qdel(left)
