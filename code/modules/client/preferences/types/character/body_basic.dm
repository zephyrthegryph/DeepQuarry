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
		target.dna.b_type = value


/datum/preference/text/human/blood_reagents
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "blood_reagents"
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE
	maximum_value_length = MAX_NAME_LEN
	var/static/list/blood_reagent_choices = list("default", "blood", "ammonia", "vinegar", "milk", "water", "wine")

/datum/preference/text/human/blood_reagents/create_default_value()
	return "default"

/datum/preference/text/human/blood_reagents/get_pref_choices(datum/preferences/preferences)
	return blood_reagent_choices

/datum/preference/text/human/blood_reagents/apply_to_human(mob/living/carbon/human/target, value)
	return


/datum/preference/numeric/human/s_tone
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "skin_tone"  // disk-key match for existing savefiles
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE
	minimum = -185
	maximum = 34

/datum/preference/numeric/human/s_tone/create_default_value()
	return -75

/datum/preference/numeric/human/s_tone/apply_to_human(mob/living/carbon/human/target, value)
	target.s_tone = value


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
	return sprite_accessory_thumbs(GLOB.hair_styles_list)

/datum/preference/text/human/h_style/apply_to_human(mob/living/carbon/human/target, value)
	target.h_style = value


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
	return sprite_accessory_thumbs(GLOB.facial_hair_styles_list)

/datum/preference/text/human/f_style/apply_to_human(mob/living/carbon/human/target, value)
	target.f_style = value


/datum/preference/text/human/grad_style
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "grad_style_name"  // disk-key match
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE
	maximum_value_length = MAX_NAME_LEN

/datum/preference/text/human/grad_style/create_default_value()
	return "none"

/datum/preference/text/human/grad_style/get_pref_choices(datum/preferences/preferences)
	// GLOB.hair_gradients is display-name -> internal-id; the saved pref is the internal id,
	// so flatten the values for the dropdown.
	if(!GLOB.hair_gradients)
		return null
	var/list/out = list()
	for(var/key in GLOB.hair_gradients)
		out += "[GLOB.hair_gradients[key]]"
	return out

/datum/preference/text/human/grad_style/apply_to_human(mob/living/carbon/human/target, value)
	target.grad_style = value


/datum/preference/toggle/human/digitigrade
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "digitigrade"
	default_value = FALSE
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE

/datum/preference/toggle/human/digitigrade/apply_to_human(mob/living/carbon/human/target, value)
	target.digitigrade = value


/datum/preference/toggle/human/synth_color
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "synth_color"
	default_value = FALSE
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE

/datum/preference/toggle/human/synth_color/apply_to_human(mob/living/carbon/human/target, value)
	target.synth_color = value


/datum/preference/toggle/human/synth_markings
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "synth_markings"
	default_value = TRUE
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE

/datum/preference/toggle/human/synth_markings/apply_to_human(mob/living/carbon/human/target, value)
	target.synth_markings = value
