// The generated STAGE_DEF, SOURCE_DEF and cap_keys declarations are emitted in .dme include order (tools/analyze/src/sem/decls.rs), so a file move
// never reorders them. Their readers (stage_defs_build(), source_is_valid(), cap_keys_build()) make keyed lookups by a unique id and nothing iterates the
// result: this pins that an id finds its own declaration whatever order the declarations are in, and that no id is declared twice.

/// stage_key() answers each declared stage id with the key of the one STAGE_DEF that declares it; no id is declared twice.
/datum/unit_test/dq_declared_stage_lookup_is_order_free

/datum/unit_test/dq_declared_stage_lookup_is_order_free/Run()
	var/list/seen = list()
	for(var/def_type in subtypesof(/datum/stage_def))
		var/datum/stage_def/D = new def_type
		var/list/row = D.spec()
		TEST_ASSERT(length(row), "[def_type] declares a stage")
		var/id = "[row[1]]"
		TEST_ASSERT(!seen[id], "stage id [id] is declared once ([def_type] and [seen[id]])")
		seen[id] = "[def_type]"
		TEST_ASSERT_EQUAL(stage_key(row[1]), "[row[2]]_[row[3]]", "[def_type]: its id finds its own key")
	TEST_ASSERT(length(seen) > 100, "the declared stages were read")
	TEST_ASSERT_EQUAL(stage_key(STAGE_DOOR_FRAME), "door_frame", "a known stage id finds its key")
	TEST_ASSERT_EQUAL(stage_key(STAGE_LIGHTSWITCH_FRAME), "lightswitch_frame", "and a stage of a moved file does too")

/// source_is_valid() accepts each declared source id once.
/datum/unit_test/dq_declared_source_lookup_is_order_free

/datum/unit_test/dq_declared_source_lookup_is_order_free/Run()
	var/list/seen = list()
	for(var/def_type in subtypesof(/datum/source_def))
		var/datum/source_def/S = new def_type
		var/list/row = S.spec()
		TEST_ASSERT(length(row), "[def_type] declares a source")
		var/id = "[row[1]]"
		TEST_ASSERT(!seen[id], "source id [id] is declared once ([def_type] and [seen[id]])")
		seen[id] = "[def_type]"
		TEST_ASSERT(source_is_valid(row[1]), "[def_type]: its id is a valid source")
	TEST_ASSERT(length(seen) > 20, "the declared sources were read")

/// cap_key_bit() answers each declared state key with its position in its own capability's list; no capability declares its keys twice.
/datum/unit_test/dq_declared_cap_keys_lookup_is_order_free

/datum/unit_test/dq_declared_cap_keys_lookup_is_order_free/Run()
	var/list/seen = list()
	for(var/decl_type in subtypesof(/datum/cap_keys_decl))
		var/datum/cap_keys_decl/D = new decl_type
		var/list/row = D.spec()
		TEST_ASSERT(length(row), "[decl_type] declares state keys")
		var/id = "[row[1]]"
		TEST_ASSERT(!seen[id], "capability [id] declares its keys once ([decl_type] and [seen[id]])")
		seen[id] = "[decl_type]"
		var/list/keys = row[2]
		var/bit = 0
		for(var/name in keys)
			bit++
			TEST_ASSERT_EQUAL(cap_key_bit(row[1], name), bit, "[decl_type]: key [name] is bit [bit]")
	TEST_ASSERT(length(seen) > 5, "the declared state keys were read")
