// Every CAPABILITIES block compiles clean. A type's table is built lazily, on its first instance (code/engine/declare/table.dm), so a
// declaration error in a type nobody spawns in a test world would never be reported. This builds the table of every block type
// (declared_block_types(), generated) with table_of_type(), which makes no instance, and fails on any declaration report.

/datum/unit_test/dq_declare_every_block_compiles

/datum/unit_test/dq_declare_every_block_compiles/Run()
	var/list/old_capture = GLOB.declare_report_capture
	GLOB.declare_report_capture = list()
	var/started = REALTIMEOFDAY
	var/compiled = 0
	var/list/uncovered = list()
	for(var/type in declared_block_types())
		if(type_blocks_cache()[type])
			continue
		if(!table_of_type(type))
			uncovered += type
			continue
		compiled++
	var/list/reports = GLOB.declare_report_capture
	GLOB.declare_report_capture = old_capture
	log_test("dq_declare_every_block_compiles: compiled [compiled] block types in [(REALTIMEOFDAY - started) / 10] s; not covered: [length(uncovered) ? jointext(uncovered, ", ") : "none"]")
	for(var/message in reports)
		TEST_FAIL("declaration error: [message]")
	TEST_ASSERT(!length(uncovered), "every block type has a table without an instance, uncovered: [jointext(uncovered, ", ")]")
	// A table built without an instance is the real one: every block type's table has items, and a known type's instance-free chain is the
	// chain its instance brings (an empty table here once passed this sweep and was cached for every later test in the world).
	var/list/empty = list()
	for(var/type in declared_block_types())
		var/datum/type_table/T = table_of_type(type)
		if(T && !length(T.items) && !length(T.caps))
			empty += type
	TEST_ASSERT(length(empty) < length(declared_block_types()) / 2, "most block types compile to entries, [length(empty)] of [length(declared_block_types())] are empty: [jointext(empty.Copy(1, min(length(empty), 20) + 1), ", ")]")
	var/datum/type_table/known = table_of_type(/obj/e1_fixture)
	TEST_ASSERT(length(known?.items), "the e1 fixture's instance-free table has entries")
	var/list/by_proc = list()
	var/list/block_procs = list()
	for(var/at = /obj/e1_fixture; at; at = type2parent(at))
		if(declared_entries_procs()[at])
			block_procs.Insert(1, declared_entries_procs()[at])
	for(var/block_proc in block_procs)
		call(block_proc)(by_proc)
	var/obj/e1_fixture/F = new(run_loc_floor_bottom_left)
	var/list/by_instance = list()
	F.declared_entries(by_instance)
	TEST_ASSERT_EQUAL(length(by_proc), length(by_instance), "the instance-free chain is the instance's chain")
	TEST_ASSERT(table_of(F) == known, "the instance reads the table built without one")
	qdel(F)

/// A click_on() handler that is neither a proc of the type nor an op key is a build error.
/datum/unit_test/dq_declare_silent_mistakes_are_loud

/datum/unit_test/dq_declare_silent_mistakes_are_loud/Run()
	var/list/old_capture = GLOB.declare_report_capture
	GLOB.declare_report_capture = list()
	table_compile(/obj/e1_fixture, null, list(click_on("no_such_handler")), "inputfile.dm:5")
	var/list/errors = GLOB.declare_report_capture
	TEST_ASSERT_EQUAL(length(errors), 1, "an unknown click handler is one error, got [json_encode(errors)]")
	if(length(errors))
		TEST_ASSERT(findtext(errors[1], "[RULE_INPUT_HANDLER]") && findtext(errors[1], "no_such_handler") && findtext(errors[1], "inputfile.dm:5"), "it names rule, handler and line: [errors[1]]")
	GLOB.declare_report_capture = list()
	table_compile(/obj/e1_fixture, null, list(entry_of("op", "toggle"), click_on("toggle"), click_on("examine")), "inputfile.dm:6")
	TEST_ASSERT_EQUAL(length(GLOB.declare_report_capture), 0, "an op key or a proc is a valid handler, got [json_encode(GLOB.declare_report_capture)]")
	// extend() of a tag: one some op carries resolves, any other number past TAG_BASE is a declaration error (the generated tag registry).
	GLOB.declare_report_capture = list()
	table_compile(/obj/e1_fixture, null, list(extend(TAG_CONTROL, needs(req_empty_hand())), extend(TAG_UI, needs(req_empty_hand()))), "inputfile.dm:7")
	TEST_ASSERT_EQUAL(length(GLOB.declare_report_capture), 0, "a declared tag resolves, got [json_encode(GLOB.declare_report_capture)]")
	GLOB.declare_report_capture = list()
	table_compile(/obj/e1_fixture, null, list(extend(TAG_BASE + 900, needs(req_empty_hand()))), "inputfile.dm:8")
	TEST_ASSERT_EQUAL(length(GLOB.declare_report_capture), 1, "a tag no op carries is one error, got [json_encode(GLOB.declare_report_capture)]")
	TEST_ASSERT(declared_op_tags()["[TAG_POD_ENTER]"], "the registry lists a tag a library op carries")
	GLOB.declare_report_capture = old_capture
