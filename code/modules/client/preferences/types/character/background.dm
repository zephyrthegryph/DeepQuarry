// Character background preferences
// Handles "Background Information" pref section

/datum/preference/text/human/home_system
	savefile_key = "home_system"
	savefile_identifier = PREFERENCE_CHARACTER
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	can_randomize = FALSE
	maximum_value_length = MAX_NAME_LEN

/datum/preference/text/human/home_system/create_default_value()
	return "Unset"

/datum/preference/text/human/home_system/pref_deserialize(input, datum/preferences/preferences)
	if(!input || !istext(input))
		return create_default_value()
	return sanitize_input(input)

// dropdown choices from the same global the Bay UI used.
/datum/preference/text/human/home_system/get_pref_choices(datum/preferences/preferences)
	return GLOB.home_system_choices + list("Unset")

/datum/preference/text/human/home_system/apply_to_human(mob/living/carbon/human/target, value)
	target.home_system = value

/datum/preference/text/human/birthplace
	savefile_key = "birthplace"
	savefile_identifier = PREFERENCE_CHARACTER
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	can_randomize = FALSE
	maximum_value_length = MAX_NAME_LEN

/datum/preference/text/human/birthplace/create_default_value()
	return "Unset"

/datum/preference/text/human/birthplace/pref_deserialize(input, datum/preferences/preferences)
	if(!input || !istext(input))
		return create_default_value()
	return sanitize_input(input)

// birthplace draws from the same home-systems list.
/datum/preference/text/human/birthplace/get_pref_choices(datum/preferences/preferences)
	return GLOB.home_system_choices + list("Unset")

/datum/preference/text/human/birthplace/apply_to_human(mob/living/carbon/human/target, value)
	target.birthplace = value

/datum/preference/text/human/citizenship
	savefile_key = "citizenship"
	savefile_identifier = PREFERENCE_CHARACTER
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	can_randomize = FALSE
	maximum_value_length = MAX_NAME_LEN

/datum/preference/text/human/citizenship/create_default_value()
	return "None"

/datum/preference/text/human/citizenship/pref_deserialize(input, datum/preferences/preferences)
	if(!input || !istext(input))
		return create_default_value()
	return sanitize_input(input)

// dropdown choices from the same global the Bay UI used.
/datum/preference/text/human/citizenship/get_pref_choices(datum/preferences/preferences)
	return GLOB.citizenship_choices + list("None")

/datum/preference/text/human/citizenship/apply_to_human(mob/living/carbon/human/target, value)
	target.citizenship = value

/datum/preference/text/human/faction
	savefile_key = "faction"
	savefile_identifier = PREFERENCE_CHARACTER
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	can_randomize = FALSE
	maximum_value_length = MAX_NAME_LEN

/datum/preference/text/human/faction/create_default_value()
	return "None"

/datum/preference/text/human/faction/pref_deserialize(input, datum/preferences/preferences)
	if(!input || !istext(input))
		return create_default_value()
	return sanitize_input(input)

// dropdown choices from the same global the Bay UI used.
/datum/preference/text/human/faction/get_pref_choices(datum/preferences/preferences)
	return GLOB.faction_choices + list("None")

/datum/preference/text/human/faction/apply_to_human(mob/living/carbon/human/target, value)
	target.personal_faction = value

/datum/preference/text/human/religion
	savefile_key = "religion"
	savefile_identifier = PREFERENCE_CHARACTER
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	can_randomize = FALSE
	maximum_value_length = MAX_NAME_LEN

/datum/preference/text/human/religion/create_default_value()
	return "None"

/datum/preference/text/human/religion/pref_deserialize(input, datum/preferences/preferences)
	if(!input || !istext(input))
		return create_default_value()
	return sanitize_input(input)

// dropdown choices from the same global the Bay UI used.
/datum/preference/text/human/religion/get_pref_choices(datum/preferences/preferences)
	return GLOB.religion_choices + list("None")

/datum/preference/text/human/religion/apply_to_human(mob/living/carbon/human/target, value)
	target.religion = value

// Economic Status

/datum/preference/choiced/human/economic_status
	savefile_key = "economic_status"
	savefile_identifier = PREFERENCE_CHARACTER
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	can_randomize = FALSE

/datum/preference/choiced/human/economic_status/init_possible_values()
	return ECONOMIC_CLASS

/datum/preference/choiced/human/economic_status/create_default_value()
	return "Average"

/datum/preference/choiced/human/economic_status/apply_to_human(mob/living/carbon/human/target, value)
	return // Economic status is read directly from prefs when needed, not stored on the mob.

// /datum/category_item/player_setup_item/general/background was the Bay-prefs UI
// wrapper for the home_system/birthplace/citizenship/faction/religion/economic_status prefs
// above. The new auto-renderer renders each as a choice/text widget directly.
