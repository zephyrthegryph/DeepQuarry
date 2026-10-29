// Smoke tests for the new preferences architecture. These don't run any UI;
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


// ---------------------------------------------------------------------------
//   Tests
// ---------------------------------------------------------------------------

/datum/unit_test/dq_pref_registry_has_keys

/datum/unit_test/dq_pref_registry_has_keys/Run()
	TEST_ASSERT(length(GLOB.preference_entries) > 0, "preference registry is empty")
	for(var/pref_type in GLOB.preference_entries)
		var/datum/preference/pref = GLOB.preference_entries[pref_type]
		TEST_ASSERT_NOTNULL(pref.savefile_key, "[pref_type] has no savefile_key")
		TEST_ASSERT_NOTNULL(pref.savefile_identifier, "[pref_type] has no savefile_identifier")


/datum/unit_test/dq_pref_character_metadata_present

/datum/unit_test/dq_pref_character_metadata_present/Run()
	// Force the metadata table init in case the GLOBAL_LIST_INIT lazy-init hasn't run yet.
	if(!GLOB.pref_metadata_table)
		init_pref_metadata_table()
	TEST_ASSERT(length(GLOB.preference_entries) > 0, "preference registry is empty")
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
	qdel(p, TRUE)

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
	qdel(p, TRUE)


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
	TEST_ASSERT(length(GLOB.preference_entries) > 0, "preference registry is empty")
	var/list/unresolved = list()
	for(var/pref_type in GLOB.preference_entries)
		var/datum/preference/pref = GLOB.preference_entries[pref_type]
		var/resolved = pref.get_widget(null)
		if(resolved == PREF_WIDGET_AUTO)
			unresolved += "[pref_type]"
	if(unresolved.len)
		TEST_FAIL("[unresolved.len] prefs returned PREF_WIDGET_AUTO from get_widget(): [english_list(unresolved)]")


/// The character setup tabs open on the ones every new character needs (Identity, Looks, Loadout, Jobs), and the
/// rarely-changed ones the window folds under "More" come after every other tab, so the strip never interleaves them.
/datum/unit_test/dq_charsetup_category_order

/datum/unit_test/dq_charsetup_category_order/Run()
	var/list/index = dq_character_category_index("human")
	TEST_ASSERT(length(index) >= 4, "the human tab index has its tabs: [jointext(index, ", ")]")
	var/list/first = list("identity", "appearance", "loadout", "occupation")
	for(var/i in 1 to length(first))
		TEST_ASSERT_EQUAL(index[i], first[i], "tab [i] of [jointext(index, ", ")]")
	for(var/more in GLOB.dq_more_categories)
		TEST_ASSERT(more in GLOB.dq_category_order, "the More tab's [more] has a place in dq_category_order")
	var/seen_more = FALSE
	for(var/category in index)
		if(category in GLOB.dq_more_categories)
			seen_more = TRUE
		else
			TEST_ASSERT(!seen_more, "[category] comes after a More category: [jointext(index, ", ")]")
	// Robot and pAI modes keep the order of what they show.
	for(var/mode in list("robot", "pai"))
		var/list/mode_index = dq_character_category_index(mode)
		TEST_ASSERT_EQUAL(mode_index[1], "identity", "[mode] mode opens on Identity")


/// A character's colour palette is a real character preference: written, saved to the character's save and read
/// back the same, cleaned on the way in (bad entries and duplicates dropped, at most eight colours).
/datum/unit_test/dq_pref_color_palette_roundtrip

/datum/unit_test/dq_pref_color_palette_roundtrip/Run()
	var/datum/preference/color_palette/pref = GLOB.preference_entries[/datum/preference/color_palette]
	TEST_ASSERT_NOTNULL(pref, "color_palette is registered")
	TEST_ASSERT_EQUAL(pref.savefile_identifier, PREFERENCE_CHARACTER, "the palette is saved per character")
	TEST_ASSERT_EQUAL(pref.get_category(null), "appearance", "the palette lives on the Looks tab")
	TEST_ASSERT_EQUAL(pref.get_group(null), "palette", "in its own group")
	TEST_ASSERT_EQUAL(pref.get_widget(null), PREF_WIDGET_PALETTE, "with the palette widget")
	TEST_ASSERT(pref.is_client_writable(null), "the window may write it")

	var/list/cleaned = pref.pref_deserialize(list("#AA0000", "#aa0000", "not a colour", 5, "#00ff00", "#0000ff", "#111111", "#222222", "#333333", "#444444", "#555555", "#666666"), null)
	TEST_ASSERT_EQUAL(length(cleaned), 8, "at most eight colours survive: [json_encode(cleaned)]")
	TEST_ASSERT_EQUAL(cleaned[1], "#aa0000", "colours are lower-cased, the duplicate dropped")
	TEST_ASSERT_EQUAL(cleaned[2], "#00ff00", "and the bad entries dropped")
	TEST_ASSERT(!pref.is_valid(list("#zzzzzz")), "a bad colour is not a valid palette")

	var/path = "data/dq_palette_saves/[world.realtime]_[rand(1, 99999)]/preferences.json"
	TEST_ASSERT(fcopy("code/modules/unit_tests/data/profile_saves/headless_preferences.json", path), "the fixture save is copied to a scratch path")
	var/datum/preferences/dq_test_stub/P = allocate(/datum/preferences/dq_test_stub)
	P.load_and_save = TRUE
	P.path = path
	P.load_savefile()
	TEST_ASSERT(P.load_character(1), "the fixture character loads")
	TEST_ASSERT_EQUAL(length(P.read_preference(/datum/preference/color_palette)), 0, "a save without a palette has an empty one")
	var/list/palette = list("#123456", "#abcdef", "#ff8800")
	TEST_ASSERT(P.update_preference(pref, palette), "the palette is written like any window write")
	P.save_character()
	P.savefile.save()
	var/datum/json_savefile/again = new(path)
	var/list/saved = again.get_entry("character1")?["color_palette"]
	TEST_ASSERT_EQUAL(json_encode(saved), json_encode(palette), "the save holds the palette")
	var/datum/preferences/dq_test_stub/Q = allocate(/datum/preferences/dq_test_stub)
	Q.path = path
	Q.load_savefile()
	TEST_ASSERT(Q.load_character(1), "the saved character loads again")
	TEST_ASSERT_EQUAL(json_encode(Q.read_preference(/datum/preference/color_palette)), json_encode(palette), "and reads back the same palette")
	fdel(path)


/// Ears, tail and wings are optional: the window's Remove writes an empty style, which is valid; any other value
/// must still be a style on offer.
/datum/unit_test/dq_pref_optional_parts_removable

/datum/unit_test/dq_pref_optional_parts_removable/Run()
	var/datum/preferences/dq_test_stub/P = allocate(/datum/preferences/dq_test_stub)
	for(var/pref_type in list(/datum/preference/text/human/ear_style, /datum/preference/text/human/ear_secondary_style, /datum/preference/text/human/tail_style, /datum/preference/text/human/wing_style))
		var/datum/preference/pref = GLOB.preference_entries[pref_type]
		TEST_ASSERT(pref.validate(P, ""), "[pref_type]: an empty style (no part) is valid")
		TEST_ASSERT(pref.validate(P, null), "[pref_type]: so is null, the default")
		TEST_ASSERT(!pref.validate(P, "/datum/sprite_accessory/not_a_style"), "[pref_type]: an unknown style is still refused")


/// A marking's colour can be set straight from the palette (no picker): the whole marking or one body part,
/// and a malformed colour is refused. The editor also tells the window which markings the species cannot wear.
/datum/unit_test/dq_pref_marking_palette_colour

/datum/unit_test/dq_pref_marking_palette_colour/Run()
	var/path = "data/dq_palette_saves/[world.realtime]_[rand(1, 99999)]/preferences.json"
	TEST_ASSERT(fcopy("code/modules/unit_tests/data/profile_saves/headless_preferences.json", path), "the fixture save is copied to a scratch path")
	var/datum/preferences/dq_test_stub/P = allocate(/datum/preferences/dq_test_stub)
	P.path = path
	P.load_savefile()
	TEST_ASSERT(P.load_character(1), "the fixture character loads")
	P.update_preference_by_type(/datum/preference/body_markings, list())
	var/datum/preference_editor/body_markings/editor = GLOB.preference_editors_by_key["body_markings"]
	var/marking
	var/zone
	for(var/name in GLOB.body_marking_styles_list)
		var/datum/sprite_accessory/marking/M = GLOB.body_marking_styles_list[name]
		if(LAZYLEN(M.body_parts) >= 2)
			marking = name
			zone = M.body_parts[2]
			break
	TEST_ASSERT_NOTNULL(marking, "a marking with two body parts exists")
	TEST_ASSERT_EQUAL(editor.handle_action(P, "add", list("marking" = marking), null), PREF_UPDATE_ACCEPTED, "the marking is added")
	var/datum/sprite_accessory/marking/added = GLOB.body_marking_styles_list[marking]
	for(var/part in added.body_parts)
		TEST_ASSERT(isnull(added.body_parts[part]), "adding a marking leaves the shared accessory's body part list flat ([part] -> [json_encode(added.body_parts[part])])")
	TEST_ASSERT_EQUAL(editor.handle_action(P, "set_color_value", list("marking" = marking, "color" = "#12AB34"), null), PREF_UPDATE_ACCEPTED, "a palette colour applies to the whole marking")
	var/list/markings = P.read_preference(/datum/preference/body_markings)
	for(var/part in markings[marking])
		if(islist(markings[marking][part]))
			TEST_ASSERT_EQUAL(lowertext(markings[marking][part]["color"]), "#12ab34", "[part] took the colour")
	TEST_ASSERT_EQUAL(editor.handle_action(P, "set_color_value", list("marking" = marking, "zone" = zone, "color" = "#000080"), null), PREF_UPDATE_ACCEPTED, "a palette colour applies to one part")
	markings = P.read_preference(/datum/preference/body_markings)
	TEST_ASSERT_EQUAL(lowertext(markings[marking][zone]["color"]), "#000080", "[zone] took its own colour")
	TEST_ASSERT_EQUAL(editor.handle_action(P, "set_color_value", list("marking" = marking, "color" = "red; drop"), null), PREF_UPDATE_REJECTED, "a malformed colour is refused")
	var/list/ui = editor.build_ui_data(P)
	TEST_ASSERT(islist(ui["incompatible"]), "the window learns which markings the species cannot wear")
	for(var/name in ui["incompatible"])
		TEST_ASSERT(name in GLOB.body_marking_styles_list, "[name] is a real marking")
	fdel(path)
