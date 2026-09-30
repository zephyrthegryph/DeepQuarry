// Verb framework (plan 2.12): VERB_CAT_* defines and DEBUG_VERB.

/// A DEBUG_VERB used only by the tests below (debug builds only, like every test build).
DEBUG_VERB(dq_test_debug_verb, R_DEBUG, "DQ Test Debug Verb", "Unit test only.", VERB_CAT_DEBUG_MISC)
	return TRUE

/// A DEBUG_VERB registers as a rights-gated, debug_only admin verb in the debug category.
/datum/unit_test/dq_debug_verb_registers_gated
/datum/unit_test/dq_debug_verb_registers_gated/Run()
	var/datum/admin_verb/registered = SSadmin_verbs.admin_verbs_by_type[/datum/admin_verb/dq_test_debug_verb]
	TEST_ASSERT(registered, "a DEBUG_VERB should register with SSadmin_verbs in a DEBUG build")
	TEST_ASSERT(registered.debug_only, "a DEBUG_VERB should be flagged debug_only so dispatch logs it")
	TEST_ASSERT_EQUAL(registered.permissions, R_DEBUG, "a DEBUG_VERB should carry its rights")
	TEST_ASSERT_EQUAL(registered.category, VERB_CAT_DEBUG_MISC, "a DEBUG_VERB should carry its category define")

/// An ordinary ADMIN_VERB is not debug_only, and no registered debug verb is open to everyone.
/datum/unit_test/dq_debug_verb_only_debug_flagged
/datum/unit_test/dq_debug_verb_only_debug_flagged/Run()
	var/datum/admin_verb/plain = SSadmin_verbs.admin_verbs_by_type[/datum/admin_verb/admin_explosion]
	TEST_ASSERT(plain, "admin_explosion should be a registered admin verb")
	TEST_ASSERT(!plain.debug_only, "an ADMIN_VERB should not be flagged debug_only")
	for(var/verb_type in SSadmin_verbs.admin_verbs_by_type)
		var/datum/admin_verb/registered = SSadmin_verbs.admin_verbs_by_type[verb_type]
		if(registered.debug_only)
			TEST_ASSERT(registered.permissions != R_NONE, "debug verb [verb_type] must require rights")

/// The ADMIN_CATEGORY_* names are aliases of the same strings as their VERB_CAT_* defines.
/datum/unit_test/dq_verb_category_aliases
/datum/unit_test/dq_verb_category_aliases/Run()
	TEST_ASSERT_EQUAL(ADMIN_CATEGORY_MAIN, VERB_CAT_ADMIN, "ADMIN_CATEGORY_MAIN should alias VERB_CAT_ADMIN")
	TEST_ASSERT_EQUAL(ADMIN_CATEGORY_DEBUG, VERB_CAT_DEBUG, "ADMIN_CATEGORY_DEBUG should alias VERB_CAT_DEBUG")
	TEST_ASSERT_EQUAL(VERB_CAT_ABILITIES_VORE, "Abilities.Vore", "the dotted string is written once, in the define")
