// The per-table caches of the ownership build (table_own_entries, table_owns_entries, table_hook_flags_cached) and the bucketed op clash
// check (op_clash_candidates) against the computations they replace, over every table this world has built. doc/rewrite/table_precompute.md.

/// The distinct compiled tables of this world (instance-type and block caches share most of them).
/proc/dq_cache_test_tables()
	var/list/seen = list()
	for(var/type in type_table_cache())
		var/datum/type_table/T = type_table_cache()[type]
		if(T)
			seen[T] = TRUE
	for(var/type in type_blocks_cache())
		var/datum/type_table/T = type_blocks_cache()[type]
		if(T)
			seen[T] = TRUE
	return seen

/proc/dq_own_entries_same(datum/own_entry/A, datum/own_entry/B)
	if(A == B)
		return TRUE
	return A.var_name == B.var_name && datum_signature(A.entry) == datum_signature(B.entry) && datum_signature(A.starts) == datum_signature(B.starts) \
		&& A.keep_after_destroy == B.keep_after_destroy && A.pool_reset == B.pool_reset && A.forward == B.forward && A.keyed_key == B.keyed_key

/datum/unit_test/dq_table_own_caches_equal_computed

/datum/unit_test/dq_table_own_caches_equal_computed/Run()
	var/checked = 0
	for(var/datum/type_table/T as anything in dq_cache_test_tables())
		var/list/cached = table_own_entries(T)
		var/list/fresh = table_own_entries_compute(T)
		TEST_ASSERT_EQUAL(length(cached), length(fresh), "[T.owner_type]: the cached own entries have the computed count")
		for(var/i in 1 to length(fresh))
			TEST_ASSERT(dq_own_entries_same(cached[i], fresh[i]), "[T.owner_type]: own entry [i] equals the computed one")
		var/list/owns = table_owns_entries(T)
		var/list/scan = list()
		for(var/datum/centry/C as anything in T.items)
			var/datum/entry/E = C.item
			if(istype(E) && (E.kind == ENTRY_OWNS_ONE || E.kind == ENTRY_OWNS_MANY))
				scan += E
		TEST_ASSERT_EQUAL(length(owns), length(scan), "[T.owner_type]: the cached owns scan has the scanned count")
		for(var/i in 1 to length(scan))
			TEST_ASSERT(owns[i] == scan[i], "[T.owner_type]: owns entry [i] is the scanned one")
		TEST_ASSERT_EQUAL(table_hook_flags_cached(T), table_hook_flags(T), "[T.owner_type]: the cached hook flags equal the computed ones")
		if(!isnull(T.hook_flags_cached))
			TEST_ASSERT_EQUAL(T.hook_flags_cached, table_hook_flags(T), "[T.owner_type]: a kept hook-flags value is current")
		checked++
	log_world("DQ_TABLE_CACHE: own caches equal the computed values over [checked] tables")
	TEST_ASSERT(checked > 100, "the test world built its tables ([checked])")

/datum/unit_test/dq_op_clash_candidates_equal_naive

/datum/unit_test/dq_op_clash_candidates_equal_naive/Run()
	var/tables = 0
	var/clashing = 0
	var/pairs_skipped = 0
	for(var/datum/type_table/T as anything in dq_cache_test_tables())
		var/datum/op_index/index = op_index_of_table(T)
		var/list/plans = index.ordered
		var/list/naive = list()
		for(var/i in 1 to length(plans))
			for(var/j in i + 1 to length(plans))
				if(op_plans_clash(plans[i], plans[j]))
					naive += "[i],[j]"
		var/list/candidates = op_clash_candidates(plans)
		var/list/bucketed = list()
		for(var/pair in candidates)
			TEST_ASSERT(pair[1] < pair[2], "[T.owner_type]: a candidate pair is ordered")
			if(op_plans_clash(plans[pair[1]], plans[pair[2]]))
				bucketed += "[pair[1]],[pair[2]]"
		TEST_ASSERT_EQUAL(jointext(bucketed, ";"), jointext(naive, ";"), "[T.owner_type]: the bucketed walk finds the same clashes in the same order")
		pairs_skipped += length(plans) * (length(plans) - 1) / 2 - length(candidates)
		clashing += length(naive)
		tables++
	log_world("DQ_TABLE_CACHE: clash candidates equal the naive walk over [tables] tables ([clashing] clashing pairs, [pairs_skipped] pairs not compared)")
