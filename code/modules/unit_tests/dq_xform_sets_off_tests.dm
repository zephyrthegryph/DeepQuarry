#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

// sets_off() (code/library/transformations/transformation_effects.dm): the rows a rule compiles, and the mistakes it refuses.

/datum/unit_test/dq_xform_sets_off_rows
	boot_needs = list()

/datum/unit_test/dq_xform_sets_off_rows/Run()
	var/list/rows = xform_effect_rows(/transformation/chem/instant/foam, "test", sets_off(EFFECT_FOAM, variant = 2, clears = TRUE, tell = "Foam!"))
	TEST_ASSERT_EQUAL(length(rows), 1, "one sets_off() is one row")
	var/datum/xform_effect/row = rows[1]
	TEST_ASSERT_EQUAL(row.kind, EFFECT_FOAM, "the kind")
	TEST_ASSERT_EQUAL(row.variant, 2, "the foam variant")
	TEST_ASSERT(row.clears, "clears is carried")
	TEST_ASSERT_EQUAL(row.tell, "Foam!", "the message is carried")
	rows = xform_effect_rows(/transformation/chem/instant/emp_pulse, "test", list(sets_off(EFFECT_EMP, divisors = list(24, 20, 18, 14)), sets_off(EFFECT_SMOKE)))
	TEST_ASSERT_EQUAL(length(rows), 2, "a list of two rows compiles to two, in order")
	TEST_ASSERT_NULL(xform_effect_rows(/transformation/chem/instant/emp_pulse, "test", sets_off(EFFECT_EMP)), "a pulse needs its four divisors")
	TEST_ASSERT_NULL(xform_effect_rows(/transformation/chem/instant/foam, "test", sets_off("confetti")), "an unknown kind")
	TEST_ASSERT_NULL(xform_effect_rows(/transformation/chem/instant/foam, "test", list()), "no rows")
	// The converted rules compiled their rows at world setup.
	var/datum/xform/X = xform_of(/transformation/chem/instant/chemsmoke)
	TEST_ASSERT_NOTNULL(X, "the chem smoke rule exists")
	TEST_ASSERT_EQUAL(length(X.effect_rows), 1, "the chem smoke rule sets off one smoke")

#endif
