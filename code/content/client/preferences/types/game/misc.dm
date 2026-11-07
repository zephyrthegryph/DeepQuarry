// Toggles

/// Whether or not to toggle ambient occlusion, the shadows around people
/datum/preference/toggle/ambient_occlusion
	category = PREFERENCE_CATEGORY_GAME_PREFERENCES
	savefile_key = "AMBIENT_OCCLUSION_PREF"
	default_value = FALSE
	savefile_identifier = PREFERENCE_PLAYER

/datum/preference/toggle/ambient_occlusion/apply_to_client(client/client, value)
	var/datum/plane_holder/PH = hud_of(client?.mob)?.plane_holder
	if(PH)
		PH.set_ao(VIS_OBJS, value)
		PH.set_ao(VIS_MOBS, value)

/datum/preference/toggle/browser_dev_tools
	category = PREFERENCE_CATEGORY_GAME_PREFERENCES
	savefile_key = "BrowserDevTools"
	default_value = FALSE
	savefile_identifier = PREFERENCE_PLAYER

/datum/preference/toggle/browser_dev_tools/apply_to_client(client/client, value)
	if(value)
		winset(client, null, "browser-options=[DEFAULT_CLIENT_BROWSER_OPTIONS],devtools")
	else
		winset(client, null, "browser-options=[DEFAULT_CLIENT_BROWSER_OPTIONS]")

// Text

/datum/preference/text/lastchangelog
	category = PREFERENCE_CATEGORY_GAME_PREFERENCES
	savefile_key = "lastchangelog"
	savefile_identifier = PREFERENCE_PLAYER

/datum/preference/text/lastchangelog/is_accessible(datum/preferences/preferences)
	..()
	return FALSE

/datum/preference/toggle/autotranscore
	category = PREFERENCE_CATEGORY_GAME_PREFERENCES
	savefile_key = "AUTOTRANSCORE"
	savefile_identifier = PREFERENCE_PLAYER
