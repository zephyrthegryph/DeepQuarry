// A subtype table's op index shares its parent's plans (op_inherited_base(), code/engine/parts/plan.dm) instead of rebuilding them.

/// What tells two compiled plans apart: where it came from, its position and tier, and every part folded into it.
/proc/dq_op_plan_text(datum/op_plan/P)
	return "[P.key]|[P.base_key]|[P.origin]|[P.owner]|[P.seq]|[P.tier]|[P.claim_mask]|[P.priority_tier]|[length(P.bindings)]|[length(P.needs)]|[length(P.effects)]|[length(P.steps)]|[length(P.conds)]|[jointext(P.provenance || list(), ";")]|[jointext(P.problems || list(), ";")]|[json_encode(P.click_below)]"

/// Every compiled table's op index, built by the compiler (inherited plans shared), equals one built from scratch over the same items.
/datum/unit_test/dq_op_index_inherit_parity

/datum/unit_test/dq_op_index_inherit_parity/Run()
	var/list/seen = list()
	var/tables = 0
	for(var/type in type_table_cache())
		var/datum/type_table/T = type_table_cache()[type]
		if(!T || seen[T] || !T.op_index)
			continue
		seen[T] = TRUE
		var/list/extends = list()
		for(var/datum/centry/C as anything in T.items)
			var/datum/entry/E = C.item
			if(istype(E) && E.kind == ENTRY_EXTEND)
				extends += C
		var/datum/op_index/fresh = op_index_build(T, T.items, extends, FALSE)
		var/datum/op_index/built = T.op_index
		tables++
		TEST_ASSERT_EQUAL(length(built.ordered), length(fresh.ordered), "[T.owner_type]: the number of ops")
		TEST_ASSERT_EQUAL(built.has_clicks, fresh.has_clicks, "[T.owner_type]: has_clicks")
		for(var/i in 1 to length(fresh.ordered))
			TEST_ASSERT_EQUAL(dq_op_plan_text(built.ordered[i]), dq_op_plan_text(fresh.ordered[i]), "[T.owner_type]: op [i]")
		for(var/key in fresh.by_key)
			TEST_ASSERT(built.by_key[key], "[T.owner_type]: op [key] missing")
			TEST_ASSERT_EQUAL(dq_op_plan_text(built.by_key[key]), dq_op_plan_text(fresh.by_key[key]), "[T.owner_type]: by_key [key]")
	TEST_ASSERT(tables > 100, "tables checked ([tables])")
	TEST_ASSERT(GLOB.op_plans_inherited > 0, "no plan was shared from a parent table")
	log_world("dq_op_index_inherit_parity: [tables] tables; plans built [GLOB.op_plans_built], inherited [GLOB.op_plans_inherited]")
