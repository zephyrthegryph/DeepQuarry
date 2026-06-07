// DQ-migrated: language composite prefs.

/datum/preference/alternate_languages
	savefile_key = "language"   // disk-key match for existing savefiles
	savefile_identifier = PREFERENCE_CHARACTER
	category = PREFERENCE_CATEGORY_MANUALLY_RENDERED
	can_randomize = FALSE

/datum/preference/alternate_languages/create_default_value()
	return list()

/datum/preference/alternate_languages/pref_deserialize(input, datum/preferences/preferences)
	if(!islist(input))
		return list()
	return input

/datum/preference/alternate_languages/pref_serialize(input)
	if(!islist(input))
		return list()
	return check_list_copy(input)

/datum/preference/alternate_languages/is_valid(value)
	return islist(value)

/datum/preference/alternate_languages/apply_to_human(mob/living/carbon/human/target, value)
	return
/datum/preference/alternate_languages/apply_to_living(mob/living/target, value)
	return
/datum/preference/alternate_languages/apply_to_silicon(mob/living/silicon/target, value)
	return
/datum/preference/alternate_languages/apply_to_animal(mob/living/simple_mob/target, value)
	return


/datum/preference/language_prefixes
	savefile_key = "language_prefixes"
	savefile_identifier = PREFERENCE_CHARACTER
	category = PREFERENCE_CATEGORY_MANUALLY_RENDERED
	can_randomize = FALSE

/datum/preference/language_prefixes/create_default_value()
	return list()

/datum/preference/language_prefixes/pref_deserialize(input, datum/preferences/preferences)
	if(!islist(input))
		return list()
	return input

/datum/preference/language_prefixes/pref_serialize(input)
	if(!islist(input))
		return list()
	return check_list_copy(input)

/datum/preference/language_prefixes/is_valid(value)
	return islist(value)

/datum/preference/language_prefixes/apply_to_human(mob/living/carbon/human/target, value)
	return
/datum/preference/language_prefixes/apply_to_living(mob/living/target, value)
	return
/datum/preference/language_prefixes/apply_to_silicon(mob/living/silicon/target, value)
	return
/datum/preference/language_prefixes/apply_to_animal(mob/living/simple_mob/target, value)
	return


/datum/preference/language_custom_keys
	savefile_key = "language_custom_keys"
	savefile_identifier = PREFERENCE_CHARACTER
	category = PREFERENCE_CATEGORY_MANUALLY_RENDERED
	can_randomize = FALSE

/datum/preference/language_custom_keys/create_default_value()
	return list()

/datum/preference/language_custom_keys/pref_deserialize(input, datum/preferences/preferences)
	if(!islist(input))
		return list()
	return input

/datum/preference/language_custom_keys/pref_serialize(input)
	if(!islist(input))
		return list()
	return check_list_copy(input)

/datum/preference/language_custom_keys/is_valid(value)
	return islist(value)

/datum/preference/language_custom_keys/apply_to_human(mob/living/carbon/human/target, value)
	return
/datum/preference/language_custom_keys/apply_to_living(mob/living/target, value)
	return
/datum/preference/language_custom_keys/apply_to_silicon(mob/living/silicon/target, value)
	return
/datum/preference/language_custom_keys/apply_to_animal(mob/living/simple_mob/target, value)
	return
