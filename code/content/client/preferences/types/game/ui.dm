/// Screentips: what Click and Alt-click would do to the hovered thing (code/datums/interactions/presentation.dm).
/datum/preference/toggle/screentips
	category = PREFERENCE_CATEGORY_GAME_PREFERENCES
	savefile_key = "screentips_optin" // renamed when the default went off, so a value saved under the old default does not keep it on
	default_value = FALSE // opt-in: the hover line at the top of the map is off unless the player turns it on
	savefile_identifier = PREFERENCE_PLAYER

/datum/preference/toggle/screentips/apply_to_client(client/client, value)
	client.set_hover_tracking(value || keybinding_profile_uses_hover(client.mob?.keybind_profile() || KEYBIND_PROFILE_DEFAULT, client.keybinding_overrides()))
	if(!value)
		client.clear_screentip()

/datum/preference/choiced/tgui_layout
	savefile_key = "tgui_layout"
	savefile_identifier = PREFERENCE_PLAYER

TYPE_TABLE(/datum/preference/choiced/tgui_layout, pref_choices, list(TGUI_LAYOUT_GRID, TGUI_LAYOUT_LIST))

/datum/preference/choiced/tgui_layout/create_default_value()
	return TGUI_LAYOUT_GRID

/datum/preference/choiced/tgui_layout/apply_to_client(client/client, value)
	for (var/datum/tgui/tgui as anything in client.mob?.tgui_open_uis)
		// Force it to reload either way
		tgui.update_tgui_static_data(client.mob)

/datum/preference/toggle/tgui_use_spellcheck
	category = PREFERENCE_CATEGORY_GAME_PREFERENCES
	savefile_key = "TGUI_ENABLE_SPELLCHECK"
	default_value = TRUE
	savefile_identifier = PREFERENCE_PLAYER


/datum/preference/text/preset_colors
	category = PREFERENCE_CATEGORY_MANUALLY_RENDERED
	savefile_identifier = PREFERENCE_PLAYER
	savefile_key = "preset_colors"
	maximum_value_length = 160

/datum/preference/text/preset_colors/apply_to_client(client/client, value)
	return

/datum/preference/toggle/ui_scale
	category = PREFERENCE_CATEGORY_GAME_PREFERENCES
	savefile_key = "ui_scale"
	savefile_identifier = PREFERENCE_PLAYER
	default_value = FALSE // Set to true once lobby screen is migrated to tgui and browse are replaced with datum browser

/datum/preference/toggle/ui_scale/apply_to_client(client/client, value)
	if(!istype(client))
		return

	client.refresh_tgui()

/// Enables flashing the window in your task tray for important events
/datum/preference/toggle/window_flashing
	category = PREFERENCE_CATEGORY_GAME_PREFERENCES
	savefile_key = "windowflashing"
	savefile_identifier = PREFERENCE_PLAYER
