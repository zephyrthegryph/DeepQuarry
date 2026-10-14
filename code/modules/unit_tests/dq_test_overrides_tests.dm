/// A global for set_global() that starts out null.
GLOBAL_VAR(dq_test_override_global)

/// A fixture for set_var(): a plain datum with a var to change.
/datum/dq_test_override_fixture
	var/value = "original"

/// set_var(), set_global() and set_config() put everything back when the test is torn down, even a
/// value that started out null, so a failing assert can't leak the change into later tests.
/datum/unit_test/dq_test_overrides_restore

/datum/unit_test/dq_test_overrides_restore/Run()
	var/datum/dq_test_override_fixture/fixture = new
	var/old_gesture = GLOB.dq_test_override_global
	var/old_addict = CONFIG_GET(flag/can_addict_during_round)

	set_var(fixture, "value", "changed")
	set_var(fixture, "value", "changed again") // a second change keeps the first original
	set_global("dq_test_override_global", "dq_test_gesture")
	set_config(/datum/config_entry/flag/can_addict_during_round, !old_addict)
	TEST_ASSERT_EQUAL(fixture.value, "changed again", "set_var did not set the var")
	TEST_ASSERT_EQUAL(GLOB.dq_test_override_global, "dq_test_gesture", "set_global did not set the global")
	TEST_ASSERT_EQUAL(CONFIG_GET(flag/can_addict_during_round), !old_addict, "set_config did not set the entry")

	restore_test_overrides() // what on_destroy() runs
	TEST_ASSERT_EQUAL(fixture.value, "original", "set_var did not restore the first original value")
	TEST_ASSERT_EQUAL(GLOB.dq_test_override_global, old_gesture, "set_global did not restore the global (null included)")
	TEST_ASSERT_EQUAL(CONFIG_GET(flag/can_addict_during_round), old_addict, "set_config did not restore the entry")
	TEST_ASSERT(!saved_vars && !saved_configs, "restore left saved overrides behind")
	qdel(fixture)
