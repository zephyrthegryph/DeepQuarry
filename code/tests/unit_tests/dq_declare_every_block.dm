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
