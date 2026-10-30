#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

SERIAL_DEF(test_plain, 5, FALSE)
SERIAL_DEF(test_saved, 1, TRUE)

/// Drops a test kind's counter so a test leaves no serial state behind.
/proc/serial_test_forget(kind)
	GLOB.serial_counters -= kind

/datum/unit_test/dq_serial_counts_from_first_and_resets
/datum/unit_test/dq_serial_counts_from_first_and_resets/Run()
	TEST_ASSERT_EQUAL(next_serial(test_plain), 5, "a kind starts at its first number")
	TEST_ASSERT_EQUAL(next_serial(test_plain), 6, "the next take counts on")
	serial_reset(test_plain)
	TEST_ASSERT_EQUAL(next_serial(test_plain), 5, "a reset starts the kind again at its first number")
	serial_test_forget(/datum/serial/test_plain)

/datum/unit_test/dq_serial_keys_count_separately
/datum/unit_test/dq_serial_keys_count_separately/Run()
	TEST_ASSERT_EQUAL(next_serial_keyed(test_plain, "a"), 5, "first take of key a")
	TEST_ASSERT_EQUAL(next_serial_keyed(test_plain, "a"), 6, "second take of key a")
	TEST_ASSERT_EQUAL(next_serial_keyed(test_plain, "b"), 5, "key b has its own run")
	TEST_ASSERT_EQUAL(next_serial(test_plain), 5, "the unkeyed run is separate from the keyed ones")
	serial_test_forget(/datum/serial/test_plain)

/datum/unit_test/dq_serial_persisted_needs_a_seed
/datum/unit_test/dq_serial_persisted_needs_a_seed/Run()
	// An unseeded persisted kind refuses to issue and reports it with a stack trace, which the runtime capture would fail: only the seeded path runs here.
	var/datum/serial/saved = serial_for(/datum/serial/test_saved)
	TEST_ASSERT_NULL(saved.next_number, "a persisted kind starts unseeded")
	serial_seed(test_saved, 41)
	TEST_ASSERT_EQUAL(next_serial(test_saved), 42, "a seeded kind continues after the saved number")
	TEST_ASSERT_EQUAL(next_serial(test_saved), 43, "and counts on")
	serial_test_forget(/datum/serial/test_saved)

/datum/unit_test/dq_serial_sequential_id_keeps_its_numbers
/datum/unit_test/dq_serial_sequential_id_keeps_its_numbers/Run()
	var/key = "dq_serial_test_key"
	TEST_ASSERT_EQUAL(sequential_id(key), 100, "sequential_id starts a key at 100")
	TEST_ASSERT_EQUAL(sequential_id(key), 101, "and counts on")
	serial_test_forget(/datum/serial/sequential_id)

#endif
