#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

// sets_off() (code/library/transformations/transformation_effects.dm): the rows a rule compiles, and the mistakes it refuses.

/datum/unit_test/dq_xform_sets_off_rows
	boot_needs = list()

/datum/unit_test/dq_xform_sets_off_rows/Run()
	var/list/rows = xform_effect_rows(/transformation/chem/instant/foam, "test", sets_off(kind = XFORM_FX_FOAM, variant = 2, clears = TRUE, tell = "Foam!"))
	TEST_ASSERT_EQUAL(length(rows), 1, "one sets_off() is one row")
	var/datum/xform_effect/row = rows[1]
	TEST_ASSERT_EQUAL(row.kind, XFORM_FX_FOAM, "the kind")
	TEST_ASSERT_EQUAL(row.variant, 2, "the foam variant")
	TEST_ASSERT(row.clears, "clears is carried")
	TEST_ASSERT_EQUAL(row.tell, "Foam!", "the message is carried")
	rows = xform_effect_rows(/transformation/chem/instant/emp_pulse, "test", list(sets_off(kind = XFORM_FX_EMP, divisors = list(24, 20, 18, 14)), sets_off(kind = XFORM_FX_SMOKE)))
	TEST_ASSERT_EQUAL(length(rows), 2, "a list of two rows compiles to two, in order")
	var/list/reported = list()
	GLOB.declare_report_capture = reported
	TEST_ASSERT_NULL(xform_effect_rows(/transformation/chem/instant/emp_pulse, "test", sets_off(kind = XFORM_FX_EMP)), "a pulse needs its four divisors")
	TEST_ASSERT_NULL(xform_effect_rows(/transformation/chem/instant/foam, "test", sets_off(kind = "confetti")), "an unknown kind")
	TEST_ASSERT_NULL(xform_effect_rows(/transformation/chem/instant/foam, "test", list()), "no rows")
	GLOB.declare_report_capture = null
	TEST_ASSERT_EQUAL(length(reported), 3, "each refusal was reported ([jointext(reported, "; ")])")
	TEST_ASSERT_EQUAL(length(xform_effect_rows(/transformation/chem/instant/foam, "test", sets_off(kind = XFORM_FX_LIGHTNING, delay = 5 SECONDS, tell = TRUE))), 1, "a lightning row needs nothing else")
	TEST_ASSERT_EQUAL(length(xform_effect_rows(/transformation/chem/instant/foam, "test", sets_off(kind = XFORM_FX_RADIATION, range = 7, strength = 30))), 1, "a radiation row takes range and strength")
	TEST_ASSERT_EQUAL(length(xform_effect_rows(/transformation/chem/instant/foam, "test", sets_off(kind = XFORM_FX_EMP, ranges = list(2, 4, 7, 10)))), 1, "an EMP row takes fixed ranges")
	var/list/radiation_reports = list()
	GLOB.declare_report_capture = radiation_reports
	TEST_ASSERT_NULL(xform_effect_rows(/transformation/chem/instant/foam, "test", sets_off(kind = XFORM_FX_RADIATION, range = 7)), "a radiation row without a strength")
	GLOB.declare_report_capture = null
	TEST_ASSERT_EQUAL(length(radiation_reports), 1, "is refused with one report")
	TEST_ASSERT_EQUAL(length(xform_effect_rows(/transformation/chem/instant/foam, "test", sets_off(kind = XFORM_FX_GRAVITY, direction = GRAVITY_PUSH, range = 3))), 1, "a push needs a direction and a range")
	TEST_ASSERT_EQUAL(length(xform_effect_rows(/transformation/chem/instant/foam, "test", sets_off(kind = XFORM_FX_BURN, gases = list(GAS_VOLATILE_FUEL = 1), temperature = 500, range = 1))), 1, "a burn needs gases, a temperature and a range")
	TEST_ASSERT_EQUAL(length(xform_effect_rows(/transformation/chem/instant/foam, "test", sets_off(kind = XFORM_FX_MOOD, mood = MOOD_CALM))), 1, "a mood row")
	TEST_ASSERT_EQUAL(length(xform_effect_rows(/transformation/chem/instant/foam, "test", sets_off(kind = XFORM_FX_CONTAGION, edit = CONTAGION_EVOLVE, levels = list(0, 2)))), 1, "an evolve takes levels")
	var/list/new_kind_reports = list()
	GLOB.declare_report_capture = new_kind_reports
	TEST_ASSERT_NULL(xform_effect_rows(/transformation/chem/instant/foam, "test", sets_off(kind = XFORM_FX_GRAVITY, direction = "sideways", range = 3)), "an unknown gravity direction")
	TEST_ASSERT_NULL(xform_effect_rows(/transformation/chem/instant/foam, "test", sets_off(kind = XFORM_FX_BURN, gases = list(GAS_VOLATILE_FUEL = 1))), "a burn without a temperature and range")
	TEST_ASSERT_NULL(xform_effect_rows(/transformation/chem/instant/foam, "test", sets_off(kind = XFORM_FX_MOOD, mood = "sulky")), "an unknown mood")
	TEST_ASSERT_NULL(xform_effect_rows(/transformation/chem/instant/foam, "test", sets_off(kind = XFORM_FX_CONTAGION, edit = CONTAGION_EVOLVE)), "an evolve without levels")
	GLOB.declare_report_capture = null
	TEST_ASSERT_EQUAL(length(new_kind_reports), 4, "each was reported ([jointext(new_kind_reports, "; ")])")
	// The converted rules compiled their rows at world setup.
	var/datum/xform/X = xform_of(/transformation/chem/instant/chemsmoke)
	TEST_ASSERT_NOTNULL(X, "the chem smoke rule exists")
	TEST_ASSERT_EQUAL(length(X.effect_rows), 1, "the chem smoke rule sets off one smoke")

/// A nested list in a part's arguments survives construction, interning and the row compile.
/datum/unit_test/dq_part_nested_list_argument
	boot_needs = list()

/datum/unit_test/dq_part_nested_list_argument/Run()
	var/datum/entry/part/effect/sets_off/part = sets_off(kind = XFORM_FX_BLAST, chance = 7, blast = list(-1, list(-1, 1), list(1, 2), list(3, 5)))
	TEST_ASSERT_EQUAL(part.args["kind"], XFORM_FX_BLAST, "the kind is kept next to a nested list: [json_encode(part.args)]")
	TEST_ASSERT_EQUAL(part.args["chance"], 7, "so is the chance")
	var/list/blast = part.args["blast"]
	TEST_ASSERT_EQUAL(length(blast), 4, "the list has its four members")
	var/list/second = blast[2]
	TEST_ASSERT(islist(second) && second[2] == 1, "a member that is itself a list is intact")
	var/datum/entry/part/effect/sets_off/same = sets_off(kind = XFORM_FX_BLAST, chance = 7, blast = list(-1, list(-1, 1), list(1, 2), list(3, 5)))
	TEST_ASSERT(same == part, "the same arguments intern to the same part")
	var/datum/entry/part/effect/sets_off/other = sets_off(kind = XFORM_FX_BLAST, chance = 7, blast = list(-1, list(-1, 2), list(1, 2), list(3, 5)))
	TEST_ASSERT(other != part, "a different nested value is a different part")

/// The kind goes in by name, so a kind whose text equals another parameter name ("chance", "blast", "range") stays the kind: a positional text argument equal to a
/// named-argument key binds as that key in BYOND, in a direct call too.
/datum/unit_test/dq_sets_off_kind_by_name
	boot_needs = list()

/datum/unit_test/dq_sets_off_kind_by_name/Run()
	for(var/colliding in list("chance", "blast", "range", "amount", "delay", "tell"))
		var/datum/entry/part/effect/sets_off/part = sets_off(kind = colliding, chance = 5, amount = 2)
		TEST_ASSERT_EQUAL(part.args["kind"], colliding, "the kind \"[colliding]\" stays the kind: [json_encode(part.args)]")
		TEST_ASSERT_EQUAL(part.args["chance"], 5, "and the chance is still the chance for \"[colliding]\"")
	// A positional call that collides is refused at compile, naming the cause.
	var/list/reported = list()
	GLOB.declare_report_capture = reported
	var/datum/entry/part/effect/sets_off/bad = sets_off(XFORM_FX_BLAST, blast = list(-1, -1, 1, 2))
	TEST_ASSERT_NULL(xform_effect_rows(/transformation/chem/instant/foam, "test", bad), "a kind that bound as another argument is refused")
	GLOB.declare_report_capture = null
	TEST_ASSERT_EQUAL(length(reported), 1, "with one report")
	TEST_ASSERT(findtext(reported[1], "kind = "), "that names the by-name form: [jointext(reported, "; ")]")
	var/datum/entry/part/effect/sets_off/blast = sets_off(kind = XFORM_FX_BLAST, blast = list(-1, -1, 1, 2))
	TEST_ASSERT_EQUAL(blast.args["kind"], XFORM_FX_BLAST, "the real blast kind is the kind")

#endif
