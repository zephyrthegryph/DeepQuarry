/// The cadence vocabulary on systems: CADENCE_* are the periodic pipelines, periodic_interval overrides.

/datum/system/test_cadence_default
	abstract_type = /datum/system/test_cadence_default
	periodic_cadence = CADENCE_SECOND

/datum/system/test_cadence_override
	abstract_type = /datum/system/test_cadence_override
	periodic_cadence = CADENCE_SECOND
	periodic_interval = 7

/datum/system/test_cadence_reactive
	abstract_type = /datum/system/test_cadence_reactive

/datum/unit_test/kernel_cadence

/datum/unit_test/kernel_cadence/Run()
	var/list/expected = list(
		CADENCE_FAST = 2, CADENCE_SECOND = 10, CADENCE_SLOW = 20, CADENCE_MINUTE = 600,
	)
	for(var/path in expected)
		var/datum/om/pipeline/periodic/P = path
		TEST_ASSERT(ispath(path, /datum/om/pipeline/periodic), "[path] is a periodic pipeline")
		TEST_ASSERT_EQUAL(initial(P.delta), expected[path], "[path] step in deciseconds")
	var/datum/om/pipeline/periodic/minute/M = CADENCE_MINUTE
	TEST_ASSERT_EQUAL(initial(M.every), 1 MINUTES, "the minute cadence runs once a minute")

	var/datum/system/plain = new /datum/system/test_cadence_default
	TEST_ASSERT_EQUAL(plain.step_interval(), 10, "a system runs at its cadence's step")
	var/datum/system/custom = new /datum/system/test_cadence_override
	TEST_ASSERT_EQUAL(custom.step_interval(), 7, "periodic_interval overrides the cadence")
	var/datum/system/reactive = new /datum/system/test_cadence_reactive
	TEST_ASSERT_EQUAL(reactive.step_interval(), 0, "a reactive system has no interval")
	TEST_ASSERT_NULL(reactive.periodic_cadence, "and no cadence")
	check_work_item_interval()

/// A work item's cadence is its interval: due when first seen, then once per interval, re-armed from the run.
/datum/unit_test/kernel_cadence/proc/check_work_item_interval()
	var/datum/controller/kernel/K = new
	var/datum/test_work_owner/O = new
	var/datum/work_item/test_fixture/W = K.register_work(/datum/test_work_owner, test_work_item(O, interval = 20))
	for(var/now in list(0, 10, 20, 30, 40, 50))
		K.run_item(W, WORK_TEST_LIMIT, now)
	TEST_ASSERT_EQUAL(length(O.calls), 3, "a 20 ds work item runs at 0, 20 and 40 of 0..50")
