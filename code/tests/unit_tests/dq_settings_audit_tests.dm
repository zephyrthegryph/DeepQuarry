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
