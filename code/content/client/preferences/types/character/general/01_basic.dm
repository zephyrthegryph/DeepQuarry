// Toggles

// Numerics
/datum/preference/numeric/human/age
	category = PREFERENCE_CATEGORY_MANUALLY_RENDERED
	savefile_key = "age"
	savefile_identifier = PREFERENCE_CHARACTER

	step = 1
	minimum = 18
	maximum = 100 // was 250; capped so the Mind/Body pool curve reaches its plateau at a realistic upper bound.

/datum/preference/numeric/human/age/apply_to_human(mob/living/carbon/human/target, value)
	target.bio.age = value
	return

/datum/preference/numeric/human/age/create_default_value()
	return 18

/datum/preference/numeric/human/age/create_random_value(datum/preferences/preferences, datum/species/current_species)
	return rand(current_species.min_age, current_species.max_age)

/// The days a birthday month has (February counts the 29th). 0 for anything that is not a month.
/proc/birth_month_days(month)
	switch(month)
		if(1, 3, 5, 7, 8, 10, 12)
			return 31
		if(4, 6, 9, 11)
			return 30
		if(2)
			return 29
	return 0

/datum/preference/numeric/human/bday_month
	category = PREFERENCE_CATEGORY_MANUALLY_RENDERED
	savefile_key = "bday_month"
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE

	step = 1
	minimum = 1
	maximum = 12

/datum/preference/numeric/human/bday_month/apply_to_human(mob/living/carbon/human/target, value)
	return

/datum/preference/numeric/human/bday_month/create_default_value()
	return rand(1, 12)

/// An old save's "no month" (0) or anything else that is not a month becomes a random one.
/datum/preference/numeric/human/bday_month/pref_deserialize(input, datum/preferences/preferences)
	if(!birth_month_days(input))
		return create_default_value()
	return input

/datum/preference/numeric/human/bday_day
	category = PREFERENCE_CATEGORY_MANUALLY_RENDERED
	savefile_key = "bday_day"
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE

	step = 1
	minimum = 1
	maximum = 31

/datum/preference/numeric/human/bday_day/apply_to_human(mob/living/carbon/human/target, value)
	return

/datum/preference/numeric/human/bday_day/create_default_value()
	return rand(1, 28)

/datum/preference/numeric/human/bday_day/create_informed_default_value(datum/preferences/preferences)
	return rand(1, birth_month_days(preferences.read_preference(/datum/preference/numeric/human/bday_month)))

/// An old save's "no day" (0), or a day the saved month does not have, becomes a random day of that month.
/datum/preference/numeric/human/bday_day/pref_deserialize(input, datum/preferences/preferences)
	var/days = preferences ? birth_month_days(preferences.read_preference(/datum/preference/numeric/human/bday_month)) : 28
	if(!isnum(input) || input < 1 || input > days || input != round(input))
		return rand(1, days)
	return input

/datum/preference/numeric/human/last_bday_note
	category = PREFERENCE_CATEGORY_MANUALLY_RENDERED
	savefile_key = "last_bday_note"
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE

	step = 1
	minimum = 0
	maximum = 9999

/datum/preference/numeric/human/last_bday_note/apply_to_human(mob/living/carbon/human/target, value)
	return

/datum/preference/numeric/human/last_bday_note/create_default_value()
	return 0

/datum/preference/numeric/human/last_bday_note/is_accessible(datum/preferences/preferences)
	..()
	return FALSE

/datum/preference/text/living/ooc_notes
	category = PREFERENCE_CATEGORY_MANUALLY_RENDERED
	savefile_identifier = PREFERENCE_CHARACTER
	savefile_key = "OOC_Notes"
	maximum_value_length = MAX_MESSAGE_LEN * 4
	can_randomize = FALSE

/datum/preference/text/living/ooc_notes/apply_to_living(mob/living/target, value)
	target.identity().set_ooc_notes(text_or_null(value))
	return

/datum/preference/text/living/ooc_notes_likes
	category = PREFERENCE_CATEGORY_MANUALLY_RENDERED
	savefile_identifier = PREFERENCE_CHARACTER
	savefile_key = "OOC_Notes_Likes"
	maximum_value_length = MAX_MESSAGE_LEN * 2
	can_randomize = FALSE

/datum/preference/text/living/ooc_notes_likes/apply_to_living(mob/living/target, value)
	target.identity().ooc_notes_likes = text_or_null(value)
	return

/datum/preference/text/living/ooc_notes_dislikes
	category = PREFERENCE_CATEGORY_MANUALLY_RENDERED
	savefile_identifier = PREFERENCE_CHARACTER
	savefile_key = "OOC_Notes_Disikes"
	maximum_value_length = MAX_MESSAGE_LEN * 2
	can_randomize = FALSE

/datum/preference/text/living/ooc_notes_dislikes/apply_to_living(mob/living/target, value)
	target.identity().ooc_notes_dislikes = text_or_null(value)
	return

/datum/preference/toggle/living/ooc_notes_style
	category = PREFERENCE_CATEGORY_MANUALLY_RENDERED
	savefile_key = "OOC_Notes_System"
	default_value = FALSE
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE

/datum/preference/toggle/living/ooc_notes_style/apply_to_living(mob/living/target, value)
	target.identity().ooc_notes_style = num_or_null(value)
	return

/datum/preference/text/living/ooc_notes_maybes
	category = PREFERENCE_CATEGORY_MANUALLY_RENDERED
	savefile_identifier = PREFERENCE_CHARACTER
	savefile_key = "OOC_Notes_Maybes"
	maximum_value_length = MAX_MESSAGE_LEN * 2
	can_randomize = FALSE

/datum/preference/text/living/ooc_notes_maybes/apply_to_living(mob/living/target, value)
	target.identity().ooc_notes_maybes = text_or_null(value)
	return

/datum/preference/text/living/ooc_notes_favs
	category = PREFERENCE_CATEGORY_MANUALLY_RENDERED
	savefile_identifier = PREFERENCE_CHARACTER
	savefile_key = "OOC_Notes_Favs"
	maximum_value_length = MAX_MESSAGE_LEN * 2
	can_randomize = FALSE

/datum/preference/text/living/ooc_notes_favs/apply_to_living(mob/living/target, value)
	target.identity().ooc_notes_favs = text_or_null(value)
	return

/datum/preference/choiced/living/spawnpoint
	category = PREFERENCE_CATEGORY_MANUALLY_RENDERED
	savefile_key = "spawnpoint"
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE

/datum/preference/choiced/living/spawnpoint/init_possible_values()
	var/list/spawnkeys = list()
	for(var/spawntype in GLOB.spawntypes)
		spawnkeys += spawntype
	return spawnkeys

/// What the setup list offers this character (the same check the join makes, /datum/spawnpoint/proc/refusal()).
/datum/preference/choiced/living/spawnpoint/get_pref_choices(datum/preferences/preferences)
	return spawnpoint_choices_for(preferences)

/datum/preference/choiced/living/spawnpoint/validate(datum/preferences/preferences, value)
	return is_valid(value) && (value in spawnpoint_choices_for(preferences))

/datum/preference/choiced/living/spawnpoint/create_informed_default_value(datum/preferences/preferences)
	return spawnpoint_default_for(preferences)

/datum/preference/choiced/living/spawnpoint/apply_to_living(mob/living/target, value)
	return // handled in job_controller

/datum/preference/choiced/living/spawnpoint/create_default_value()
	var/datum/spawnpoint/default_spawnpoint = DEFAULT_LATEJOIN_LOCATION
	return default_spawnpoint::display_name

/datum/preference/choiced/living/emote_sound_mode
	category = PREFERENCE_CATEGORY_MANUALLY_RENDERED
	savefile_identifier = PREFERENCE_CHARACTER
	savefile_key = "emote_sound_mode"

TYPE_TABLE(/datum/preference/choiced/living/emote_sound_mode, pref_choices, list(EMOTE_SOUND_NO_FREQ, EMOTE_SOUND_VOICE_FREQ, EMOTE_SOUND_VOICE_LIST))

/datum/preference/choiced/living/emote_sound_mode/apply_to_living(mob/living/target, value)
	STATE_SET(target, mob_misc, emote_sound_mode, value)

/datum/preference/choiced/living/emote_sound_mode/create_informed_default_value(datum/preferences/preferences)
	return EMOTE_SOUND_VOICE_FREQ
