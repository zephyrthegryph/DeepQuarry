// Settings that were once verbs of the verb panel. Each is read where it matters, so it holds for whatever mob the player is playing.


/// Whether a plain click with combat mode off tries to pick up a micro (or pet, hug or help it).
/datum/preference/toggle/micro_pickup
	category = PREFERENCE_CATEGORY_GAME_PREFERENCES
	savefile_key = "MicroPickup"
	default_value = TRUE
	savefile_identifier = PREFERENCE_PLAYER

/datum/preference/toggle/micro_pickup/apply_to_client(client/client, value)
	(client?.mob)?.sync_game_settings()

/// Copies the player's game settings that the mob's own state carries onto the mob they play (at Login, and when a setting changes).
/mob/proc/sync_game_settings()
	return

/mob/living/sync_game_settings()
	if(!client?.prefs)
		return
	STATE_SET(src, living_misc, pickup_active, preference_or_default(/datum/preference/toggle/micro_pickup) ? TRUE : FALSE)
	STATE_SET(src, living_misc, mute_entry, FALSE)
	STATE_SET(src, vore_fx, liquidbelly_visuals, TRUE)

/mob/living/carbon/human/sync_game_settings()
	..()
	if(!client?.prefs)
		return
	STATE_SET(src, human_misc, nutrition_hidden, FALSE)
