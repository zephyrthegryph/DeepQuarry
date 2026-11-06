// Settings that were once verbs of the verb panel. Each is read where it matters, so it holds for whatever mob the player is playing.

/// Show the buttons that hotkeys also do (the human HUD's hotkey button group).
/datum/preference/toggle/hotkey_buttons
	category = PREFERENCE_CATEGORY_GAME_PREFERENCES
	savefile_key = "HotkeyButtons"
	default_value = TRUE
	savefile_identifier = PREFERENCE_PLAYER

/datum/preference/toggle/hotkey_buttons/apply_to_client_updated(client/client, value)
	var/mob/living/carbon/human/H = client?.mob
	if(istype(H))
		H.apply_hotkey_buttons(value)

/// Which click engages the selected hardsuit module.
/datum/preference/choiced/hardsuit_activation
	category = PREFERENCE_CATEGORY_GAME_PREFERENCES
	savefile_key = "HardsuitActivation"
	savefile_identifier = PREFERENCE_PLAYER

TYPE_TABLE(/datum/preference/choiced/hardsuit_activation, pref_choices, list(HARDSUIT_CLICK_MIDDLE, HARDSUIT_CLICK_ALT, HARDSUIT_CLICK_CONTROL))

/datum/preference/choiced/hardsuit_activation/create_default_value()
	return HARDSUIT_CLICK_MIDDLE

/// Whether other players see your nutrition level when they examine you.
/datum/preference/toggle/show_nutrition
	category = PREFERENCE_CATEGORY_GAME_PREFERENCES
	savefile_key = "ShowNutrition"
	default_value = TRUE
	savefile_identifier = PREFERENCE_PLAYER

/datum/preference/toggle/show_nutrition/apply_to_client(client/client, value)
	(client?.mob)?.sync_game_settings()

/// Whether a plain click with combat mode off tries to pick up a micro (or pet, hug or help it).
/datum/preference/toggle/micro_pickup
	category = PREFERENCE_CATEGORY_GAME_PREFERENCES
	savefile_key = "MicroPickup"
	default_value = TRUE
	savefile_identifier = PREFERENCE_PLAYER

/// Chat messages when something enters one of your bellies.
/datum/preference/toggle/belly_entrance_logs
	category = PREFERENCE_CATEGORY_GAME_PREFERENCES
	savefile_key = "BellyEntranceLogs"
	default_value = TRUE
	savefile_identifier = PREFERENCE_PLAYER

/// The fullscreen liquid effect while you are in a liquid belly.
/datum/preference/toggle/liquidbelly_visuals
	category = PREFERENCE_CATEGORY_GAME_PREFERENCES
	savefile_key = "LiquidbellyVisuals"
	default_value = TRUE
	savefile_identifier = PREFERENCE_PLAYER

/datum/preference/toggle/micro_pickup/apply_to_client(client/client, value)
	(client?.mob)?.sync_game_settings()

/datum/preference/toggle/belly_entrance_logs/apply_to_client(client/client, value)
	(client?.mob)?.sync_game_settings()

/datum/preference/toggle/liquidbelly_visuals/apply_to_client(client/client, value)
	(client?.mob)?.sync_game_settings()

/// Copies the player's game settings that the mob's own state carries onto the mob they play (at Login, and when a setting changes).
/mob/proc/sync_game_settings()
	return

/mob/living/sync_game_settings()
	if(!client?.prefs)
		return
	STATE_SET(src, living_misc, pickup_active, preference_or_default(/datum/preference/toggle/micro_pickup) ? TRUE : FALSE)
	STATE_SET(src, living_misc, mute_entry, preference_or_default(/datum/preference/toggle/belly_entrance_logs) ? FALSE : TRUE)
	STATE_SET(src, vore_fx, liquidbelly_visuals, preference_or_default(/datum/preference/toggle/liquidbelly_visuals) ? TRUE : FALSE)

/mob/living/carbon/human/sync_game_settings()
	..()
	if(!client?.prefs)
		return
	STATE_SET(src, human_misc, nutrition_hidden, preference_or_default(/datum/preference/toggle/show_nutrition) ? FALSE : TRUE)
