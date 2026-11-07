// DQ-migrated: basic body scalar prefs.

/datum/preference/text/human/b_type
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "b_type"
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE
	maximum_value_length = 8
	var/static/list/b_type_choices = list("A-", "A+", "B-", "B+", "AB-", "AB+", "O-", "O+")

/datum/preference/text/human/b_type/create_default_value()
	return DEFAULT_BLOOD_TYPE

/datum/preference/text/human/b_type/get_pref_choices(datum/preferences/preferences)
	return b_type_choices

/datum/preference/text/human/b_type/apply_to_human(mob/living/carbon/human/target, value)
	if(target.dna)
		target.dna.b_type = text_or_null(value)



/datum/preference/text/human/h_style
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "hair_style_name"  // disk-key match
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE
	maximum_value_length = MAX_NAME_LEN

/datum/preference/text/human/h_style/create_default_value()
	return "Bald"

/datum/preference/text/human/h_style/get_pref_choices(datum/preferences/preferences)
	return GLOB.hair_styles_list ? assoc_to_keys(GLOB.hair_styles_list) : null

/datum/preference/text/human/h_style/get_pref_thumbnails(datum/preferences/preferences)
	return sprite_accessory_thumbs(GLOB.hair_styles_list, "_s")

/datum/preference/text/human/h_style/apply_to_human(mob/living/carbon/human/target, value)
	target.looks.set_hair_style(value)


/datum/preference/text/human/f_style
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "facial_style_name"  // disk-key match
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE
	maximum_value_length = MAX_NAME_LEN

/datum/preference/text/human/f_style/create_default_value()
	return "Shaved"

/datum/preference/text/human/f_style/get_pref_choices(datum/preferences/preferences)
	return GLOB.facial_hair_styles_list ? assoc_to_keys(GLOB.facial_hair_styles_list) : null

/datum/preference/text/human/f_style/get_pref_thumbnails(datum/preferences/preferences)
	return sprite_accessory_thumbs(GLOB.facial_hair_styles_list, "_s")

/datum/preference/text/human/f_style/apply_to_human(mob/living/carbon/human/target, value)
	target.looks.set_facial_style(value)



/datum/preference/toggle/human/digitigrade
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "digitigrade"
	default_value = FALSE
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE

/datum/preference/toggle/human/digitigrade/apply_to_human(mob/living/carbon/human/target, value)
	target.looks.set_digitigrade(value)


