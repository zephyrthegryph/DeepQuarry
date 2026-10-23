/// converted unit test, maybe should be fully refactored

/// Test that language entries have distinct names
/datum/unit_test/language_test_shall_have_distinct_names

/datum/unit_test/language_test_shall_have_distinct_names/Run()
	if(length(GLOB.language_name_conflicts) != 0)
		var/list/name_conflict_log = list()
		for(var/conflicted_name in GLOB.language_name_conflicts)
			name_conflict_log += "+[length(GLOB.language_name_conflicts[conflicted_name])] languages with name \"[conflicted_name]\"!"
			for(var/datum/language/L in GLOB.language_name_conflicts[conflicted_name])
				name_conflict_log += "+-+[L.type]"
		TEST_FAIL("Some names are used by more than one language:\n" + name_conflict_log.Join("\n"))

/// Test that language entries have distinct keys
/datum/unit_test/language_test_shall_have_distinct_keys

/datum/unit_test/language_test_shall_have_distinct_keys/Run()
	if(length(GLOB.language_key_conflicts) != 0)
		var/list/key_conflict_log = list()
		for(var/conflicted_key in GLOB.language_key_conflicts)
			key_conflict_log += "+[length(GLOB.language_key_conflicts[conflicted_key])] languages with key \"[conflicted_key]\"!"
			for(var/datum/language/L in GLOB.language_key_conflicts[conflicted_key])
				key_conflict_log += "+-+[L]([L.type])"
		TEST_FAIL("Some keys are used by more than one language:\n" + key_conflict_log.Join("\n"))

/// The known-languages window's buttons are ops of its panel: the default language is set and reset, a custom key is asked for and set,
/// and only the mob itself may press them, and only for a language it knows.
/datum/unit_test/language_panel_ops

/datum/unit_test/language_panel_ops/Run()
	test_driver_begin()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/mob/living/carbon/human/other = allocate(/mob/living/carbon/human, test_floor())
	H.add_language(LANGUAGE_GALCOM)
	H.add_language(LANGUAGE_SOL_COMMON)
	var/datum/language/species_own = GLOB.all_languages[H.species_language || LANGUAGE_GIBBERISH]
	var/datum/language/chosen = GLOB.all_languages[LANGUAGE_SOL_COMMON]
	if(chosen == species_own)
		chosen = GLOB.all_languages[LANGUAGE_GALCOM]
	TEST_ASSERT(H.can_speak(chosen), "the human can speak the language it will make its default")
	TEST_ASSERT_NOTNULL(chosen, "the human knows a language it can speak and has not made its default")
	var/datum/languages_panel/panel = allocate(/datum/languages_panel, H)
	var/list/rows = hc_data(panel, H)["languages"]
	var/list/row_ids = list()
	for(var/list/row in rows)
		row_ids += row["id"]
	TEST_ASSERT(chosen.name in row_ids, "a language is named in the window by its name")
	// allowed: the mob sets and resets its default
	other.add_language(LANGUAGE_GALCOM)
	other.add_language(LANGUAGE_SOL_COMMON)
	other.apply_default_language(chosen)
	other.apply_default_language(species_own)
	var/datum/language/expected_reset = other.default_language
	var/datum/op_result/set_result = own(test_ui(H, panel, "set_default", list("language" = chosen.name)))
	TEST_ASSERT_EQUAL(set_result?.outcome, ACT_COMMITTED, "setting a default is allowed; reason=[set_result?.reason]")
	TEST_ASSERT_EQUAL(H.default_language, chosen, "the chosen language is the default")
	var/datum/op_result/reset_result = own(test_ui(H, panel, "reset_default"))
	TEST_ASSERT_EQUAL(reset_result?.outcome, ACT_COMMITTED, "resetting is allowed; reason=[reset_result?.reason]")
	TEST_ASSERT_EQUAL(H.default_language, expected_reset, "a reset applies the species' own default as the old link did")
	// refused: someone else's window, and a language the mob does not know
	var/datum/language/default_before = H.default_language
	var/datum/op_result/not_yours = own(test_ui(other, panel, "set_default", list("language" = chosen.name)))
	TEST_ASSERT_EQUAL(not_yours?.outcome, ACT_REFUSED, "another mob cannot set this mob's default")
	TEST_ASSERT_EQUAL(H.default_language, default_before, "and nothing changed")
	var/datum/op_result/unknown = own(test_ui(H, panel, "set_default", list("language" = "No Such Language")))
	TEST_ASSERT_EQUAL(unknown?.outcome, ACT_REFUSED, "a language the mob does not know is refused")
	// effect: a custom key is asked for and set
	test_ui(H, panel, "edit_key", list("language" = chosen.name))
	test_answer(H, "9")
	TEST_ASSERT_EQUAL(get_custom_prefix_by_lang(H, chosen), "9", "the answered key is the language's custom key")
	test_ui(H, panel, "edit_key", list("language" = chosen.name))
	test_answer(H, " ")
	TEST_ASSERT_NULL(get_custom_prefix_by_lang(H, chosen), "a blank answer removes the custom key")
	test_driver_end()
