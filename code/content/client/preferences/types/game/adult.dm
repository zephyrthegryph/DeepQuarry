/datum/preference/toggle/tummy_sprites
	category = PREFERENCE_CATEGORY_GAME_PREFERENCES
	savefile_key = "VISIBLE_TUMMIES"
	savefile_identifier = PREFERENCE_PLAYER
	default_value = TRUE //it IS a vore server

/datum/preference/toggle/tummy_sprites/apply_to_client_updated(client/client, value)
	client?.mob?.recalculate_vis()
	. = ..()

