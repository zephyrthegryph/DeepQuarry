// The settings audit (doc/rewrite/proposals/settings_audit.md): deleted settings load from old saves.

/// An old slot's equip_preview_mob bitfield becomes the two preview toggles, and every retired character key leaves the slot.
/datum/unit_test/dq_retired_character_keys_migrate

/datum/unit_test/dq_retired_character_keys_migrate/Run()
	var/datum/preferences/dq_test_stub/P = dq_test_load_character(list("species" = SPECIES_HUMAN, "equip_preview_mob" = EQUIP_PREVIEW_LOADOUT, "preview_loadout" = null, "preview_job" = null, "vantag_volunteer" = 1))
	TEST_ASSERT(P.read_preference(/datum/preference/toggle/human/preview_loadout), "the loadout bit carries over")
	TEST_ASSERT(!P.read_preference(/datum/preference/toggle/human/preview_job), "a clear job bit carries over")
	var/list/save = P.get_save_data_for_savefile_identifier(PREFERENCE_CHARACTER)
	for(var/key in GLOB.retired_character_pref_keys)
		TEST_ASSERT(!(key in save), "[key] is dropped from the slot")

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
