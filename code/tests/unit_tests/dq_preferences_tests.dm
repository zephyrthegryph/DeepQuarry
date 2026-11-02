// Smoke tests for the new preferences architecture. These don't run any UI;
// they exercise the registry / batch / constraint / sanitize / serialize paths.
//
// Included from /code/tests/unit_tests/_unit_tests.dm which already gates on UNIT_TESTS,
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


/// A scratch copy of the fixture save, with `character_overrides` written into character 1, loaded.
/proc/dq_palette_test_prefs(list/character_overrides)
	var/path = "data/dq_palette_saves/[world.realtime]_[rand(1, 99999)]/preferences.json"
	if(!fcopy("code/tests/unit_tests/data/profile_saves/headless_preferences.json", path))
		CRASH("the fixture save did not copy")
	if(length(character_overrides))
		var/datum/json_savefile/save = new(path)
		var/list/character = save.get_entry("character1")
		for(var/key in character_overrides)
			character[key] = character_overrides[key]
		save.save()
	var/datum/preferences/dq_test_stub/P = new
	P.load_and_save = TRUE
	P.path = path
	P.load_savefile()
	P.load_character(1)
	return P

/// A field saves a slot's name or its own hex, across a real save and load, and reads as hex either way.
/datum/unit_test/dq_pref_palette_link_roundtrip

/datum/unit_test/dq_pref_palette_link_roundtrip/Run()
	var/datum/preferences/dq_test_stub/P = dq_palette_test_prefs()
	TEST_ASSERT_EQUAL(lowertext(P.read_preference(/datum/preference/color/human/hair_color)), "#5c50e1", "an existing save's colour does not shift")
	TEST_ASSERT(P.update_preference_by_type(/datum/preference/color/human/color_slot/primary, "#112233"), "a slot takes a colour")
	TEST_ASSERT(P.update_preference_by_type(/datum/preference/color/human/hair_color, "primary"), "a field links to a slot")
	TEST_ASSERT(P.update_preference_by_type(/datum/preference/color/human/eyes_color, "#abcdef"), "another keeps its own")
	P.update_preference_by_type(/datum/preference/color/human/color_slot/secondary, "primary")
	TEST_ASSERT(!dq_color_slot_type(P.read_preference_raw(/datum/preference/color/human/color_slot/secondary)), "a slot cannot link to a slot")
	P.save_character()
	P.savefile.save()
	var/datum/json_savefile/again = new(P.path)
	TEST_ASSERT_EQUAL(again.get_entry("character1")?["hair_color"], "primary", "the save holds the slot's name")
	var/datum/preferences/dq_test_stub/Q = allocate(/datum/preferences/dq_test_stub)
	Q.path = P.path
	Q.load_savefile()
	TEST_ASSERT(Q.load_character(1), "the saved character loads again")
	TEST_ASSERT_EQUAL(Q.read_preference_raw(/datum/preference/color/human/hair_color), "primary", "the link is back")
	TEST_ASSERT_EQUAL(lowertext(Q.read_preference(/datum/preference/color/human/hair_color)), "#112233", "resolved to the slot")
	TEST_ASSERT_EQUAL(lowertext(Q.read_preference(/datum/preference/color/human/eyes_color)), "#abcdef", "the custom colour is the same")
	TEST_ASSERT(Q.update_preference_by_type(/datum/preference/color/human/hair_color, "#010203"), "a custom colour unlinks the field")
	TEST_ASSERT_EQUAL(lowertext(Q.read_preference(/datum/preference/color/human/color_slot/primary)), "#112233", "and leaves the slot")
	var/datum/preference/color/human/blood_color/unlinkable = GLOB.preference_entries[/datum/preference/color/human/blood_color]
	TEST_ASSERT(!unlinkable.is_valid("primary"), "a field that cannot link refuses a slot name")
	fdel(P.path)

/// A saved eight-colour palette becomes the slots; a save without one seeds them from the character.
/datum/unit_test/dq_pref_palette_migration

/datum/unit_test/dq_pref_palette_migration/Run()
	var/datum/preferences/dq_test_stub/P = dq_palette_test_prefs(list("color_palette" = list("#000001", "#000002", "#000003", "#000004", "#000005", "#000006", "#000007", "#000008")))
	TEST_ASSERT_EQUAL(P.read_preference(/datum/preference/color/human/color_slot/primary), "#000001", "first colour is Primary")
	TEST_ASSERT_EQUAL(P.read_preference(/datum/preference/color/human/color_slot/extra2), "#000005", "fifth is Extra 2")
	fdel(P.path)
	P = dq_palette_test_prefs(list("color_palette" = list("#000001", "bad")))
	TEST_ASSERT_EQUAL(P.read_preference(/datum/preference/color/human/color_slot/primary), "#000001", "a short palette fills what it has")
	TEST_ASSERT_EQUAL(lowertext(P.read_preference(/datum/preference/color/human/color_slot/secondary)), "#5c50e1", "and the rest seed from the character")
	fdel(P.path)
	P = dq_palette_test_prefs()
	TEST_ASSERT_EQUAL(lowertext(P.read_preference(/datum/preference/color/human/color_slot/primary)), "#4468af", "no palette: Primary is the skin colour")
	TEST_ASSERT_EQUAL(lowertext(P.read_preference(/datum/preference/color/human/skin_color)), "#4468af", "and the field is unchanged")
	fdel(P.path)

/// Linking an existing character changes no resolved colour, links what equals a slot, leaves the rest, and runs once.
/datum/unit_test/dq_pref_palette_links_existing

/datum/unit_test/dq_pref_palette_links_existing/Run()
	var/list/raw_save = json_decode(file2text("code/tests/unit_tests/data/profile_saves/headless_preferences.json"))
	var/list/saved = raw_save["character1"]
	var/datum/preferences/dq_test_stub/P = dq_palette_test_prefs()
	var/list/fields = dq_palette_fields()
	for(var/field in fields)
		var/datum/preference/pref = GLOB.preference_entries[field]
		TEST_ASSERT_EQUAL(lowertext(P.read_preference(field)), lowertext(saved[pref.savefile_key]), "[pref.savefile_key] resolves to its saved colour")
	TEST_ASSERT_EQUAL(P.read_preference_raw(/datum/preference/color/human/skin_color), "primary", "skin equals Primary, so it links")
	TEST_ASSERT_EQUAL(P.read_preference_raw(/datum/preference/color/human/hair_color), "secondary", "hair equals Secondary")
	TEST_ASSERT_EQUAL(P.read_preference_raw(/datum/preference/color/human/eyes_color), "tertiary", "eyes equal Tertiary")
	TEST_ASSERT_EQUAL(lowertext(P.read_preference(/datum/preference/color/human/color_slot/extra1)), lowertext(saved["facial_color"]), "the next field colour seeds Extra 1")
	TEST_ASSERT_EQUAL(P.read_preference_raw(/datum/preference/color/human/facial_color), "extra1", "and that field links to it")
	var/custom = lowertext(saved["wing_color3"])
	TEST_ASSERT_EQUAL(lowertext(P.read_preference_raw(/datum/preference/color/human/wing_color3)), custom, "a field matching no slot stays its own colour")
	// A user's later choice survives a reload: the migration does not run twice.
	P.update_preference_by_type(/datum/preference/color/human/hair_color, lowertext(saved["skin_color"]))
	P.save_character()
	P.savefile.save()
	var/datum/preferences/dq_test_stub/Q = allocate(/datum/preferences/dq_test_stub)
	Q.path = P.path
	Q.load_savefile()
	TEST_ASSERT(Q.load_character(1), "the saved character loads again")
	TEST_ASSERT_EQUAL(lowertext(Q.read_preference_raw(/datum/preference/color/human/hair_color)), lowertext(saved["skin_color"]), "a custom colour equal to a slot is not relinked")
	fdel(P.path)

/// A new character starts linked; the old tone converts only for the two species that drew from it.
/datum/unit_test/dq_pref_palette_new_and_tone

/datum/unit_test/dq_pref_palette_new_and_tone/Run()
	var/datum/preferences/dq_test_stub/P = dq_palette_test_prefs()
	TEST_ASSERT(P.load_character(2), "an empty slot loads as a new character")
	TEST_ASSERT_EQUAL(P.read_preference_raw(/datum/preference/color/human/skin_color), "primary", "skin is linked")
	TEST_ASSERT_EQUAL(P.read_preference_raw(/datum/preference/color/human/tail_color3), "tertiary", "so is a tail channel")
	fdel(P.path)
	P = dq_palette_test_prefs(list("species" = "Virtual Reality Human", "skin_tone" = -75))
	if(P.read_preference(/datum/preference/choiced/species) == "Virtual Reality Human")
		TEST_ASSERT_EQUAL(lowertext(P.read_preference(/datum/preference/color/human/skin_color)), lowertext(rgb(174, 152, 134)), "the tone converts to its fitted colour")
	fdel(P.path)
	TEST_ASSERT_EQUAL(dq_skin_tone_to_color(0), "#ffffff", "no tone is no tint")
	TEST_ASSERT_EQUAL(dq_skin_tone_to_color(30), "#ffffff", "a brightening tone clamps to white")
	TEST_ASSERT_EQUAL(dq_skin_tone_to_color(-185), lowertext(rgb(56, 2, 0)), "the darkest fit")
	TEST_ASSERT_EQUAL(dq_skin_tone_to_color(-75), lowertext(rgb(174, 152, 134)), "a table row is exact")
	P = dq_palette_test_prefs()
	TEST_ASSERT_EQUAL(lowertext(P.read_preference(/datum/preference/color/human/color_slot/primary)), "#4468af", "a Human's tone is ignored, as it always was")
	fdel(P.path)

/// A slot change reaches every linked field and marking in what the window is sent and in what is applied to the mob,
/// which gets plain hex. The preview is built by the same apply, and a slot write schedules it like any Looks pref.
/datum/unit_test/dq_pref_palette_slot_change_refreshes

/datum/unit_test/dq_pref_palette_slot_change_refreshes/Run()
	var/datum/preferences/dq_test_stub/P = dq_palette_test_prefs()
	var/datum/preference_editor/body_markings/editor = GLOB.preference_editors_by_key["body_markings"]
	var/marking
	var/zone = BP_TORSO
	for(var/name in GLOB.body_marking_styles_list)
		var/datum/sprite_accessory/marking/M = GLOB.body_marking_styles_list[name]
		if(LAZYLEN(M.body_parts) >= 2 && (zone in M.body_parts))
			marking = name
			break
	TEST_ASSERT_NOTNULL(marking, "a marking on the torso exists")
	P.update_preference_by_type(/datum/preference/body_markings, list())
	TEST_ASSERT_EQUAL(editor.handle_action(P, "add", list("marking" = marking), null), PREF_UPDATE_ACCEPTED, "the marking is added")
	var/list/raw = P.read_preference_raw(/datum/preference/body_markings)
	TEST_ASSERT_EQUAL(raw[marking][zone]["color"], "primary", "a new marking starts on Primary")
	P.update_preference_by_type(/datum/preference/color/human/hair_color, "primary")
	var/slot_pref = GLOB.preference_entries[/datum/preference/color/human/color_slot/primary]
	TEST_ASSERT(P.dq_preference_affects_preview(slot_pref), "a slot change rebuilds the preview")
	P.update_preference_by_type(/datum/preference/color/human/color_slot/primary, "#223344")

	var/list/ui = editor.build_ui_data(P)
	TEST_ASSERT_EQUAL(lowertext(ui["markings"][marking][zone]["color"]), "#223344", "the window's marking shows the slot's new colour")
	TEST_ASSERT_EQUAL(ui["links"][marking][zone], "primary", "and knows it is linked")
	raw = P.read_preference_raw(/datum/preference/body_markings)
	TEST_ASSERT_EQUAL(raw[marking][zone]["color"], "primary", "resolving does not write hex into the stored markings")
	TEST_ASSERT_EQUAL(editor.handle_action(P, "toggle_zone", list("marking" = marking, "zone" = zone), null), PREF_UPDATE_ACCEPTED, "an edit")
	raw = P.read_preference_raw(/datum/preference/body_markings)
	TEST_ASSERT_EQUAL(raw[marking][zone]["color"], "primary", "keeps the link")
	editor.handle_action(P, "toggle_zone", list("marking" = marking, "zone" = zone), null)

	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	P.copy_to(H)
	TEST_ASSERT_EQUAL(lowertext(H.looks.hair_color), "#223344", "the spawned hair is the resolved hex")
	var/obj/item/organ/external/torso = H.organs_by_name[zone]
	TEST_ASSERT_NOTNULL(torso, "the mob has the marking's organ")
	TEST_ASSERT_EQUAL(lowertext(torso.markings[marking]["color"]), "#223344", "the spawned marking is the resolved hex")

	P.update_preference_by_type(/datum/preference/color/human/color_slot/primary, "#556677")
	P.copy_to(H)
	torso = H.organs_by_name[zone]
	TEST_ASSERT_EQUAL(lowertext(H.looks.hair_color), "#556677", "a second slot change reaches the hair")
	TEST_ASSERT_EQUAL(lowertext(torso.markings[marking]["color"]), "#556677", "and the marking")

	TEST_ASSERT(P.persist_color(/datum/preference/color/human/hair_color, "#556677"), "persisting the same colour")
	TEST_ASSERT_EQUAL(P.read_preference_raw(/datum/preference/color/human/hair_color), "primary", "keeps the link")
	TEST_ASSERT(P.persist_markings(H.get_prioritised_markings()), "persisting the mob's markings")
	raw = P.read_preference_raw(/datum/preference/body_markings)
	TEST_ASSERT_EQUAL(raw[marking][zone]["color"], "primary", "keeps the marking's link")
	TEST_ASSERT(P.persist_color(/datum/preference/color/human/hair_color, "#700000"), "a colour changed in the round")
	TEST_ASSERT_EQUAL(lowertext(P.read_preference_raw(/datum/preference/color/human/hair_color)), "#700000", "becomes the field's own")
	fdel(P.path)

/// A part gaining a style links its channels; a part that had one keeps its colours.
/datum/unit_test/dq_pref_palette_new_part_links

/datum/unit_test/dq_pref_palette_new_part_links/Run()
	var/datum/preferences/dq_test_stub/P = dq_palette_test_prefs()
	var/datum/preference/text/human/tail_style/tail_pref = GLOB.preference_entries[/datum/preference/text/human/tail_style]
	var/list/offered = tail_pref.get_pref_choices(P)
	var/style = offered[1] // what the window offers is what it sends back
	var/other = offered[2]
	TEST_ASSERT(istext(style), "the choices are text, as a client sends them")
	P.update_preference_by_type(/datum/preference/text/human/tail_style, "")
	TEST_ASSERT(P.update_preference_by_type(/datum/preference/text/human/tail_style, style), "the part is added")
	TEST_ASSERT_EQUAL(P.read_preference_raw(/datum/preference/color/human/tail_color1), "primary", "channel 1")
	TEST_ASSERT_EQUAL(P.read_preference_raw(/datum/preference/color/human/tail_color2), "secondary", "channel 2")
	TEST_ASSERT_EQUAL(P.read_preference_raw(/datum/preference/color/human/tail_color3), "tertiary", "channel 3")
	P.update_preference_by_type(/datum/preference/color/human/tail_color1, "#0a0b0c")
	P.update_preference_by_type(/datum/preference/text/human/tail_style, other)
	TEST_ASSERT_EQUAL(lowertext(P.read_preference_raw(/datum/preference/color/human/tail_color1)), "#0a0b0c", "changing style keeps a custom colour")
	fdel(P.path)


/// A robotic limb starts on Tertiary with its own colour across a save and load, two limbs differ, a child follows its
/// parent, and a slot change reaches a linked limb.
/datum/unit_test/dq_pref_limb_colors

/datum/unit_test/dq_pref_limb_colors/Run()
	var/datum/preferences/dq_test_stub/P = dq_palette_test_prefs()
	var/datum/preference_editor/organs/editor = GLOB.preference_editors_by_key["organs"]
	TEST_ASSERT_EQUAL(editor.handle_action(P, "set_external_status", list("limb" = BP_L_ARM, "status" = "cyborg"), null), PREF_UPDATE_ACCEPTED, "the left arm goes robotic")
	TEST_ASSERT_EQUAL(editor.handle_action(P, "set_external_status", list("limb" = BP_R_ARM, "status" = "cyborg"), null), PREF_UPDATE_ACCEPTED, "the right arm goes robotic")
	var/list/stored = P.read_preference_raw(/datum/preference/limb_colors)
	TEST_ASSERT_EQUAL(stored[BP_L_ARM], "tertiary", "a new robotic limb links to Tertiary")
	TEST_ASSERT_EQUAL(editor.handle_action(P, "set_limb_color", list("limb" = BP_R_ARM, "color" = "#123456"), null), PREF_UPDATE_ACCEPTED, "a limb takes its own colour")
	TEST_ASSERT_EQUAL(editor.handle_action(P, "set_limb_color", list("limb" = BP_R_ARM, "color" = "red; drop"), null), PREF_UPDATE_REJECTED, "a malformed colour is refused")
	P.save_character()
	P.savefile.save()
	var/datum/preferences/dq_test_stub/Q = allocate(/datum/preferences/dq_test_stub)
	Q.path = P.path
	Q.load_savefile()
	TEST_ASSERT(Q.load_character(1), "the character loads again")
	stored = Q.read_preference_raw(/datum/preference/limb_colors)
	TEST_ASSERT_EQUAL(stored[BP_L_ARM], "tertiary", "the link is saved")
	TEST_ASSERT_EQUAL(stored[BP_R_ARM], "#123456", "and the hex")
	Q.update_preference_by_type(/datum/preference/color/human/color_slot/tertiary, "#223344")
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	Q.copy_to(H)
	var/obj/item/organ/external/left = H.organs_by_name[BP_L_ARM]
	var/obj/item/organ/external/right = H.organs_by_name[BP_R_ARM]
	var/obj/item/organ/external/hand = H.organs_by_name[BP_L_HAND]
	left.sync_colour_to_human(H)
	right.sync_colour_to_human(H)
	TEST_ASSERT_EQUAL(json_encode(left.s_col), json_encode(hex2rgb("#223344")), "the left arm renders the slot's colour")
	TEST_ASSERT_EQUAL(json_encode(right.s_col), json_encode(hex2rgb("#123456")), "the right arm renders its own")
	TEST_ASSERT(hand.is_robotic(), "the hand went robotic with its arm")
	TEST_ASSERT_EQUAL(lowertext(hand.synth_rgb), "#223344", "and takes its arm's colour")
	Q.update_preference_by_type(/datum/preference/color/human/color_slot/tertiary, "#556677")
	Q.copy_to(H)
	left = H.organs_by_name[BP_L_ARM]
	TEST_ASSERT_EQUAL(lowertext(left.synth_rgb), "#556677", "a slot change reaches the linked limb")
	var/list/ui = editor.build_ui_data(Q)
	TEST_ASSERT_EQUAL(ui["externals"][BP_L_ARM]["link"], "tertiary", "the window knows the link")
	TEST_ASSERT_EQUAL(lowertext(ui["externals"][BP_L_ARM]["color"]), "#556677", "and the colour")
	fdel(P.path)

/// Robotic limbs in an old save: the old colour when the toggle was on, otherwise Tertiary; once.
/datum/unit_test/dq_pref_limb_colors_migration

/datum/unit_test/dq_pref_limb_colors_migration/Run()
	var/datum/preferences/dq_test_stub/P = dq_palette_test_prefs(list("synth_color" = 1, "synth_color_rgb" = "#abcdef", "organ_data" = list(BP_L_ARM = "cyborg")))
	var/list/stored = P.read_preference_raw(/datum/preference/limb_colors)
	TEST_ASSERT_EQUAL(stored[BP_L_ARM], "#abcdef", "toggle on keeps its colour")
	TEST_ASSERT(!stored[BP_R_ARM], "a normal limb has no entry")
	P.update_preference_by_type(/datum/preference/limb_colors, list(BP_L_ARM = "#010203"))
	P.save_character()
	P.savefile.save()
	var/datum/preferences/dq_test_stub/Q = allocate(/datum/preferences/dq_test_stub)
	Q.path = P.path
	Q.load_savefile()
	Q.load_character(1)
	stored = Q.read_preference_raw(/datum/preference/limb_colors)
	TEST_ASSERT_EQUAL(stored[BP_L_ARM], "#010203", "the migration runs once")
	fdel(P.path)
	P = dq_palette_test_prefs(list("synth_color" = 0, "synth_color_rgb" = "#abcdef", "organ_data" = list(BP_L_ARM = "cyborg")))
	stored = P.read_preference_raw(/datum/preference/limb_colors)
	TEST_ASSERT_EQUAL(stored[BP_L_ARM], "tertiary", "toggle off takes Tertiary")
	fdel(P.path)


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
	TEST_ASSERT(fcopy("code/tests/unit_tests/data/profile_saves/headless_preferences.json", path), "the fixture save is copied to a scratch path")
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


/// The language picker offers what the character can actually take: nothing restricted, not the species' own language,
/// and the add action refuses the rest.
/datum/unit_test/dq_pref_language_picker_lists_only_pickable

/datum/unit_test/dq_pref_language_picker_lists_only_pickable/Run()
	var/datum/preference_editor/language/editor = GLOB.preference_editors_by_key["language"]
	TEST_ASSERT_NOTNULL(editor, "the language editor is registered")
	var/path = "data/dq_language_saves/[world.realtime]_[rand(1, 99999)]/preferences.json"
	TEST_ASSERT(fcopy("code/tests/unit_tests/data/profile_saves/headless_preferences.json", path), "the fixture save is copied to a scratch path")
	var/datum/preferences/dq_test_stub/P = allocate(/datum/preferences/dq_test_stub)
	P.path = path
	P.load_savefile()
	TEST_ASSERT(P.load_character(1), "the fixture character loads")
	var/datum/species/S = GLOB.all_species[P.read_preference(/datum/preference/choiced/species)]
	TEST_ASSERT_NOTNULL(S, "the fixture character has a species")
	var/list/pickable = editor.pickable_languages(P)
	var/restricted_key
	var/restricted_count = 0
	for(var/key in GLOB.all_languages)
		var/datum/language/L = GLOB.all_languages[key]
		if(L.flags & RESTRICTED)
			restricted_count++
			restricted_key ||= key
			TEST_ASSERT(!(key in pickable), "restricted [key] is not pickable")
	TEST_ASSERT(restricted_count > 0, "the catalogue has restricted languages to filter")
	TEST_ASSERT(!(S.language in pickable), "the species default [S.language] is not offered again")
	TEST_ASSERT(length(pickable) < length(GLOB.all_languages), "the picker lists fewer than the whole catalogue")
	log_test("language picker: [length(GLOB.all_languages)] languages in the catalogue, [restricted_count] restricted, [length(pickable)] pickable for [S.name]")
	TEST_ASSERT_EQUAL(editor.ui_act_add_language(null, list("language" = restricted_key), P, null, "add_language"), PREF_UPDATE_REJECTED, "adding a restricted language is refused")

/// The blood settings are on the Identity tab, under their own group, and still save under the keys existing characters have.
/datum/unit_test/dq_pref_blood_settings_live_in_identity

/datum/unit_test/dq_pref_blood_settings_live_in_identity/Run()
	var/list/expected = list(
		/datum/preference/text/human/b_type = "b_type",
		/datum/preference/text/human/blood_reagents = "blood_reagents",
		/datum/preference/color/human/blood_color = "blood_color",
	)
	for(var/pref_type in expected)
		var/datum/preference/pref = GLOB.preference_entries[pref_type]
		TEST_ASSERT_NOTNULL(pref, "[pref_type] is registered")
		TEST_ASSERT_EQUAL(pref.get_category(null), "identity", "[pref_type] is on the Identity tab")
		TEST_ASSERT_EQUAL(pref.get_group(null), "blood", "[pref_type] is in the blood group")
		TEST_ASSERT_EQUAL(pref.savefile_key, expected[pref_type], "[pref_type] keeps its savefile key, so saved values carry over")
	var/list/appearance_order = GLOB.dq_group_order["appearance"]
	TEST_ASSERT(!("blood" in appearance_order), "the Looks tab no longer lists a blood group")
	var/list/identity_order = GLOB.dq_group_order["identity"]
	TEST_ASSERT("blood" in identity_order, "the Identity tab orders the blood group")
