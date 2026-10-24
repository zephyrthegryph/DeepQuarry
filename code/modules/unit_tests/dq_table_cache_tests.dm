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

/// A table with ops that really clash (the world has none): the narrowed walk must still find every clash the all-pairs walk finds.
/datum/unit_test/dq_op_clash_candidates_find_synthetic_clashes

/datum/unit_test/dq_op_clash_candidates_find_synthetic_clashes/Run()
	GLOB.declare_report_capture = list()
	var/datum/type_table/T = table_compile(/obj/e2_box, null, list( \
		op("hand_a", hand(), then("note_pry")), \
		op("quiet", ui_act("quiet"), then("note_peek")), \
		op("hand_b", hand(), then("note_key")), \
		op("crow_a", tool(TOOL_CROWBAR), then("note_slide")), \
		op("ui_a", ui_act("shared"), then("note_peek")), \
		op("crow_b", tool(TOOL_CROWBAR), then("note_slide")), \
		op("ui_b", ui_act("shared"), then("note_peek")), \
		op("hand_c", hand(), priority(OP_PRIORITY_PART), then("note_key"))), "test:clash")
	var/list/reports = GLOB.declare_report_capture
	GLOB.declare_report_capture = null
	var/list/plans = op_index_of_table(T).ordered
	var/list/naive = list()
	for(var/i in 1 to length(plans))
		for(var/j in i + 1 to length(plans))
			if(op_plans_clash(plans[i], plans[j]))
				naive += "[i],[j]"
	TEST_ASSERT(length(naive) >= 3, "the fixture has clashing pairs under the all-pairs walk ([length(naive)])")
	var/list/bucketed = list()
	var/list/candidates = op_clash_candidates(plans)
	for(var/pair in candidates)
		if(op_plans_clash(plans[pair[1]], plans[pair[2]]))
			bucketed += "[pair[1]],[pair[2]]"
	TEST_ASSERT_EQUAL(jointext(bucketed, ";"), jointext(naive, ";"), "the narrowed walk finds the same clashes, in the same order")
	TEST_ASSERT(length(candidates) < length(plans) * (length(plans) - 1) / 2, "and compares fewer pairs than all of them")
	var/reported = 0
	for(var/report in reports)
		if(findtext(report, "[RULE_OP_CLASH]"))
			reported++
	TEST_ASSERT_EQUAL(reported, length(naive), "table_compile reported exactly the all-pairs clashes")
	log_world("DQ_TABLE_CACHE: synthetic clash fixture: [length(naive)] clashing pairs, [length(candidates)] of [length(plans) * (length(plans) - 1) / 2] pairs compared")

/// The original of type_trait_table_build(): `T in built_of_table` scans the keys, so it is quadratic in the tables. Reference for the equality test.
/proc/type_trait_table_scan(list/by_type, kind, trait_type)
	var/list/built_of_table = list()
	var/list/table = list()
	for(var/type in by_type)
		var/datum/type_table/T = by_type[type]
		if(!(T in built_of_table))
			var/datum/centry/C = static_find(T, kind)
			var/datum/entry/E = C?.item
			var/datum/type_trait/made = null
			if(E)
				made = new trait_type
				made.kind = kind
				made.apply_args(E.args)
			built_of_table[T] = made
		var/datum/type_trait/known = built_of_table[T]
		if(known)
			table[type] = known
	return table

/// Per static kind, the table built by the lookup version equals the scanning original: the same types, equal traits, and the same sharing
/// (types under one declaring table read one trait object in both).
/datum/unit_test/dq_type_trait_tables_equal_scan

/datum/unit_test/dq_type_trait_tables_equal_scan/Run()
	var/list/by_type = SSstatic_entries.tables_by_type
	TEST_ASSERT(length(by_type) > 100, "the static tables are built ([length(by_type)] types)")
	var/kinds = 0
	for(var/datum/entry_engine/type_trait/engine_type as anything in subtypesof(/datum/entry_engine/type_trait))
		var/datum/entry_engine/type_trait/engine = entry_engine_for(engine_type::kind)
		if(!engine)
			continue
		var/list/fast = type_trait_table_build(by_type, engine.kind, engine.trait_type)
		var/list/slow = type_trait_table_scan(by_type, engine.kind, engine.trait_type)
		var/list/live = GLOB.type_trait_tables[engine.kind]
		TEST_ASSERT_EQUAL(length(fast), length(slow), "[engine.kind]: the same number of types")
		TEST_ASSERT_EQUAL(length(live), length(slow), "[engine.kind]: the boot table has the same number of types")
		var/list/first_fast = list()
		var/list/first_slow = list()
		for(var/type in slow)
			TEST_ASSERT(!isnull(fast[type]), "[engine.kind]: [type] is in the lookup table")
			TEST_ASSERT_EQUAL(datum_signature(fast[type]), datum_signature(slow[type]), "[engine.kind]: [type] has equal trait values")
			if(!first_fast[fast[type]])
				first_fast[fast[type]] = type
			if(!first_slow[slow[type]])
				first_slow[slow[type]] = type
			TEST_ASSERT_EQUAL(first_fast[fast[type]], first_slow[slow[type]], "[engine.kind]: [type] shares its trait with the same types")
		kinds++
	log_world("DQ_TABLE_CACHE: type trait tables equal the scanning build over [kinds] kinds")
	TEST_ASSERT(kinds > 0, "there are type trait kinds")

// ---- interned entry signatures ----
// The signature builders inline their leaf cases for boot speed. These are the plain forms they replaced: every interned entry and part
// must still carry exactly the signature the plain form computes, and no two interned objects may share one.

/proc/dq_ref_datum_signature(value, depth = 0)
	if(isnull(value))
		return "~"
	if(isnum(value))
		return "n[value]"
	if(istext(value))
		return "t[length(value)]:[value]"
	if(ispath(value))
		return "p[value]"
	if(depth > 8)
		return "?"
	if(islist(value))
		var/list/L = value
		var/list/parts = list()
		for(var/i in 1 to length(L))
			var/k = L[i]
			var/entry = dq_ref_datum_signature(k, depth + 1)
			if(!isnum(k) && !isnull(k) && !isnull(L[k]))
				entry += "=" + dq_ref_datum_signature(L[k], depth + 1)
			parts += entry
		return "\[[jointext(parts, ",")]]"
	if(isatom(value))
		var/atom/A = value
		return "a[SHARED_CACHE_UID(A)]"
	if(isdatum(value))
		var/datum/D = value
		var/list/parts = list()
		for(var/name in signature_vars_of(D))
			var/v = D.vars[name]
			if(v == initial(D.vars[name]))
				continue
			parts += "[name]:[dq_ref_datum_signature(v, depth + 1)]"
		return "d[D.type]{[jointext(parts, ";")]}"
	return "x[value]"

/proc/dq_ref_value_signature(value)
	if(istype(value, /datum/entry))
		var/datum/entry/E = value
		return "e:[E.sig]"
	if(islist(value))
		var/list/L = value
		var/list/parts = list()
		for(var/i in 1 to length(L))
			var/k = L[i]
			var/part = dq_ref_value_signature(k)
			if(!isnum(k) && !isnull(k) && !isdatum(k) && !islist(k) && !isnull(L[k]))
				part += "=" + dq_ref_value_signature(L[k])
			parts += part
		return "\[[jointext(parts, ",")]]"
	if(istype(value, /datum/capability))
		var/datum/capability/def = value
		return "c:[def.type]:[def.key]:[def.ctor ? dq_ref_value_signature(def.ctor) : ""]"
	return dq_ref_datum_signature(value)

/proc/dq_ref_entry_signature(kind, key, list/args, list/children)
	var/list/parts = list(kind, isnull(key) ? "~" : "k[key]")
	for(var/name in args)
		parts += "[name]=[dq_ref_value_signature(args[name])]"
	for(var/child in children)
		parts += "(" + dq_ref_value_signature(child) + ")"
	return jointext(parts, "|")

/// Checks one entry (and its children) against the plain signature build: counts it in seen, and appends a line to bad on a mismatch.
/proc/dq_check_entry_signature(datum/entry/E, list/seen, list/bad)
	if(!E || seen[E])
		return
	seen[E] = TRUE
	if(istype(E, /datum/entry/block) || istype(E, /datum/entry/line) || istype(E, /datum/entry/skip_built))
		return
	var/expected = dq_ref_entry_signature(E.kind, E.key, E.args, E.children)
	if(istype(E, /datum/entry/part))
		expected = "[E.type]|" + dq_ref_entry_signature(ENTRY_OP_PART, null, E.args, E.children)
	if(E.sig != expected)
		bad += "[E.sig] != [expected]"
	for(var/datum/entry/child in E.children)
		dq_check_entry_signature(child, seen, bad)

/datum/unit_test/dq_interned_entry_signatures_unchanged

/datum/unit_test/dq_interned_entry_signatures_unchanged/Run()
	var/list/seen = list()
	var/list/bad = list()
	var/probes = 0
	var/list/types = list()
	for(var/t in typesof(/obj/item) + typesof(/obj/machinery))
		if(ispath(t, /obj/item/projectile) || findtext("[t]", "/spawner"))
			continue
		types += t
		if(length(types) >= 250)
			break
	for(var/t in types)
		var/atom/movable/probe = new t(null)
		var/list/chain = list()
		probe.declared_entries(chain)
		for(var/datum/entry/E in chain)
			dq_check_entry_signature(E, seen, bad)
		probes++
		qdel(probe)
	for(var/sig in GLOB.caps_interned)
		var/datum/capability/C = GLOB.caps_interned[sig]
		TEST_ASSERT_EQUAL(sig, dq_ref_datum_signature(C), "an interned capability's signature equals the plain build")
	TEST_ASSERT(!length(bad), "entry signatures differ from the plain build: [length(bad)], first [bad[1]]")
	TEST_ASSERT(length(seen) > 100, "the probes declared entries (got [length(seen)])")
	log_world("DQ_SIGNATURES probes=[probes] entries=[length(seen)] caps=[length(GLOB.caps_interned)]")
