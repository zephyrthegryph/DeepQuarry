/datum/preference/toggle/show_typing_indicator
	category = PREFERENCE_CATEGORY_GAME_PREFERENCES
	savefile_key = "SHOW_TYPING"
	default_value = TRUE
	savefile_identifier = PREFERENCE_PLAYER

/datum/preference/toggle/show_typing_indicator/apply_to_client(client/client, value)
	if(!value)
		client.stop_thinking()

/datum/preference/toggle/show_ooc
	category = PREFERENCE_CATEGORY_GAME_PREFERENCES
	savefile_key = "CHAT_OOC"
	default_value = TRUE
	savefile_identifier = PREFERENCE_PLAYER

/datum/preference/toggle/show_looc
	category = PREFERENCE_CATEGORY_GAME_PREFERENCES
	savefile_key = "CHAT_LOOC"
	default_value = TRUE
	savefile_identifier = PREFERENCE_PLAYER

/datum/preference/toggle/show_dsay
	category = PREFERENCE_CATEGORY_GAME_PREFERENCES
	savefile_key = "CHAT_DEAD"
	default_value = TRUE
	savefile_identifier = PREFERENCE_PLAYER

/datum/preference/toggle/check_mention
	category = PREFERENCE_CATEGORY_GAME_PREFERENCES
	savefile_key = "CHAT_MENTION"
	default_value = TRUE
	savefile_identifier = PREFERENCE_PLAYER

/// Examining writes to chat instead of the Inspect panel.
/datum/preference/toggle/examine_in_chat
	category = PREFERENCE_CATEGORY_GAME_PREFERENCES
	savefile_key = "EXAMINE_IN_CHAT"
	default_value = FALSE
	savefile_identifier = PREFERENCE_PLAYER

/datum/preference/choiced/examine_mode
	category = PREFERENCE_CATEGORY_GAME_PREFERENCES
	savefile_key = "EXAMINE_MODE"
	savefile_identifier = PREFERENCE_PLAYER

TYPE_TABLE(/datum/preference/choiced/examine_mode, pref_choices, list(EXAMINE_MODE_SLIM,EXAMINE_MODE_VERBOSE,EXAMINE_MODE_SWITCH_TO_PANEL))

/datum/preference/choiced/examine_mode/create_default_value()
	return EXAMINE_MODE_VERBOSE

