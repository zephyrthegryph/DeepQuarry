// DQ-migrated: vore_egg_type + autohiss basic scalar prefs.

/datum/preference/text/human/vore_egg_type
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "vore_egg_type"
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE
	maximum_value_length = MAX_NAME_LEN

/datum/preference/text/human/vore_egg_type/create_default_value()
	return "Egg"

/datum/preference/text/human/vore_egg_type/get_pref_choices(datum/preferences/preferences)
	return GLOB.global_vore_egg_types

/datum/preference/text/human/vore_egg_type/is_valid(value)
	if(!istext(value))
		return FALSE
	return (value in GLOB.global_vore_egg_types)

/datum/preference/text/human/vore_egg_type/apply_to_human(mob/living/carbon/human/target, value)
	target.vore_egg_type = value


/datum/preference/text/human/autohiss
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "autohiss"
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE
	maximum_value_length = MAX_NAME_LEN

/datum/preference/text/human/autohiss/create_default_value()
	return "Full"

/datum/preference/text/human/autohiss/get_pref_choices(datum/preferences/preferences)
	return list("Off", "Basic", "Full")

/datum/preference/text/human/autohiss/is_valid(value)
	return (value in list("Off", "Basic", "Full"))

/datum/preference/text/human/autohiss/apply_to_human(mob/living/carbon/human/target, value)
	if(!target.client)
		return
	switch(value)
		if("Full")
			target.client.autohiss_mode = AUTOHISS_FULL
		if("Basic")
			target.client.autohiss_mode = AUTOHISS_BASIC
		if("Off")
			target.client.autohiss_mode = AUTOHISS_OFF
		else
			target.client.autohiss_mode = AUTOHISS_FULL
