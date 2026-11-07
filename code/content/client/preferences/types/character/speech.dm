// DQ-migrated: custom speech + custom species name prefs.
// custom_heat/custom_cold remain as lists in the legacy var because they
// hold variable-count multiline messages — that composite shape doesn't
// fit the value-pref model cleanly. Will revisit in the composite-data
// follow-up.
//
// A verb left empty stays empty in the save (the language's own verb applies: a language may hiss); the field shows
// props.default_text instead of a blank box, and typing that text back empties it again.





/datum/preference/text/human/custom_species
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "custom_species"
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE
	maximum_value_length = MAX_NAME_LEN

/datum/preference/text/human/custom_species/create_default_value()
	return null

/datum/preference/text/human/custom_species/apply_to_human(mob/living/carbon/human/target, value)
	target.bio.custom_species = value
