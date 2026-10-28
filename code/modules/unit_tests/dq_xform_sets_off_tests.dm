#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

// sets_off() (code/library/transformations/transformation_effects.dm): the rows a rule compiles, and the mistakes it refuses.

/datum/unit_test/dq_xform_sets_off_rows
	boot_needs = list()

/datum/unit_test/dq_xform_sets_off_rows/Run()
	var/list/rows = xform_effect_rows(/transformation/chem/instant/foam, "test", sets_off(XFORM_FX_FOAM, variant = 2, clears = TRUE, tell = "Foam!"))
	TEST_ASSERT_EQUAL(length(rows), 1, "one sets_off() is one row")
	var/datum/xform_effect/row = rows[1]
	TEST_ASSERT_EQUAL(row.kind, XFORM_FX_FOAM, "the kind")
	TEST_ASSERT_EQUAL(row.variant, 2, "the foam variant")
	TEST_ASSERT(row.clears, "clears is carried")
	TEST_ASSERT_EQUAL(row.tell, "Foam!", "the message is carried")
	rows = xform_effect_rows(/transformation/chem/instant/emp_pulse, "test", list(sets_off(XFORM_FX_EMP, divisors = list(24, 20, 18, 14)), sets_off(XFORM_FX_SMOKE)))
	TEST_ASSERT_EQUAL(length(rows), 2, "a list of two rows compiles to two, in order")
	var/list/reported = list()
	GLOB.declare_report_capture = reported
	TEST_ASSERT_NULL(xform_effect_rows(/transformation/chem/instant/emp_pulse, "test", sets_off(XFORM_FX_EMP)), "a pulse needs its four divisors")
	TEST_ASSERT_NULL(xform_effect_rows(/transformation/chem/instant/foam, "test", sets_off("confetti")), "an unknown kind")
	TEST_ASSERT_NULL(xform_effect_rows(/transformation/chem/instant/foam, "test", list()), "no rows")
	GLOB.declare_report_capture = null
	TEST_ASSERT_EQUAL(length(reported), 3, "each refusal was reported ([jointext(reported, "; ")])")
	// The converted rules compiled their rows at world setup.
	var/datum/xform/X = xform_of(/transformation/chem/instant/chemsmoke)
	TEST_ASSERT_NOTNULL(X, "the chem smoke rule exists")
	TEST_ASSERT_EQUAL(length(X.effect_rows), 1, "the chem smoke rule sets off one smoke")

/// A nested list in a part's arguments survives construction, interning and the row compile.
/datum/unit_test/dq_part_nested_list_argument
	boot_needs = list()

/datum/unit_test/dq_part_nested_list_argument/Run()
	var/datum/entry/part/effect/sets_off/part = sets_off(XFORM_FX_BLAST, chance = 7, blast = list(-1, list(-1, 1), list(1, 2), list(3, 5)))
	TEST_ASSERT_EQUAL(part.args["kind"], XFORM_FX_BLAST, "the kind is kept next to a nested list: [json_encode(part.args)]")
	TEST_ASSERT_EQUAL(part.args["chance"], 7, "so is the chance")
	var/list/blast = part.args["blast"]
	TEST_ASSERT_EQUAL(length(blast), 4, "the list has its four members")
	var/list/second = blast[2]
	TEST_ASSERT(islist(second) && second[2] == 1, "a member that is itself a list is intact")
	var/datum/entry/part/effect/sets_off/same = sets_off(XFORM_FX_BLAST, chance = 7, blast = list(-1, list(-1, 1), list(1, 2), list(3, 5)))
	TEST_ASSERT(same == part, "the same arguments intern to the same part")
	var/datum/entry/part/effect/sets_off/other = sets_off(XFORM_FX_BLAST, chance = 7, blast = list(-1, list(-1, 2), list(1, 2), list(3, 5)))
	TEST_ASSERT(other != part, "a different nested value is a different part")

#endif
