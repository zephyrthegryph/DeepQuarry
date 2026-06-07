// DQAdd — Smoke tests for the new preferences architecture. These don't run any UI;
// they exercise the registry / batch / constraint / sanitize / serialize paths.
//
// Included from /code/modules/unit_tests/_unit_tests.dm which already gates on UNIT_TESTS,
// so the file body does not need its own #if guard and the TEST_X macros are in scope.
//
// /datum/preferences/New() requires a real client and CRASHes without one. We use a
// /datum/preferences/dq_test_stub subtype that bypasses the New() argument check so we
// can exercise the in-memory state (batch depth, constraint cascade depth) directly.

/// Test stub: a /datum/preferences instance with no client, no savefile, no middleware.
/// Pure in-memory state for testing the new architecture's counter / batch behavior.
/datum/preferences/dq_test_stub

/datum/preferences/dq_test_stub/New()
	return // skip the real New() chain entirely

/datum/preferences/dq_test_stub/Destroy()
	value_cache = null
	return ..()


// ---------------------------------------------------------------------------
//   Tests
// ---------------------------------------------------------------------------

/datum/unit_test/dq_pref_registry_has_keys

/datum/unit_test/dq_pref_registry_has_keys/Run()
	for(var/pref_type in GLOB.preference_entries)
		var/datum/preference/pref = GLOB.preference_entries[pref_type]
		TEST_ASSERT_NOTNULL(pref.savefile_key, "[pref_type] has no savefile_key")
		TEST_ASSERT_NOTNULL(pref.savefile_identifier, "[pref_type] has no savefile_identifier")


/datum/unit_test/dq_pref_character_metadata_present

/datum/unit_test/dq_pref_character_metadata_present/Run()
	// Force the metadata table init in case the GLOBAL_LIST_INIT lazy-init hasn't run yet.
	if(!GLOB.pref_metadata_table)
		init_pref_metadata_table()
	var/list/orphans = list()
	for(var/pref_type in GLOB.preference_entries)
		var/datum/preference/pref = GLOB.preference_entries[pref_type]
		if(pref.savefile_identifier != PREFERENCE_CHARACTER)
			continue
		if(pref.get_widget(null) == PREF_WIDGET_HIDDEN)
			continue
		var/cat = pref.get_category(null)
		if(!cat || cat == "misc")
			orphans += "[pref_type]"
	if(orphans.len)
		TEST_FAIL("[orphans.len] visible PREFERENCE_CHARACTER prefs lack a category: [english_list(orphans)]")


/datum/unit_test/dq_pref_constraint_depth_guard

/datum/unit_test/dq_pref_constraint_depth_guard/Run()
	// Two constraints that infinite-cycle: A bumps depth + calls B; B bumps + calls A.
	// The guard inside their apply() bodies stops the recursion at PREF_CONSTRAINT_MAX_DEPTH.
	var/datum/preferences/dq_test_stub/p = new()
	TEST_ASSERT_NOTNULL(p, "couldn't allocate test stub prefs")
	p.constraint_cascade_depth = 0

	var/datum/preference_constraint/dq_test_cycle_a/a = new
	a.apply(p, "__cycle_a", null, 1)

	// After a balanced cascade the counter should be back to 0; the guard inside the
	// constraint bodies prevented the recursion from going past PREF_CONSTRAINT_MAX_DEPTH.
	TEST_ASSERT_EQUAL(p.constraint_cascade_depth, 0, "depth counter not unwound after cycle")
	qdel(p)

// Test-only constraint pair that intentionally cycles. Trigger keys start with "__" so
// they never collide with real prefs.
/datum/preference_constraint/dq_test_cycle_a
	triggers = list("__cycle_a")
	affects = list("__cycle_b")
/datum/preference_constraint/dq_test_cycle_a/apply(datum/preferences/preferences, changed_key, old_value, new_value)
	preferences.constraint_cascade_depth += 1
	if(preferences.constraint_cascade_depth < PREF_CONSTRAINT_MAX_DEPTH)
		var/datum/preference_constraint/dq_test_cycle_b/b = new
		b.apply(preferences, "__cycle_b", null, 1)
	preferences.constraint_cascade_depth -= 1

/datum/preference_constraint/dq_test_cycle_b
	triggers = list("__cycle_b")
	affects = list("__cycle_a")
/datum/preference_constraint/dq_test_cycle_b/apply(datum/preferences/preferences, changed_key, old_value, new_value)
	preferences.constraint_cascade_depth += 1
	if(preferences.constraint_cascade_depth < PREF_CONSTRAINT_MAX_DEPTH)
		var/datum/preference_constraint/dq_test_cycle_a/a = new
		a.apply(preferences, "__cycle_a", null, 1)
	preferences.constraint_cascade_depth -= 1


/datum/unit_test/dq_pref_batch_nests

/datum/unit_test/dq_pref_batch_nests/Run()
	var/datum/preferences/dq_test_stub/p = new()
	p.begin_update_batch()
	p.begin_update_batch()
	p.begin_update_batch()
	TEST_ASSERT_EQUAL(p.save_batch_depth, 3, "batch depth after 3 begins")
	p.end_update_batch()
	p.end_update_batch()
	p.end_update_batch()
	TEST_ASSERT_EQUAL(p.save_batch_depth, 0, "batch depth back to 0 after balanced ends")
	qdel(p)


/datum/unit_test/dq_pref_composite_roundtrip

/datum/unit_test/dq_pref_composite_roundtrip/Run()
	var/datum/preference/flavor_texts/pref = GLOB.preference_entries[/datum/preference/flavor_texts]
	TEST_ASSERT_NOTNULL(pref, "flavor_texts pref not registered")
	var/list/input = list(
		"general" = "Hello, world!",
		"head" = "A head.",
		"legs" = "Two legs.",
	)
	var/list/serialized = pref.pref_serialize(input)
	TEST_ASSERT_NOTNULL(serialized, "pref_serialize returned null")
	var/list/deserialized = pref.pref_deserialize(serialized, null)
	TEST_ASSERT_EQUAL(deserialized["general"], "Hello, world!", "general slot didn't survive round-trip")
	TEST_ASSERT_EQUAL(deserialized["head"], "A head.", "head slot didn't survive round-trip")
	TEST_ASSERT_EQUAL(deserialized["legs"], "Two legs.", "legs slot didn't survive round-trip")


/datum/unit_test/dq_pref_widget_auto_resolves

/datum/unit_test/dq_pref_widget_auto_resolves/Run()
	// PREF_WIDGET_AUTO should never leak through get_widget() once the resolver runs —
	// every pref ends up with one of the concrete widget constants.
	var/list/unresolved = list()
	for(var/pref_type in GLOB.preference_entries)
		var/datum/preference/pref = GLOB.preference_entries[pref_type]
		var/resolved = pref.get_widget(null)
		if(resolved == PREF_WIDGET_AUTO)
			unresolved += "[pref_type]"
	if(unresolved.len)
		TEST_FAIL("[unresolved.len] prefs returned PREF_WIDGET_AUTO from get_widget(): [english_list(unresolved)]")
