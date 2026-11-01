// after(owner, delay, handler, ...): a call written with its owner missing used to return silently (the delay landed in the owner slot).

/datum/after_owner_probe
	var/fired = 0

/datum/after_owner_probe/proc/fire()
	fired++

/// A non-datum owner is a programmer error: the call reports a runtime and schedules nothing, on both clocks.
/datum/unit_test/dq_after_owner_misordered_is_loud

/datum/unit_test/dq_after_owner_misordered_is_loud/Run()
	test_driver_begin()
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	var/datum/after_owner_probe/probe = allocate(/datum/after_owner_probe)
	var/delay = 1 SECONDS // the misordered call goes through call() so the argument-order lint (which reads the source line) does not see it
	var/handler = TYPE_PROC_REF(/datum/after_owner_probe, fire)
	var/reported = 0
	var/own_id = 0
	var/world_id = 0
	// stack_trace() raises the runtime; the test catches it (a production call logs it and goes on).
	try
		own_id = call(GLOBAL_PROC_REF(after))(delay, handler, handler, null, CLOCK_OWN, list(probe))
	catch(var/exception/own_fault)
		reported++
		TEST_ASSERT(findtext(own_fault.name, "owner must be a datum"), "the report names the mistake: [own_fault.name]")
	try
		world_id = call(GLOBAL_PROC_REF(after))(delay, handler, handler, null, CLOCK_WORLD, list(probe))
	catch(var/exception/world_fault)
		reported++
		TEST_ASSERT(findtext(world_fault.name, "owner must be a datum"), "the report names the mistake: [world_fault.name]")
	TEST_ASSERT_EQUAL(reported, 2, "each misordered after() reports a runtime instead of returning silently")
	TEST_ASSERT(!own_id && !world_id, "a misordered after() schedules nothing")
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(probe.fired, 0, "a misordered after() never fires")

/// The correct form still schedules and fires, with a datum owner and with the global owner.
/datum/unit_test/dq_after_owner_correct_forms_fire

/datum/unit_test/dq_after_owner_correct_forms_fire/Run()
	test_driver_begin()
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	var/datum/after_owner_probe/probe = allocate(/datum/after_owner_probe)
	var/runtimes_at_start = GLOB.total_runtimes
	TEST_ASSERT(after(probe, 1 SECONDS, TYPE_PROC_REF(/datum/after_owner_probe, fire)), "an owned timer is scheduled")
	TEST_ASSERT(after(probe, 1 SECONDS, TYPE_PROC_REF(/datum/after_owner_probe, fire), clock = CLOCK_WORLD), "an owned world timer is scheduled")
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(probe.fired, 2, "both timers fire")
	TEST_ASSERT_EQUAL(GLOB.total_runtimes, runtimes_at_start, "the correct form reports nothing")

/// after(src, PROC_REF(x), delay) and a delay that is not a number: reported, and a number handler schedules nothing.
/datum/unit_test/dq_after_bad_delay_or_handler_is_loud

/datum/unit_test/dq_after_bad_delay_or_handler_is_loud/Run()
	test_driver_begin()
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	var/datum/after_owner_probe/probe = allocate(/datum/after_owner_probe)
	var/handler = TYPE_PROC_REF(/datum/after_owner_probe, fire)
	var/reported = 0
	var/swapped_id = 0
	try
		swapped_id = call(GLOBAL_PROC_REF(after))(probe, handler, 1 SECONDS)
	catch(var/exception/swapped_fault)
		reported++
		TEST_ASSERT(findtext(swapped_fault.name, "handler must be a proc reference"), "the report names the mistake: [swapped_fault.name]")
	TEST_ASSERT_EQUAL(reported, 1, "swapped arguments report a runtime")
	TEST_ASSERT(!swapped_id, "swapped arguments schedule nothing")
	try
		call(GLOBAL_PROC_REF(after))(probe, null, handler)
	catch(var/exception/null_delay_fault)
		reported++
		TEST_ASSERT(findtext(null_delay_fault.name, "delay must be a number"), "the report names the mistake: [null_delay_fault.name]")
	TEST_ASSERT_EQUAL(reported, 2, "a null delay reports a runtime")
	var/bad_with_id = 0
	var/bad_key_id = 0
	try
		bad_with_id = call(GLOBAL_PROC_REF(after))(probe, 1 SECONDS, handler, null, CLOCK_OWN, probe)
	catch(var/exception/with_fault)
		reported++
		TEST_ASSERT(findtext(with_fault.name, "with must be a list"), "the report names the mistake: [with_fault.name]")
	try
		bad_key_id = call(GLOBAL_PROC_REF(after))(probe, 1 SECONDS, handler, list(probe))
	catch(var/exception/key_fault)
		reported++
		TEST_ASSERT(findtext(key_fault.name, "key must be text"), "the report names the mistake: [key_fault.name]")
	TEST_ASSERT_EQUAL(reported, 4, "a bad with and a list in the key slot report a runtime")
	TEST_ASSERT(!bad_with_id && !bad_key_id, "neither schedules anything")

/// The declaration forms that would otherwise sit there and never run say so.
/datum/unit_test/dq_declare_dead_forms_are_loud

/datum/unit_test/dq_declare_dead_forms_are_loud/Run()
	var/list/old_capture = GLOB.declare_report_capture
	GLOB.declare_report_capture = list()
	var/not_a_notice = /datum/after_owner_probe
	var/bad_notice = on_notice(not_a_notice, then(TYPE_PROC_REF(/datum/after_owner_probe, fire)))
	var/empty_notice = on_notice(/datum/notice/ended)
	var/empty_change = on_change("fired", ANY)
	var/datum/after_owner_probe/held = allocate(/datum/after_owner_probe)
	release(held, "no such stat")
	var/read_unknown = stat_value(held, "no such stat either")
	var/bad_every = every(PROC_REF(fire_never), 1 SECONDS)
	var/empty_extend = extend("no parts here")
	var/no_edge = on_change("fired")
	observe(held, null, held)
	var/list/reports = GLOB.declare_report_capture
	GLOB.declare_report_capture = old_capture
	TEST_ASSERT(isnull(bad_notice) && isnull(empty_notice) && isnull(empty_change), "a dead form makes no entry")
	TEST_ASSERT(isnull(read_unknown) && isnull(bad_every) && isnull(empty_extend) && isnull(no_edge), "and neither do the others")
	TEST_ASSERT_EQUAL(length(reports), 9, "each dead form reports: [json_encode(reports)]")

/datum/unit_test/dq_declare_dead_forms_are_loud/proc/fire_never()
	return
