// The settings audit (doc/rewrite/proposals/settings_audit.md): deleted settings load from old saves.

/// Every retired character key leaves an old slot on load.
/datum/unit_test/dq_retired_character_keys_migrate

/datum/unit_test/dq_retired_character_keys_migrate/Run()
	var/datum/preferences/dq_test_stub/P = dq_test_load_character(list("species" = SPECIES_HUMAN, "equip_preview_mob" = 1, "vantag_volunteer" = 1, "custom_say" = "declares", "religion" = "Mars"))
	var/list/save = P.get_save_data_for_savefile_identifier(PREFERENCE_CHARACTER)
	for(var/key in GLOB.retired_character_pref_keys)
		TEST_ASSERT(!(key in save), "[key] is dropped from the slot")
	TEST_ASSERT_EQUAL(P.read_preference(/datum/preference/choiced/species), SPECIES_HUMAN, "the live settings still load")
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
