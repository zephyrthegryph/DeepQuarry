// The character settings that used to be verbs (voice, speech verbs, speech bubble, custom link, catchable) are character
// preferences; an edit made during the round reaches the mob being played because the preference is `applies_live`.

/datum/unit_test/dq_live_prefs
	var/mob/living/carbon/human/subject

/datum/unit_test/dq_live_prefs/Run()
	subject = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	run_live()

/datum/unit_test/dq_live_prefs/proc/run_live()
	return

/datum/unit_test/dq_live_prefs/proc/apply(pref_type, value)
	var/datum/preference/pref = GLOB.preference_entries[pref_type]
	TEST_ASSERT_NOTNULL(pref, "[pref_type] is registered")
	pref.apply_pref_to(subject, value)

/datum/unit_test/dq_live_prefs/the_settings_apply_live
/datum/unit_test/dq_live_prefs/the_settings_apply_live/run_live()
	var/list/live = list(
		/datum/preference/text/human/custom_say, /datum/preference/text/human/custom_whisper,
		/datum/preference/text/human/custom_ask, /datum/preference/text/human/custom_exclaim,
		/datum/preference/text/human/custom_link, /datum/preference/numeric/human/voice_freq,
		/datum/preference/text/human/voice_sound, /datum/preference/text/human/custom_speech_bubble,
		/datum/preference/toggle/human/capture_crystal,
	)
	for(var/pref_type in live)
		var/datum/preference/pref = GLOB.preference_entries[pref_type]
		TEST_ASSERT(pref.applies_live, "[pref_type] reaches the mob being played")
		TEST_ASSERT(pref.savefile_identifier == PREFERENCE_CHARACTER, "[pref_type] is a character preference")

/datum/unit_test/dq_live_prefs/speech_settings_reach_the_mob
/datum/unit_test/dq_live_prefs/speech_settings_reach_the_mob/run_live()
	apply(/datum/preference/text/human/custom_say, "Declares")
	TEST_ASSERT_EQUAL(subject.bio.custom_say, "declares", "the say verb is stored lower case")
	apply(/datum/preference/text/human/custom_speech_bubble, "robot")
	TEST_ASSERT_EQUAL(subject.bio.custom_speech_bubble, "robot", "the speech bubble reaches the body")
	apply(/datum/preference/text/human/custom_link, "https://example.org/me")
	TEST_ASSERT_EQUAL(STATE_GET(subject, living_misc, custom_link), "https://example.org/me", "the link reaches the examine text")
	apply(/datum/preference/numeric/human/voice_freq, 50000)
	TEST_ASSERT_EQUAL(STATE_GET(subject, mob_misc, voice_freq), 50000, "the voice pitch reaches the voice")
	apply(/datum/preference/toggle/human/capture_crystal, FALSE)
	TEST_ASSERT(!STATE_GET(subject, capture, capture_crystal), "catchable switches off")

/datum/unit_test/dq_live_prefs/voice_sound_reaches_the_mob
/datum/unit_test/dq_live_prefs/voice_sound_reaches_the_mob/run_live()
	var/list/expected = SSsounds.ready().talk_sound("goon speak 1")
	TEST_ASSERT_NOTNULL(expected, "the provider has a nondefault speech set")
	apply(/datum/preference/text/human/voice_sound, "goon speak 1")
	TEST_ASSERT(STATE_GET(subject, mob_misc, voice_sounds_list) == expected, "the chosen speech set is installed")

/datum/unit_test/dq_live_prefs/game_settings_read_their_defaults
/datum/unit_test/dq_live_prefs/game_settings_read_their_defaults/run_live()
	// A mob nobody plays reads as a player who never changed a setting.
	TEST_ASSERT(subject.preference_or_default(/datum/preference/toggle/micro_pickup), "micro pick-up is on by default")
	var/list/actions = HARDSUIT_CLICK_ACTIONS
	TEST_ASSERT_EQUAL(actions[HARDSUIT_CLICK_ALT], INPUT_ACTION_ALTERNATE, "alt-click is the alternate action")
	for(var/pref_type in list(/datum/preference/toggle/micro_pickup))
		var/datum/preference/pref = GLOB.preference_entries[pref_type]
		TEST_ASSERT_EQUAL(pref.category, PREFERENCE_CATEGORY_GAME_PREFERENCES, "[pref_type] is in the Game Preferences window")
		TEST_ASSERT_EQUAL(pref.savefile_identifier, PREFERENCE_PLAYER, "[pref_type] belongs to the player")

/datum/unit_test/dq_live_prefs/settings_state_follows_the_game_setting_defaults
/datum/unit_test/dq_live_prefs/settings_state_follows_the_game_setting_defaults/run_live()
	// With no player behind it the mob keeps the state it was made with.
	subject.sync_game_settings()
	TEST_ASSERT_EQUAL(STATE_GET(subject, living_misc, pickup_active), TRUE, "a mob picks up micros by default")
	TEST_ASSERT_EQUAL(STATE_GET(subject, living_misc, mute_entry), FALSE, "and logs belly entrances")
	TEST_ASSERT_EQUAL(STATE_GET(subject, human_misc, nutrition_hidden), FALSE, "and shows its nutrition")

/// A new human's own verbs that show in the verb panel are the few commands the panel keeps: everything else is a setting, a HUD control, a keybinding or a menu entry.
/datum/unit_test/dq_live_prefs/baseline_human_panel_verbs
/datum/unit_test/dq_live_prefs/baseline_human_panel_verbs/run_live()
	// The second row is shown only until the verbs that apply to some bodies, a state or a place are granted when they apply (ux/verbs-conditional).
	var/static/list/allowed = list("Pray", "Ghost", "Return to Menu", "Tie Hair", "Switch Eyes/Monitor Layer", "Show/Hide tail", "Show/Hide wings", "Remove Env Message", "Create Env Message", "Cancel Camera View", "Observe", "Check Round Info")
	var/list/unexpected = list()
	for(var/verb_ref in subject.verbs)
		var/procpath/V = verb_ref
		if(V.hidden || !istext(V.category))
			continue
		if(!(V.name in allowed))
			unexpected += "[V.name] ([V.category])"
	TEST_ASSERT(!length(unexpected), "a new human sees only the panel's commands; also showing: [english_list(unexpected)]")
