/// A speaker whose radio step records what the say path decided, and whose autohiss marks the language it ran with.
/mob/living/carbon/human/inline_language_speaker
	var/list/heard_pieces
	var/heard_mode
	var/heard_whispering

/mob/living/carbon/human/inline_language_speaker/handle_message_mode(message_mode, list/message_pieces, verb, used_radios, whispering)
	heard_pieces = message_pieces
	heard_mode = message_mode
	heard_whispering = whispering
	return 1

/mob/living/carbon/human/inline_language_speaker/handle_autohiss(message, datum/language/L)
	if(hiss_marks)
		return "[L.name]/[message]"
	return message

/mob/living/carbon/human/inline_language_speaker/var/hiss_marks = FALSE

/proc/inline_language_setup(mob/living/carbon/human/H)
	H.add_language(LANGUAGE_GALCOM)
	H.add_language(LANGUAGE_SOL_COMMON)
	H.add_language(LANGUAGE_SIIK)
	H.add_language(LANGUAGE_HIVEMIND)
	H.remove_language(LANGUAGE_UNATHI)
	H.apply_default_language(GLOB.all_languages[LANGUAGE_GALCOM])
	H.set_language_keys(list(
		"s" = GLOB.all_languages[LANGUAGE_SOL_COMMON],
		"k" = GLOB.all_languages[LANGUAGE_SIIK],
		"5" = GLOB.all_languages[LANGUAGE_SIIK],
		"q" = GLOB.all_languages[LANGUAGE_UNATHI],
		"n" = GLOB.all_languages["Noise"],
		"h" = GLOB.all_languages[LANGUAGE_HIVEMIND],
	))

/proc/inline_language_label(datum/language/L)
	var/static/list/labels = list(LANGUAGE_GALCOM = "default", LANGUAGE_SOL_COMMON = "s", LANGUAGE_SIIK = "k", LANGUAGE_GIBBERISH = "gibberish", LANGUAGE_HIVEMIND = "h", "Noise" = "n")
	return labels[L?.name] || "?[L?.name]"

/proc/inline_language_pieces_text(list/pieces)
	. = list()
	for(var/datum/multilingual_say_piece/S in pieces)
		. += "[inline_language_label(S.speaking)]=[S.message]"
	return jointext(., "|")

/// The same table the tgui-say preview parser runs: the two cannot drift apart without one of them failing.
/datum/unit_test/inline_language_shared_cases

/datum/unit_test/inline_language_shared_cases/Run()
	var/mob/living/carbon/human/inline_language_speaker/H = allocate(/mob/living/carbon/human/inline_language_speaker, test_floor())
	inline_language_setup(H)
	var/list/table = json_decode(file2text("code/tests/unit_tests/data/language_parse_cases.json"))
	var/list/cases = table["cases"]
	TEST_ASSERT(length(cases) >= 20, "the shared table loaded")
	for(var/list/test_case as anything in cases)
		var/parsed = H.parse_languages(test_case["message"])
		if(test_case["whole"])
			TEST_ASSERT(istype(parsed, /datum/multilingual_say_piece), "[test_case["name"]]: the message goes whole to one language")
			var/datum/multilingual_say_piece/whole = parsed
			TEST_ASSERT_EQUAL(inline_language_label(whole.speaking), test_case["whole"], "[test_case["name"]]: language")
			TEST_ASSERT_EQUAL(whole.message, test_case["text"], "[test_case["name"]]: text")
			continue
		var/list/expected = list()
		for(var/list/piece as anything in test_case["pieces"])
			expected += "[piece[1]]=[piece[2]]"
		TEST_ASSERT_EQUAL(inline_language_pieces_text(parsed), jointext(expected, "|"), test_case["name"])

/// Each listener hears the pieces in their own marks, garbled only where they do not know the language.
/datum/unit_test/inline_language_listener_knows_one_of_two

/datum/unit_test/inline_language_listener_knows_one_of_two/Run()
	var/mob/living/carbon/human/inline_language_speaker/H = allocate(/mob/living/carbon/human/inline_language_speaker, test_floor())
	var/mob/living/carbon/human/listener = allocate(/mob/living/carbon/human, test_floor())
	inline_language_setup(H)
	listener.set_languages(list(GLOB.all_languages[LANGUAGE_SOL_COMMON]))
	var/list/pieces = H.parse_languages(",s Clearplain ,k Hiddenword")
	var/list/combined = listener.combine_message(pieces, "says", H)
	var/formatted = combined["formatted"]
	TEST_ASSERT(findtext(formatted, "Clearplain"), "the known piece is clear: [formatted]")
	TEST_ASSERT(!findtext(formatted, "Hiddenword"), "the unknown piece is garbled: [formatted]")
	TEST_ASSERT(!findtext(combined["raw"], "Hiddenword"), "runechat's text is garbled too: [combined["raw"]]")
	TEST_ASSERT(findtext(formatted, "\" \""), "each piece has its own speech marks: [formatted]")
	TEST_ASSERT(findtext(formatted, "says, \"") == 1, "the verb leads: [formatted]")

	listener.set_languages(list(GLOB.all_languages[LANGUAGE_SOL_COMMON], GLOB.all_languages[LANGUAGE_SIIK]))
	var/formatted_both = listener.combine_message(pieces, "says", H)["formatted"]
	TEST_ASSERT(findtext(formatted_both, "Hiddenword"), "a listener who knows both reads both: [formatted_both]")

	// One piece keeps the one pair of marks it always had.
	var/list/single = listener.combine_message(H.parse_languages(",s Solo"), "says", H)
	TEST_ASSERT(!findtext(single["formatted"], "\" \""), "a single language has one pair of marks: [single["formatted"]]")
	var/list/radio = listener.combine_message(pieces, "says", H, radio = TRUE)
	TEST_ASSERT(findtext(radio["formatted"], "\" \""), "radio renders each piece in its own marks: [radio["formatted"]]")
	TEST_ASSERT(!findtext(radio["formatted"], "Hiddenword") || (GLOB.all_languages[LANGUAGE_SIIK] in listener.languages), "radio garbles for the listener")

/// Autohiss runs once per piece, with that piece's language.
/datum/unit_test/inline_language_autohiss_per_piece

/datum/unit_test/inline_language_autohiss_per_piece/Run()
	var/mob/living/carbon/human/inline_language_speaker/H = allocate(/mob/living/carbon/human/inline_language_speaker, test_floor())
	inline_language_setup(H)
	H.hiss_marks = TRUE
	var/list/pieces = H.parse_languages(",s one ,k two")
	var/datum/multilingual_say_piece/first = pieces[1]
	var/datum/multilingual_say_piece/second = pieces[2]
	TEST_ASSERT(findtext(first.message, "one") && findtext(first.message, html_encode(LANGUAGE_SOL_COMMON)), "first piece hissed in its language: [first.message]")
	TEST_ASSERT(findtext(second.message, "two") && findtext(second.message, LANGUAGE_SIIK), "second piece hissed in its language: [second.message]")

	// The real species map: an exempt language in the same message is left alone.
	var/datum/species/unathi/lizard = allocate(/datum/species/unathi)
	TEST_ASSERT_EQUAL(lizard.handle_autohiss("sss", GLOB.all_languages[LANGUAGE_UNATHI], AUTOHISS_BASIC), "sss", "unathi does not hiss in its own language")
	TEST_ASSERT_NOTEQUAL(lizard.handle_autohiss("sss", GLOB.all_languages[LANGUAGE_GALCOM], AUTOHISS_BASIC), "sss", "unathi hisses in another language")

/// Radio and whisper run the real say path: the channel key is consumed first, then the pieces parse from what is left.
/datum/unit_test/inline_language_radio_and_whisper

/datum/unit_test/inline_language_radio_and_whisper/Run()
	var/mob/living/carbon/human/inline_language_speaker/H = allocate(/mob/living/carbon/human/inline_language_speaker, test_floor())
	inline_language_setup(H)

	H.direct_say(";,s Hello ,k friend")
	TEST_ASSERT_EQUAL(H.heard_mode, "headset", "; is the headset")
	TEST_ASSERT_EQUAL(inline_language_pieces_text(H.heard_pieces), "s=Hello|k=friend", "common radio splits")

	H.direct_say(":s Hello ,k friend")
	TEST_ASSERT_EQUAL(H.heard_mode, CHANNEL_SECURITY, ":s stays the security channel, not a language")
	TEST_ASSERT_EQUAL(inline_language_pieces_text(H.heard_pieces), "default=Hello|k=friend", "a department channel splits")

	H.direct_say(":w ,s Hello ,k friend")
	TEST_ASSERT(H.heard_whispering, ":w whispers")
	TEST_ASSERT_EQUAL(inline_language_pieces_text(H.heard_pieces), "s=Hello|k=friend", "a whisper splits")

	H.direct_say(",s Hello ,k friend", whispering = 1)
	TEST_ASSERT(H.heard_whispering, "the whisper verb's flag arrives")
	TEST_ASSERT_EQUAL(inline_language_pieces_text(H.heard_pieces), "s=Hello|k=friend", "a whisper splits")
	TEST_ASSERT_EQUAL(length(stars_all(H.heard_pieces)), 2, "the far whisper keeps its pieces")

	H.direct_say("It is 3,5 credits, friend")
	TEST_ASSERT_EQUAL(inline_language_pieces_text(H.heard_pieces), "default=It is 3,5 credits, friend", "ordinary commas pass through")

/// A rebound language's old key stops working; a mob with no keys keeps the languages' own.
/datum/unit_test/inline_language_rebound_key

/datum/unit_test/inline_language_rebound_key/Run()
	var/mob/living/carbon/human/inline_language_speaker/H = allocate(/mob/living/carbon/human/inline_language_speaker, test_floor())
	inline_language_setup(H)
	var/datum/language/siik = GLOB.all_languages[LANGUAGE_SIIK]
	TEST_ASSERT_EQUAL(H.language_for_key("k"), siik, "the bound key")
	if(siik.key != "k" && siik.key != "5")
		TEST_ASSERT_NULL(H.language_for_key(siik.key), "the language's own key was rebound away")
	H.set_language_keys(list())
	TEST_ASSERT_EQUAL(H.language_for_key(siik.key), siik, "with no keys, the language's own key answers")

/// The data tgui-say's preview parses with: the speaker's own keys and only what the server rules say.
/datum/unit_test/inline_language_preview_rules

/datum/unit_test/inline_language_preview_rules/Run()
	var/mob/living/carbon/human/inline_language_speaker/H = allocate(/mob/living/carbon/human/inline_language_speaker, test_floor())
	inline_language_setup(H)
	var/list/rules = json_decode(json_encode(H.say_language_rules()))
	TEST_ASSERT_EQUAL(rules["keys"]["s"], LANGUAGE_SOL_COMMON, "a bound key")
	TEST_ASSERT_EQUAL(rules["defaultLanguage"], LANGUAGE_GALCOM, "the preferred language")
	TEST_ASSERT(rules["languages"][LANGUAGE_HIVEMIND]["whole"], "a hivemind takes the whole message")
	TEST_ASSERT(!rules["languages"][LANGUAGE_UNATHI]["spoken"], "an unspoken language is marked")
	TEST_ASSERT(rules["languages"]["Noise"]["innate"], "noise is innate")
	TEST_ASSERT_EQUAL(rules["markers"]["+"], "b", "the game's own formatting markers")
	TEST_ASSERT(LANGUAGE_SOL_COMMON in rules["order"], "a spoken language is in the shortcut order")
	TEST_ASSERT(!(LANGUAGE_UNATHI in rules["order"]), "an unspoken one is not")
	TEST_ASSERT(":s" in rules["radioKeys"], "radio keys come along")
	TEST_ASSERT_NULL(rules["hiss"], "no client, no autohiss")
