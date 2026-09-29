/// The cadence vocabulary (code/controllers/kernel/cadence.dm).

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
		CADENCE_FAST = 0.2 SECONDS, CADENCE_SECOND = 1 SECONDS, CADENCE_SLOW = 2 SECONDS,
		CADENCE_LIFE = LIFE_CYCLE, CADENCE_MINUTE = 1 MINUTES,
	)
	for(var/path in expected)
		var/datum/cadence/C = cadence(path)
		TEST_ASSERT_NOTNULL(C, "[path] is a cadence")
		TEST_ASSERT_EQUAL(C.interval_ds(), expected[path], "[path] interval")
		TEST_ASSERT_EQUAL(cadence(path), C, "a cadence is a singleton")
		TEST_ASSERT_EQUAL(C.max_interval_ds(), expected[path] * 4, "[path] may run four intervals late by default")
	var/datum/cadence/tick = cadence(CADENCE_TICK)
	TEST_ASSERT_EQUAL(tick.interval_ds(), world.tick_lag, "the tick cadence is one tick")
	var/datum/cadence/life = cadence(CADENCE_LIFE)
	TEST_ASSERT_EQUAL(life.clock, CLOCK_BIO, "life counts on the bio clock")
	TEST_ASSERT_NULL(cadence(/datum/cadence), "the abstract base is not a cadence")
	TEST_ASSERT_NULL(cadence(/datum/system), "a non-cadence path is refused")

	var/datum/system/plain = new /datum/system/test_cadence_default
	TEST_ASSERT_EQUAL(plain.step_interval(), 1 SECONDS, "a system runs at its cadence's interval")
	var/datum/system/custom = new /datum/system/test_cadence_override
	TEST_ASSERT_EQUAL(custom.step_interval(), 7, "periodic_interval overrides the cadence")
	var/datum/system/reactive = new /datum/system/test_cadence_reactive
	TEST_ASSERT_NULL(reactive.system_cadence(), "a reactive system has no cadence")
	TEST_ASSERT_EQUAL(reactive.step_interval(), 0, "and no interval")
