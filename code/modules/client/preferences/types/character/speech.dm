// DQ-migrated: custom speech + custom species name prefs.
// custom_heat/custom_cold remain as lists in the legacy var because they
// hold variable-count multiline messages — that composite shape doesn't
// fit the value-pref model cleanly. Will revisit in the composite-data
// follow-up.

/datum/preference/text/human/custom_say
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "custom_say"
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE
	maximum_value_length = 12

/datum/preference/text/human/custom_say/create_default_value()
	return null

/datum/preference/text/human/custom_say/apply_to_human(mob/living/carbon/human/target, value)
	target.custom_say = lowertext(trim(value))


/datum/preference/text/human/custom_whisper
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "custom_whisper"
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE
	maximum_value_length = 12

/datum/preference/text/human/custom_whisper/create_default_value()
	return null

/datum/preference/text/human/custom_whisper/apply_to_human(mob/living/carbon/human/target, value)
	target.custom_whisper = lowertext(trim(value))


/datum/preference/text/human/custom_ask
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "custom_ask"
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE
	maximum_value_length = 12

/datum/preference/text/human/custom_ask/create_default_value()
	return null

/datum/preference/text/human/custom_ask/apply_to_human(mob/living/carbon/human/target, value)
	target.custom_ask = lowertext(trim(value))


/datum/preference/text/human/custom_exclaim
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "custom_exclaim"
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE
	maximum_value_length = 12

/datum/preference/text/human/custom_exclaim/create_default_value()
	return null

/datum/preference/text/human/custom_exclaim/apply_to_human(mob/living/carbon/human/target, value)
	target.custom_exclaim = lowertext(trim(value))


/datum/preference/text/human/custom_species
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "custom_species"
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE
	maximum_value_length = MAX_NAME_LEN

/datum/preference/text/human/custom_species/create_default_value()
	return null

/datum/preference/text/human/custom_species/apply_to_human(mob/living/carbon/human/target, value)
	target.custom_species = value
