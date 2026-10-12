#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/datum/unit_test/test_publish_fault_contract/Run()
	var/datum/seq_test_entity/E = allocate(/datum/seq_test_entity)
	TEST_ASSERT_NULL(test_publish_fault_refusal(src, E, "heat"), "Declared allocate-owned field passes real runtime preflight")
	TEST_ASSERT_NOTNULL(test_publish_fault_refusal(src, E, "unknown"), "Unknown fixture field is refused")
	var/datum/test_driver/borrowed = GLOB.test_driver
	TEST_ASSERT_NOTNULL(borrowed, "The borrowed engine driver must actually exist for ownership rejection coverage")
	TEST_ASSERT(!(borrowed in allocated), "The real engine driver is borrowed, not allocated by this fixture")
	TEST_ASSERT_NOTNULL(test_publish_fault_refusal(src, borrowed, "heat"), "Non-null shared unowned engine state is refused")
	var/datum/test_publish_fault/unmarked = allocate(/datum/test_publish_fault)
	TEST_ASSERT_NOTNULL(test_publish_fault_refusal(src, unmarked, "field"), "Owned but undeclared field is refused")
	TEST_ASSERT_EQUAL(E.heat, 0, "Pure rejection checks never mutate the actual fixture")

#endif
