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

/// The one override rule (table_add_item()): a later declaration of a key replaces the earlier entry at its position, a new key appends. A
/// subtype's re-declared op keeps its parent's place in the op index (the menu and click order), and a re-declared relation keeps its place
/// among the relations. Real types this moved when the rule became one: the /robot tgui modules' ui_open now sits where /datum/tgui_module
/// declares it.
/datum/unit_test/dq_table_override_keeps_position

/datum/unit_test/dq_table_override_keeps_position/Run()
	var/list/old_capture = GLOB.declare_report_capture
	GLOB.declare_report_capture = list()
	var/datum/type_table/parent = table_compile(/obj/e1_fixture, null, list(entry_of("op", "first"), entry_of("op", "middle"), entry_of("op", "last"), ref_one("rel_a"), ref_one("rel_b")), "parent.dm:1")
	var/datum/type_table/child = table_compile(/obj/e1_fixture, parent, list(entry_of("op", "middle"), entry_of("op", "added"), ref_one("rel_a", on_other_deleted = OTHER_DELETE_ME)), "child.dm:1")
	GLOB.declare_report_capture = old_capture
	var/list/keys = list()
	for(var/datum/op_plan/P as anything in op_index_of_table(child).ordered)
		keys += P.key
	TEST_ASSERT_EQUAL(jointext(keys, ","), "first,middle,last,added", "a re-declared op keeps the parent's position, a new one appends")
	var/datum/op_plan/middle = op_index_of_table(child).by_key["middle"]
	TEST_ASSERT_EQUAL(middle?.origin, "child.dm:1", "the re-declaration is the one kept")
	var/list/rels = list()
	var/ops = 0
	for(var/datum/centry/C as anything in child.items)
		var/datum/entry/E = C.item
		if(E.kind == ENTRY_REF_ONE)
			rels += "[E.args["var"]]@[C.origin]"
		if(E.kind == "op")
			ops++
	TEST_ASSERT_EQUAL(jointext(rels, ","), "rel_a@child.dm:1,rel_b@parent.dm:1", "a re-declared relation keeps its position")
	TEST_ASSERT_EQUAL(ops, 4, "the table holds one entry per op key")
	TEST_ASSERT_EQUAL(length(parent.items), 5, "the parent's table is unchanged")
