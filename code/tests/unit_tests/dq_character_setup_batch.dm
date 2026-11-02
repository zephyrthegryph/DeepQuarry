// Character setup batch: the migrations and rules of the identity tab (language keys, preferred language).

/// Loads the fixture save with character1's keys overridden.
/proc/dq_test_load_character(list/overrides)
	var/path = dq_test_write_character_save(overrides)
	var/datum/preferences/dq_test_stub/P = new()
	P.load_and_save = TRUE
	P.path = path
	P.load_savefile()
	P.load_character(1)
	fdel(path)
	return P

/// An old {key: language} save keeps its keys, every other known language has its own default, and a key already held is refused.
/datum/unit_test/dq_language_keys_migrate_and_conflict

/datum/unit_test/dq_language_keys_migrate_and_conflict/Run()
	var/datum/preferences/dq_test_stub/P = dq_test_load_character(list("species" = SPECIES_HUMAN, "language" = list(LANGUAGE_UNATHI), "language_custom_keys" = list("q" = LANGUAGE_UNATHI), "language_prefixes" = list("+", "#", ",")))
	var/list/map = P.language_key_map()
	TEST_ASSERT_EQUAL(map[LANGUAGE_UNATHI], "q", "the saved custom key is kept")
	var/species_lang = P.species_language_name()
	var/datum/language/own = GLOB.all_languages[species_lang]
	TEST_ASSERT_EQUAL(map[species_lang], own.key, "a language without a saved key uses its own")
	TEST_ASSERT_NOTNULL(P.language_key_problem(species_lang, "q"), "a held key is a conflict")
	TEST_ASSERT_NOTNULL(P.language_key_problem(species_lang, "#"), "a symbol is refused")
	TEST_ASSERT_NOTNULL(P.language_key_problem(species_lang, "ab"), "two characters are refused")
	TEST_ASSERT_NOTNULL(P.language_key_problem(LANGUAGE_SIIK, "w"), "an unknown language is refused")
	TEST_ASSERT_NULL(P.set_language_key(LANGUAGE_UNATHI, "7"), "a free digit is taken")
	TEST_ASSERT_EQUAL(P.language_key_map()[LANGUAGE_UNATHI], "7", "the new key replaces the old")
	var/list/custom = P.read_preference(/datum/preference/language_custom_keys)
	TEST_ASSERT(!("q" in custom), "the old key is freed")

/// The old default ("common", not a language) and a language the character does not know resolve to the species language; the editor refuses unknowns.
/datum/unit_test/dq_preferred_language_rules

/datum/unit_test/dq_preferred_language_rules/Run()
	var/datum/preferences/dq_test_stub/P = dq_test_load_character(list("species" = SPECIES_HUMAN, "language" = list(LANGUAGE_UNATHI)))
	var/datum/preference/text/human/preferred_language/pref = GLOB.preference_entries[/datum/preference/text/human/preferred_language]
	TEST_ASSERT_EQUAL(pref.sanitize("common", P), P.species_language_name(), "the old default falls back to the species language")
	var/datum/preference_editor/language/editor = GLOB.preference_editors_by_key["language"]
	TEST_ASSERT_EQUAL(editor.handle_action(P, "set_preferred", list("language" = LANGUAGE_SIIK), null), PREF_UPDATE_REJECTED, "an unknown language cannot be preferred")
	TEST_ASSERT_EQUAL(editor.handle_action(P, "set_preferred", list("language" = LANGUAGE_UNATHI), null), PREF_UPDATE_ACCEPTED, "a known one can")
	TEST_ASSERT_EQUAL(editor.handle_action(P, "remove_language", list("language" = LANGUAGE_UNATHI), null), PREF_UPDATE_ACCEPTED, "the language can be removed")
	TEST_ASSERT_EQUAL(P.read_preference(/datum/preference/text/human/preferred_language), P.species_language_name(), "removing the preferred language falls back to the species language")

/// What a spawn runs on the mob: the keys reach mob.language_keys, the preferred language becomes the default, and parsing honours the key.
/datum/unit_test/dq_language_prefs_reach_the_mob

/datum/unit_test/dq_language_prefs_reach_the_mob/Run()
	var/datum/preferences/dq_test_stub/P = dq_test_load_character(list("species" = SPECIES_HUMAN, "language" = list(LANGUAGE_UNATHI), "language_custom_keys" = list("q" = LANGUAGE_UNATHI), "preflang" = LANGUAGE_UNATHI))
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	H.add_language(LANGUAGE_UNATHI)
	H.apply_language_prefs(P)
	var/datum/language/unathi = GLOB.all_languages[LANGUAGE_UNATHI]
	TEST_ASSERT_EQUAL(H.language_keys["q"], unathi, "the key is bound on the mob")
	TEST_ASSERT_EQUAL(H.get_default_language(), unathi, "the preferred language is the default")
	var/prefix = H.get_language_prefix()
	var/list/pieces = H.parse_languages("[prefix]q hello")
	var/datum/multilingual_say_piece/piece = pieces[1]
	TEST_ASSERT_EQUAL(piece.speaking, unathi, "typing the prefix and the key speaks the language")
