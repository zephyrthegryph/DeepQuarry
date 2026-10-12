// Exercise the real guards without emitting intentional failure diagnostics.
/datum/unit_test/dq_state_leak_guard/Run()
	set_global(nameof(GLOB.test_prompts), null)
	var/list/before = unit_test_globals_snapshot()
	set_global(nameof(GLOB.test_prompts), list("pending fixture prompt"))
	var/reason = unit_test_globals_guard(before, type, FALSE)
	TEST_ASSERT(reason && findtext(reason, "GLOB.test_prompts"), "A real null-to-list mutation returns its named leak")
	TEST_ASSERT_EQUAL(length(GLOB.test_prompts), 1, "Detection does not silently restore or discard live state")
	TEST_ASSERT_EQUAL(unit_test_leak_status(UNIT_TEST_PASSED, FALSE, reason), UNIT_TEST_FAILED, "The runner cannot retain a passing JSON status for the detected leak")
	TEST_ASSERT_EQUAL(unit_test_leak_status(UNIT_TEST_FAILED, FALSE, reason), UNIT_TEST_FAILED, "An existing failure remains failed")
	TEST_ASSERT_EQUAL(unit_test_leak_status(UNIT_TEST_SKIPPED, TRUE, reason), UNIT_TEST_SKIPPED, "Skipped fixtures remain skipped")
	set_global(nameof(GLOB.test_prompts), null)
	TEST_ASSERT_NULL(unit_test_globals_guard(before, type, FALSE), "Restoring the actual fixture state clears the leak")
	TEST_ASSERT_EQUAL(unit_test_leak_status(UNIT_TEST_PASSED, FALSE, null), UNIT_TEST_PASSED, "Clean teardown preserves a pass")

/datum/unit_test/dq_state_leak_guard/flag/Run()
	set_global(nameof(GLOB.test_prompts), FALSE)
	var/list/before = unit_test_globals_snapshot()
	set_global(nameof(GLOB.test_prompts), TRUE)
	var/reason = unit_test_globals_guard(before, type, FALSE)
	TEST_ASSERT(reason && findtext(reason, "GLOB.test_prompts"), "A real changed global flag becomes a failure reason")
	TEST_ASSERT_EQUAL(unit_test_leak_status(UNIT_TEST_PASSED, FALSE, reason), UNIT_TEST_FAILED, "Flag leaks fail the same final-result path")
	set_global(nameof(GLOB.test_prompts), FALSE)
	TEST_ASSERT_NULL(unit_test_globals_guard(before, type, FALSE), "Restored flags are clean")

/datum/unit_test/dq_state_leak_guard/gravity/Run()
	var/area/A = get_area(test_floor())
	var/original = A.has_gravity
	defer_cleanup(A, TYPE_PROC_REF(/area, gravitychange), original)
	var/list/before = list()
	before[A] = original
	A.gravitychange(!original)
	TEST_ASSERT_NOTEQUAL(A.has_gravity, original, "The real area changed gravity")
	var/reason = unit_test_gravity_guard(before, type, FALSE)
	TEST_ASSERT(reason && findtext(reason, "has_gravity"), "The real area guard reports leaked gravity")
	TEST_ASSERT_EQUAL(unit_test_leak_status(UNIT_TEST_PASSED, FALSE, reason), UNIT_TEST_FAILED, "Gravity leaks fail the same final-result path")
	A.gravitychange(original)
	TEST_ASSERT_NULL(unit_test_gravity_guard(before, type, FALSE), "Restored area gravity is clean")

/datum/unit_test/dq_state_leak_guard/dview_cache/Run()
	var/mob/dview/cached = GLOB.dview_mob
	TEST_ASSERT_NOTNULL(cached, "Real dview singleton is initialized before fixture execution")
	TEST_ASSERT_NULL(cached.loc, "Shared visibility cache is parked outside the test floor")
	dview(0, test_floor())
	TEST_ASSERT_EQUAL(GLOB.dview_mob, cached, "Actual view call retains production singleton identity")
	TEST_ASSERT_NULL(cached.loc, "Actual view call restores parked location after reading the floor")
	TEST_ASSERT(!QDELETED(cached), "Fixture never deletes the shared visibility cache")

// An instance-only probe uses the real unit-test New and on_destroy lifecycle.
/datum/unit_test/dq_state_leak_guard/prompt_probe
	abstract_type = /datum/unit_test/dq_state_leak_guard/prompt_probe

/datum/unit_test/dq_state_leak_guard/prompt_list_isolation/Run()
	var/datum/prompt/text/existing = allocate(/datum/prompt/text)
	var/datum/prompt/text/appended = allocate(/datum/prompt/text)
	var/list/prior = list(existing)
	set_global(nameof(GLOB.test_prompts), prior)
	var/datum/unit_test/dq_state_leak_guard/prompt_probe/probe = allocate(/datum/unit_test/dq_state_leak_guard/prompt_probe)
	var/datum/unit_test_block/block = probe.test_block
	defer_cleanup(src, PROC_REF(release_prompt_probe), probe, block)
	TEST_ASSERT(GLOB.test_prompts != prior, "Real fixture constructor isolates the nonnull prompt list")
	TEST_ASSERT_EQUAL(GLOB.test_prompts[1], existing, "Isolation preserves the actual prior prompt identity")
	// This is the same in-place append performed by request_open's recording path.
	GLOB.test_prompts += appended
	TEST_ASSERT_EQUAL(length(GLOB.test_prompts), 2, "The live fixture scratch list receives the actual prompt")
	TEST_ASSERT_EQUAL(GLOB.test_prompts[2], appended, "The appended prompt is retained in the private recording list")
	TEST_ASSERT_EQUAL(length(prior), 1, "Appending never mutates the saved original recording list")
	TEST_ASSERT_EQUAL(prior[1], existing, "The saved original retains its sole actual prompt")
	qdel(probe)
	TEST_ASSERT_EQUAL(GLOB.test_prompts, prior, "Normal fixture teardown restores the original list identity")
	TEST_ASSERT_EQUAL(length(GLOB.test_prompts), 1, "Normal teardown restores the original prompt contents")
	TEST_ASSERT_EQUAL(GLOB.test_prompts[1], existing, "Normal teardown preserves the original prompt identity")

/datum/unit_test/dq_state_leak_guard/prompt_list_isolation/proc/release_prompt_probe(datum/unit_test/probe, datum/unit_test_block/block)
	if(!QDELETED(probe))
		qdel(probe)
	var/reason = release_unit_test_block(block, probe)
	if(reason)
		Fail(reason)

// Instance-only probe exercises the real wrapper and normal scope teardown.
/datum/unit_test/dq_state_leak_guard/counter_probe
	abstract_type = /datum/unit_test/dq_state_leak_guard/counter_probe

/datum/unit_test/dq_state_leak_guard/counter_probe/Run()
	GLOB.coalesce_runs++
	// Simulate the last observation being before a real wall-clock rollover.
	GLOB.rollovercheck_last_timeofday = world.timeofday + 1 SECOND
	GLOB.rollover_safety_date = world.realtime - 13 HOURS
	update_midnight_rollover()

/datum/unit_test/dq_state_leak_guard/counter_scope/Run()
	var/coalesce_before = GLOB.coalesce_runs
	var/midnight_before = GLOB.midnight_rollovers
	var/last_before = GLOB.rollovercheck_last_timeofday
	var/safety_before = GLOB.rollover_safety_date
	var/datum/unit_test/dq_state_leak_guard/counter_probe/probe = allocate(/datum/unit_test/dq_state_leak_guard/counter_probe)
	var/datum/unit_test_block/block = probe.test_block
	defer_cleanup(src, PROC_REF(release_counter_probe), probe, block)
	probe.RunWrapped()
	TEST_ASSERT_EQUAL(GLOB.coalesce_runs, coalesce_before + 1, "Real wrapper allows the fixture's diagnostic counter change")
	TEST_ASSERT_EQUAL(GLOB.midnight_rollovers, midnight_before + 1, "Actual clock helper observes the simulated rollover")
	lifeform_end(probe, END_SCOPE)
	TEST_ASSERT_EQUAL(GLOB.coalesce_runs, coalesce_before, "Normal teardown restores exact prior coalesce diagnostic")
	TEST_ASSERT_EQUAL(GLOB.midnight_rollovers, midnight_before, "Normal teardown restores exact prior midnight count")
	TEST_ASSERT_EQUAL(GLOB.rollovercheck_last_timeofday, last_before, "Clock observation is restored with its count")
	TEST_ASSERT_EQUAL(GLOB.rollover_safety_date, safety_before, "Clock safety timestamp retains its original value")

/datum/unit_test/dq_state_leak_guard/counter_scope/proc/release_counter_probe(datum/unit_test/probe, datum/unit_test_block/block)
	if(!QDELETED(probe))
		lifeform_end(probe, END_SCOPE)
	var/reason = release_unit_test_block(block, probe)
	if(reason)
		Fail(reason)
