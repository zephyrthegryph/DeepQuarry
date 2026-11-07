// The lighting overhang test kit (code/content/lighting/overhang_test.dm): the verb is a Debug-tab admin verb, and the experiments undo themselves.

/datum/unit_test/dq_lighting_overhang_verb_registered

/datum/unit_test/dq_lighting_overhang_verb_registered/Run()
	var/datum/admin_verb/registered = SSadmin_verbs.admin_verbs_by_type[/datum/admin_verb/lighting_overhang_test]
	TEST_ASSERT_NOTNULL(registered, "the lighting overhang test is not a registered admin verb")
	TEST_ASSERT_EQUAL(registered.permissions, R_DEBUG, "the lighting overhang test must require exactly R_DEBUG")
	TEST_ASSERT_EQUAL(registered.name, "Lighting Overhang Test", "the verb changed its name")
	TEST_ASSERT(findtext(registered.category, ADMIN_CATEGORY_DEBUG) == 1, "the verb left the Debug category ([registered.category])")

/datum/unit_test/dq_lighting_overhang_modes_named

/datum/unit_test/dq_lighting_overhang_modes_named/Run()
	var/seen = list()
	for(var/mode in 0 to 3)
		var/name = lighting_overhang_mode_name(mode)
		TEST_ASSERT(!(name in seen), "mode [mode] shares its name with another mode")
		seen += name
