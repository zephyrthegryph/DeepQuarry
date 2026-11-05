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
	STATE_SET(target, vore_fx, vore_egg_type, value)


/datum/preference/text/human/autohiss
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "autohiss"
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE
	maximum_value_length = MAX_NAME_LEN

/datum/preference/text/human/autohiss/create_default_value()
	return AUTOHISS_DEFAULT_CHOICE

/datum/preference/text/human/autohiss/get_pref_choices(datum/preferences/preferences)
	return assoc_to_keys(GLOB.autohiss_choices)

/datum/preference/text/human/autohiss/get_widget_props(datum/preferences/preferences)
	. = ..()
	.["option_tooltips"] = autohiss_choice_tooltips()

/datum/preference/text/human/autohiss/is_valid(value)
	return !isnull(GLOB.autohiss_choices[value])

/// Saves from before the exact types: Full and Basic were the species' own hiss at that level.
/datum/preference/text/human/autohiss/pref_deserialize(input, datum/preferences/preferences)
	switch(input)
		if("Full")
			return AUTOHISS_DEFAULT_CHOICE
		if("Basic")
			return "Default (Basic)"
	return GLOB.autohiss_choices[input] ? input : AUTOHISS_DEFAULT_CHOICE

/// Read from the prefs of the client speaking (handle_autohiss).
/datum/preference/text/human/autohiss/apply_to_human(mob/living/carbon/human/target, value)
	return
