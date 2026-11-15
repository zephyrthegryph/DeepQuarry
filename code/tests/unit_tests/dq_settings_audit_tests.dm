// The settings audit (doc/rewrite/proposals/settings_audit.md): deleted settings load from old saves.

/// Every retired character key leaves an old slot on load.
/datum/unit_test/dq_retired_character_keys_migrate

/datum/unit_test/dq_retired_character_keys_migrate/Run()
	var/datum/preferences/dq_test_stub/P = dq_test_load_character(list("species" = SPECIES_HUMAN, "equip_preview_mob" = 1, "vantag_volunteer" = 1, "custom_link" = "https://example.org", "ttone" = "beep", "custom_say" = "declares"))
	var/list/save = P.get_save_data_for_savefile_identifier(PREFERENCE_CHARACTER)
	for(var/key in GLOB.retired_character_pref_keys)
		TEST_ASSERT(!(key in save), "[key] is dropped from the slot")
	TEST_ASSERT_EQUAL(P.read_preference(/datum/preference/choiced/species), SPECIES_HUMAN, "the live settings still load")
	TEST_ASSERT_EQUAL(P.read_preference(/datum/preference/text/human/custom_say), "declares", "a restored setting keeps its saved value")
	qdel(P, TRUE)

/// A sound toggle that was off mutes the volume channel that replaced it.
/datum/unit_test/dq_retired_sound_toggle_mutes_channel

/datum/unit_test/dq_retired_sound_toggle_mutes_channel/Run()
	var/datum/preferences/dq_test_stub/P = new()
	var/list/save = list("SAY_SOUNDS" = 0, "SOUND_WEATHER" = 1, "SOUND_JUKEBOX" = 0, "volume_channels" = list(VOLUME_CHANNEL_WEATHER = 1))
	P.drop_retired_player_keys(save)
	var/list/volumes = save["volume_channels"]
	TEST_ASSERT_EQUAL(volumes[VOLUME_CHANNEL_VOICE], 0, "say sounds off mutes Voices and Emotes")
	TEST_ASSERT_EQUAL(volumes[VOLUME_CHANNEL_WEATHER], 1, "weather sounds on leaves Weather alone")
	TEST_ASSERT_EQUAL(save["media_volume"], 0, "jukebox off mutes the jukebox volume")
	TEST_ASSERT(!("SAY_SOUNDS" in save) && !("SOUND_JUKEBOX" in save), "the toggles leave the save")

/// Retired account keys leave the save, and nothing that is still a setting is on the list.
/datum/unit_test/dq_retired_player_keys_drop

/datum/unit_test/dq_retired_player_keys_drop/Run()
	var/datum/preferences/dq_test_stub/P = new()
	var/list/save = list("SHOW_PROGRESS" = 1, "vvdark" = 0, "CHAT_OOC" = 1)
	P.drop_retired_player_keys(save)
	TEST_ASSERT(!("SHOW_PROGRESS" in save) && !("vvdark" in save), "retired keys are dropped")
	TEST_ASSERT(save["CHAT_OOC"] == 1, "a live setting is kept")
	for(var/key in GLOB.preference_entries_by_key)
		TEST_ASSERT(!(key in GLOB.retired_player_pref_keys) && !(key in GLOB.retired_character_pref_keys), "[key] is a live setting and is not retired")

/// The character setup's "Show loadout" / "Show job outfit" switches are live settings: on by default, saved, and a change redraws the preview.
/datum/unit_test/dq_preview_toggles_are_live_settings

/datum/unit_test/dq_preview_toggles_are_live_settings/Run()
	var/datum/preferences/dq_test_stub/P = dq_test_load_character(list("species" = SPECIES_HUMAN, "preview_loadout" = 0))
	TEST_ASSERT(!P.read_preference(/datum/preference/toggle/human/preview_loadout), "a saved off loadout toggle loads")
	TEST_ASSERT(P.read_preference(/datum/preference/toggle/human/preview_job), "the job toggle defaults on")
	for(var/type in list(/datum/preference/toggle/human/preview_loadout, /datum/preference/toggle/human/preview_job))
		var/datum/preference/preference = GLOB.preference_entries[type]
		TEST_ASSERT(P.dq_preference_affects_preview(preference), "[type] redraws the preview")
	TEST_ASSERT(!("preview_loadout" in GLOB.retired_character_pref_keys) && !("preview_job" in GLOB.retired_character_pref_keys), "the toggles are not retired keys")
	qdel(P, TRUE)

/// The character setup's Looks options come back: the hair gradient, the ear, tail and wing opacities and the preview animation switch are settings again, tagged to the Looks tab, and no longer retired.
/datum/unit_test/dq_looks_options_present

/datum/unit_test/dq_looks_options_present/Run()
	var/list/types = list(
		/datum/preference/text/human/grad_style, /datum/preference/color/human/grad_color,
		/datum/preference/numeric/human/ears_alpha, /datum/preference/numeric/human/ears_alpha/secondary,
		/datum/preference/numeric/human/tail_alpha, /datum/preference/numeric/human/wing_alpha,
		/datum/preference/toggle/human/animations_toggle,
	)
	for(var/pref_type in types)
		var/datum/preference/pref = GLOB.preference_entries[pref_type]
		TEST_ASSERT_NOTNULL(pref, "[pref_type] exists")
		TEST_ASSERT(!(pref.savefile_key in GLOB.retired_character_pref_keys), "[pref.savefile_key] is not retired")
		var/list/entry = GLOB.pref_metadata_table[pref_type]
		TEST_ASSERT_EQUAL(entry?["category"], "appearance", "[pref_type] is on the Looks tab")
	TEST_ASSERT_EQUAL(GLOB.pref_metadata_table[/datum/preference/text/human/grad_style]["group"], "hair", "the gradient sits with the hair")

/// A taur body picks its tail style like any other part: None is the bare body, as the ears and wings have it, and the Legs picker leaves the body to the client.
/datum/unit_test/dq_tail_none_is_the_body

/datum/unit_test/dq_tail_none_is_the_body/Run()
	var/datum/preferences/dq_test_stub/P = new()
	var/datum/preference/pref = GLOB.preference_entries[/datum/preference/text/human/tail_style]
	var/list/thumbs = pref.get_pref_thumbnails(P)
	var/list/none = thumbs[""]
	TEST_ASSERT(islist(none) && length(none["layers"]) && none["base"], "None has the body's layers as its base")
	TEST_ASSERT(thumbs["plantigrade"] && thumbs["digitigrade"], "the Legs picker's bodies are still there")

/// A list of the character settings the second audit cut and put back (the background, records, speech verbs, speech bubble, footstep,
/// species sound, directory tags, nickname, pAI texts, Shadekin flicker and the second-look group), each with a saved value that differs from its default and is valid.
/proc/dq_restored_character_settings()
	return list(
		/datum/preference/text/human/home_system = "Sol",
		/datum/preference/text/human/birthplace = "Mars, Sol",
		/datum/preference/text/human/citizenship = "Sif",
		/datum/preference/text/human/religion = "Unitarianism",
		/datum/preference/choiced/human/economic_status = CLASS_UPPER,
		/datum/preference/text/human/med_record = "Allergic to penicillin.",
		/datum/preference/text/human/sec_record = "Two parking tickets.",
		/datum/preference/text/human/gen_record = "Station-born.",
		/datum/preference/text/human/custom_say = "declares",
		/datum/preference/text/human/custom_whisper = "murmurs",
		/datum/preference/text/human/custom_ask = "wonders",
		/datum/preference/text/human/custom_exclaim = "bellows",
		/datum/preference/text/human/custom_speech_bubble = "machine",
		/datum/preference/text/human/custom_footstep = "Claw",
		/datum/preference/text/human/species_sound = "Feline",
		/datum/preference/choiced/human/directory_gendertag = "Nonbinary",
		/datum/preference/choiced/human/directory_sexualitytag = "Bisexual",
		/datum/preference/name/nickname = "Nicky",
		/datum/preference/text/pai_ad = "Fast and friendly.",
		/datum/preference/text/pai_description = "A small cat-shaped card.",
		/datum/preference/text/pai_role = "Navigator",
		/datum/preference/text/pai_comments = "Please talk to me.",
		/datum/preference/numeric/living/flicker_break_chance = 5,
		/datum/preference/color/living/flicker_color = "#123456",
		/datum/preference/numeric/living/flicker_distance = 6,
		/datum/preference/numeric/living/flicker_time = 7,
		/datum/preference/text/human/autohiss = "Off",
		/datum/preference/text/human/blood_reagents = "milk",
		/datum/preference/text/human/vore_egg_type = "Skrell",
		/datum/preference/numeric/human/weight_gain = 77,
		/datum/preference/numeric/human/weight_loss = 33,
		/datum/preference/toggle/human/borg_petting = FALSE,
		/datum/preference/toggle/human/resleeve_lock = TRUE,
		/datum/preference/toggle/human/auto_backup_implant = TRUE,
		/datum/preference/numeric/human/sensorpref = 3,
		/datum/preference/toggle/human/ignore_shoes = TRUE,
		/datum/preference/toggle/human/fuzzy = TRUE,
		/datum/preference/toggle/human/offset_override = FALSE,
	)

/// Each restored setting exists, is not a retired key, and is tagged to a tab (the flicker settings to the Game tab's Shadekin section); the settings that stay cut are still retired.
/datum/unit_test/dq_restored_character_settings_present

/datum/unit_test/dq_restored_character_settings_present/Run()
	var/list/restored = dq_restored_character_settings()
	for(var/pref_type in restored)
		var/datum/preference/pref = GLOB.preference_entries[pref_type]
		TEST_ASSERT_NOTNULL(pref, "[pref_type] exists")
		TEST_ASSERT(!(pref.savefile_key in GLOB.retired_character_pref_keys), "[pref.savefile_key] is not retired")
		TEST_ASSERT_EQUAL(pref.savefile_identifier, PREFERENCE_CHARACTER, "[pref_type] is a character setting")
		var/list/entry = GLOB.pref_metadata_table[pref_type]
		TEST_ASSERT_NOTNULL(entry?["category"], "[pref_type] is tagged to a tab")
		TEST_ASSERT_NOTNULL(entry?["group"], "[pref_type] is tagged to a section")
	TEST_ASSERT_EQUAL(GLOB.pref_metadata_table[/datum/preference/numeric/living/flicker_time]["group"], "shadekin", "the flicker settings sit together")
	for(var/key in list("antag_faction", "antag_vis", "bday_announce", "communicator_visibility", "custom_link", "exploit_record", "name_is_always_random", "ttone", "uplinklocation"))
		TEST_ASSERT(key in GLOB.retired_character_pref_keys, "[key] stays cut")
	TEST_ASSERT("shadekin" in GLOB.dq_group_order["game"], "the Shadekin section is ordered on the Game tab")

/// Every restored setting keeps its value across a real save and load.
/datum/unit_test/dq_restored_character_settings_round_trip

/datum/unit_test/dq_restored_character_settings_round_trip/Run()
	var/list/restored = dq_restored_character_settings()
	var/list/overrides = list("species" = SPECIES_HUMAN)
	for(var/pref_type in restored)
		var/datum/preference/pref = GLOB.preference_entries[pref_type]
		overrides[pref.savefile_key] = restored[pref_type]
	var/path = dq_test_write_character_save(overrides)
	var/datum/preferences/dq_test_stub/P = allocate(/datum/preferences/dq_test_stub)
	P.load_and_save = TRUE
	P.path = path
	P.load_savefile()
	TEST_ASSERT(P.load_character(1), "the save loads")
	P.save_character()
	P.savefile.save()
	var/datum/preferences/dq_test_stub/Q = allocate(/datum/preferences/dq_test_stub)
	Q.load_and_save = TRUE
	Q.path = path
	Q.load_savefile()
	TEST_ASSERT(Q.load_character(1), "the saved slot loads again")
	var/list/wrong = list()
	for(var/pref_type in restored)
		var/expected = restored[pref_type]
		for(var/datum/preferences/slot in list(P, Q))
			var/got = slot.read_preference(pref_type)
			if(lowertext("[got]") != lowertext("[expected]"))
				wrong += "[pref_type]: [expected] != [got]"
	TEST_ASSERT(!length(wrong), "restored settings keep their saved values: [jointext(wrong, "; ")]")
	fdel(path)

/// The restored settings reach the body being played: records, background, nickname, sensor level, footstep, weight rates, speech verbs.
/datum/unit_test/dq_live_prefs/restored_settings_reach_the_mob
/datum/unit_test/dq_live_prefs/restored_settings_reach_the_mob/run_live()
	apply(/datum/preference/text/human/med_record, "Allergic to penicillin.")
	apply(/datum/preference/text/human/sec_record, "Two parking tickets.")
	apply(/datum/preference/text/human/gen_record, "Station-born.")
	TEST_ASSERT_EQUAL(subject.bio.med_record, "Allergic to penicillin.", "the medical record reaches the body")
	TEST_ASSERT_EQUAL(subject.bio.sec_record, "Two parking tickets.", "the security record reaches the body")
	TEST_ASSERT_EQUAL(subject.bio.gen_record, "Station-born.", "the general record reaches the body")
	apply(/datum/preference/text/human/home_system, "Sol")
	apply(/datum/preference/text/human/birthplace, "Mars, Sol")
	apply(/datum/preference/text/human/citizenship, "Sif")
	apply(/datum/preference/text/human/religion, "Unitarianism")
	TEST_ASSERT_EQUAL(subject.bio.home_system, "Sol", "the home system reaches the body")
	TEST_ASSERT_EQUAL(subject.bio.birthplace, "Mars, Sol", "the birthplace reaches the body")
	TEST_ASSERT_EQUAL(subject.bio.citizenship, "Sif", "the citizenship reaches the body")
	TEST_ASSERT_EQUAL(subject.bio.religion, "Unitarianism", "the religion reaches the body")
	apply(/datum/preference/name/nickname, "Nicky")
	TEST_ASSERT_EQUAL(subject.bio.nickname, "Nicky", "the nickname reaches the body")
	apply(/datum/preference/numeric/human/sensorpref, 3)
	TEST_ASSERT_EQUAL(subject.bio.sensorpref, 3, "the sensor level reaches the body")
	apply(/datum/preference/text/human/custom_footstep, "Claw")
	TEST_ASSERT_EQUAL(footstep_of(subject).custom_footstep, FOOTSTEP_MOB_CLAW, "the footstep sound reaches the body")
	apply(/datum/preference/numeric/human/weight_gain, 77)
	apply(/datum/preference/numeric/human/weight_loss, 33)
	TEST_ASSERT_EQUAL(STATE_GET(subject, bodyweight, weight_gain), 77, "the weight gain rate reaches the body")
	TEST_ASSERT_EQUAL(STATE_GET(subject, bodyweight, weight_loss), 33, "the weight loss rate reaches the body")
	apply(/datum/preference/text/human/custom_whisper, "Murmurs")
	apply(/datum/preference/text/human/custom_ask, "Wonders")
	apply(/datum/preference/text/human/custom_exclaim, "Bellows")
	TEST_ASSERT_EQUAL(subject.bio.custom_whisper, "murmurs", "the whisper verb is stored lower case")
	TEST_ASSERT_EQUAL(subject.bio.custom_ask, "wonders", "the ask verb is stored lower case")
	TEST_ASSERT_EQUAL(subject.bio.custom_exclaim, "bellows", "the exclaim verb is stored lower case")

/// The saved directory settings are what a mind starts the round with, and a change made in the directory this round leaves the saved one alone.
/datum/unit_test/dq_directory_tags_seed_the_mind

/datum/unit_test/dq_directory_tags_seed_the_mind/Run()
	var/datum/preferences/dq_test_stub/P = dq_test_load_character(list("species" = SPECIES_HUMAN, "directory_gendertag" = "Nonbinary", "directory_sexualitytag" = "Bisexual", "directory_tag" = GLOB.char_directory_tags[2], "directory_erptag" = "Unset"))
	var/datum/mind/M = allocate(/datum/mind)
	M.seed_directory_from(P)
	TEST_ASSERT_EQUAL(M.directory_gendertag, "Nonbinary", "the saved gender tag seeds the mind")
	TEST_ASSERT_EQUAL(M.directory_sexualitytag, "Bisexual", "the saved sexuality tag seeds the mind")
	TEST_ASSERT_EQUAL(M.directory_tag, GLOB.char_directory_tags[2], "the saved tag still seeds the mind")
	M.set_directory_gendertag("Male")
	TEST_ASSERT_EQUAL(M.directory_gendertag, "Male", "the tag is editable per round")
	TEST_ASSERT_EQUAL(P.read_preference(/datum/preference/choiced/human/directory_gendertag), "Nonbinary", "and the saved one is untouched")
	qdel(P, TRUE)

/// A saved flicker setting is what the Shadekin panel starts the round with.
/datum/unit_test/dq_flicker_prefs_seed_the_panel

/datum/unit_test/dq_flicker_prefs_seed_the_panel/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/datum/shadekin/SK = H.add_shadekin(/datum/shadekin/full)
	var/list/values = list(
		/datum/preference/numeric/living/flicker_time = 7,
		/datum/preference/numeric/living/flicker_break_chance = 5,
		/datum/preference/numeric/living/flicker_distance = 6,
		/datum/preference/color/living/flicker_color = "#123456",
	)
	for(var/pref_type in values)
		var/datum/preference/pref = GLOB.preference_entries[pref_type]
		pref.apply_pref_to(H, values[pref_type])
	TEST_ASSERT_EQUAL(SK.flicker_time, 7, "the flicker time seeds the panel")
	TEST_ASSERT_EQUAL(SK.flicker_break_chance, 5, "the break chance seeds the panel")
	TEST_ASSERT_EQUAL(SK.flicker_distance, 6, "the flicker distance seeds the panel")
	TEST_ASSERT_EQUAL(lowertext(SK.flicker_color), "#123456", "the flicker colour seeds the panel")

/// Hair, facial hair and the gradient draw their "none" style as the body, so no row of the Looks tab shows a bare label.
/datum/unit_test/dq_hair_none_styles_have_a_body_thumb

/datum/unit_test/dq_hair_none_styles_have_a_body_thumb/Run()
	var/datum/preferences/dq_test_stub/P = new()
	var/static/list/none_keys = list(
		/datum/preference/text/human/h_style = "Bald",
		/datum/preference/text/human/f_style = "Shaved",
		/datum/preference/text/human/grad_style = "none",
	)
	for(var/type in none_keys)
		var/datum/preference/pref = GLOB.preference_entries[type]
		var/list/thumbs = pref.get_pref_thumbnails(P)
		var/list/none = islist(thumbs) ? thumbs[none_keys[type]] : null
		TEST_ASSERT(islist(none) && length(none["layers"]), "[type]: [none_keys[type]] has the body's layers")
