// Mob window links (hrefs) through the input inbox: a language panel's links work only for the mob whose panel it is, and name a language the mob knows.
// These read the same for an op.

/datum/unit_test/dq_topic_language_links

/datum/unit_test/dq_topic_language_links/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/speaker = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/other = allocate(/mob/living/carbon/human, T)
	var/datum/language/known = GLOB.all_languages[LANGUAGE_TRADEBAND]
	var/datum/language/unknown = GLOB.all_languages[LANGUAGE_SKRELLIAN]
	speaker.add_language(LANGUAGE_TRADEBAND)
	speaker.remove_language(LANGUAGE_SKRELLIAN)
	speaker.set_only_species_language(FALSE)
	speaker.set_species_language(LANGUAGE_GALCOM)
	speaker.add_language(LANGUAGE_GALCOM)
	TEST_ASSERT(known && unknown, "both languages exist")
	var/datum/languages_panel/panel = allocate(/datum/languages_panel, speaker)
	test_ui(speaker, panel, "set_default", list("language" = known.name))
	TEST_ASSERT_EQUAL(speaker.default_language, known, "a language link makes it the mob's default")
	test_ui(speaker, panel, "reset_default", list())
	TEST_ASSERT_EQUAL(speaker.default_language, GLOB.all_languages[LANGUAGE_GALCOM], "the reset link goes back to the species language")
	test_ui(speaker, panel, "set_default", list("language" = unknown.name))
	TEST_ASSERT(speaker.default_language != unknown, "a language the mob does not know is not found for the link")
	// someone else's panel link does nothing
	test_ui(other, panel, "set_default", list("language" = known.name))
	TEST_ASSERT(speaker.default_language != known, "another mob cannot set the default language")
