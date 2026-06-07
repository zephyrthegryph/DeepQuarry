// DQ-migrated: thermal comfort range composite prefs.

/datum/preference/custom_heat
	savefile_key = "custom_heat"
	savefile_identifier = PREFERENCE_CHARACTER
	category = PREFERENCE_CATEGORY_MANUALLY_RENDERED
	can_randomize = FALSE

/datum/preference/custom_heat/create_default_value()
	return list()

/datum/preference/custom_heat/pref_deserialize(input, datum/preferences/preferences)
	if(!islist(input))
		return list()
	return input

/datum/preference/custom_heat/pref_serialize(input)
	if(!islist(input))
		return list()
	return check_list_copy(input)

/datum/preference/custom_heat/is_valid(value)
	return islist(value)

/datum/preference/custom_heat/apply_to_human(mob/living/carbon/human/target, value)
	target.custom_heat = value
/datum/preference/custom_heat/apply_to_living(mob/living/target, value)
	return
/datum/preference/custom_heat/apply_to_silicon(mob/living/silicon/target, value)
	return
/datum/preference/custom_heat/apply_to_animal(mob/living/simple_mob/target, value)
	return


/datum/preference/custom_cold
	savefile_key = "custom_cold"
	savefile_identifier = PREFERENCE_CHARACTER
	category = PREFERENCE_CATEGORY_MANUALLY_RENDERED
	can_randomize = FALSE

/datum/preference/custom_cold/create_default_value()
	return list()

/datum/preference/custom_cold/pref_deserialize(input, datum/preferences/preferences)
	if(!islist(input))
		return list()
	return input

/datum/preference/custom_cold/pref_serialize(input)
	if(!islist(input))
		return list()
	return check_list_copy(input)

/datum/preference/custom_cold/is_valid(value)
	return islist(value)

/datum/preference/custom_cold/apply_to_human(mob/living/carbon/human/target, value)
	target.custom_cold = value
/datum/preference/custom_cold/apply_to_living(mob/living/target, value)
	return
/datum/preference/custom_cold/apply_to_silicon(mob/living/silicon/target, value)
	return
/datum/preference/custom_cold/apply_to_animal(mob/living/simple_mob/target, value)
	return
