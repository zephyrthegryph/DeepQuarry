// DQ-migrated scalar prefs.
//   custom_base — custom species base reference (text)
//   dirty_synth / gross_meatbag — body-type categorical toggles
//   custom_link — examine-text profile link

/datum/preference/text/human/custom_base
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "custom_base"
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE
	maximum_value_length = MAX_NAME_LEN

/datum/preference/text/human/custom_base/create_default_value()
	return null

/datum/preference/text/human/custom_base/get_pref_choices(datum/preferences/preferences)
	return GLOB.custom_species_bases ? GLOB.custom_species_bases : null

/datum/preference/text/human/custom_base/apply_to_human(mob/living/carbon/human/target, value)
	return


/datum/preference/toggle/human/dirty_synth
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "dirty_synth"
	default_value = FALSE
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE

/datum/preference/toggle/human/dirty_synth/apply_to_human(mob/living/carbon/human/target, value)
	return


/datum/preference/toggle/human/gross_meatbag
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "gross_meatbag"
	default_value = FALSE
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE

/datum/preference/toggle/human/gross_meatbag/apply_to_human(mob/living/carbon/human/target, value)
	return


/datum/preference/text/human/custom_link
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "custom_link"
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE
	maximum_value_length = 100

/datum/preference/text/human/custom_link/create_default_value()
	return null

/datum/preference/text/human/custom_link/apply_to_human(mob/living/carbon/human/target, value)
	target.custom_link = value
