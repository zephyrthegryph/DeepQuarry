// DQ-migrated: composite body data — body_markings, flavor_texts,
// flavour_texts_robot, ear_secondary_colors.

/datum/preference/body_markings
	savefile_key = "body_markings"
	savefile_identifier = PREFERENCE_CHARACTER
	category = PREFERENCE_CATEGORY_MANUALLY_RENDERED
	can_randomize = FALSE

/datum/preference/body_markings/create_default_value()
	return list()

/datum/preference/body_markings/pref_deserialize(input, datum/preferences/preferences)
	if(!islist(input))
		return list()
	return input

/datum/preference/body_markings/pref_serialize(input)
	if(!islist(input))
		return list()
	var/list/out = check_list_copy(input)
	for(var/i in out)
		out[i] = check_list_copy(out[i])
		for(var/j in out[i])
			if(islist(out[i][j]))
				out[i][j] = check_list_copy(out[i][j])
	return out

/datum/preference/body_markings/is_valid(value)
	return islist(value)

/datum/preference/body_markings/apply_to_human(mob/living/carbon/human/target, value)
	return
/datum/preference/body_markings/apply_to_living(mob/living/target, value)
	return
/datum/preference/body_markings/apply_to_silicon(mob/living/silicon/target, value)
	return
/datum/preference/body_markings/apply_to_animal(mob/living/simple_mob/target, value)
	return


/datum/preference/flavor_texts
	savefile_key = "flavor_texts"
	savefile_identifier = PREFERENCE_CHARACTER
	category = PREFERENCE_CATEGORY_MANUALLY_RENDERED
	can_randomize = FALSE

/datum/preference/flavor_texts/create_default_value()
	return list()

/datum/preference/flavor_texts/pref_deserialize(input, datum/preferences/preferences)
	if(!islist(input))
		return list()
	return input

/datum/preference/flavor_texts/pref_serialize(input)
	if(!islist(input))
		return list()
	return check_list_copy(input)

/datum/preference/flavor_texts/is_valid(value)
	return islist(value)

/datum/preference/flavor_texts/apply_to_human(mob/living/carbon/human/target, value)
	if(!islist(value))
		return
	// Re-strip on apply. The editor strips on write but a savefile loaded from a state
	// predating that strip (or hand-edited JSON) can carry tags through to the mob —
	// where it lands in examine, character_directory, etc. Cheap insurance.
	for(var/zone in list("general", "head", "face", "eyes", "torso", "arms", "hands", "legs", "feet"))
		var/t = value[zone]
		target.flavor_texts[zone] = istext(t) ? strip_html_simple(t) : null
/datum/preference/flavor_texts/apply_to_living(mob/living/target, value)
	return
/datum/preference/flavor_texts/apply_to_silicon(mob/living/silicon/target, value)
	return
/datum/preference/flavor_texts/apply_to_animal(mob/living/simple_mob/target, value)
	return


/datum/preference/flavour_texts_robot
	savefile_key = "flavour_texts_robot"
	savefile_identifier = PREFERENCE_CHARACTER
	category = PREFERENCE_CATEGORY_MANUALLY_RENDERED
	can_randomize = FALSE

/datum/preference/flavour_texts_robot/create_default_value()
	return list()

/datum/preference/flavour_texts_robot/pref_deserialize(input, datum/preferences/preferences)
	if(!islist(input))
		return list()
	return input

/datum/preference/flavour_texts_robot/pref_serialize(input)
	if(!islist(input))
		return list()
	return check_list_copy(input)

/datum/preference/flavour_texts_robot/is_valid(value)
	return islist(value)

/datum/preference/flavour_texts_robot/apply_to_human(mob/living/carbon/human/target, value)
	return
/datum/preference/flavour_texts_robot/apply_to_living(mob/living/target, value)
	return
/datum/preference/flavour_texts_robot/apply_to_silicon(mob/living/silicon/target, value)
	return
/datum/preference/flavour_texts_robot/apply_to_animal(mob/living/simple_mob/target, value)
	return


/datum/preference/ear_secondary_colors
	savefile_key = "ear_secondary_colors"
	savefile_identifier = PREFERENCE_CHARACTER
	category = PREFERENCE_CATEGORY_MANUALLY_RENDERED
	can_randomize = FALSE

/datum/preference/ear_secondary_colors/create_default_value()
	return list()

/datum/preference/ear_secondary_colors/pref_deserialize(input, datum/preferences/preferences)
	if(!islist(input))
		return list()
	return input

/datum/preference/ear_secondary_colors/pref_serialize(input)
	if(!islist(input))
		return list()
	return check_list_copy(input)

/datum/preference/ear_secondary_colors/is_valid(value)
	return islist(value)

/datum/preference/ear_secondary_colors/apply_to_human(mob/living/carbon/human/target, value)
	target.ear_secondary_colors = SANITIZE_LIST(value)
/datum/preference/ear_secondary_colors/apply_to_living(mob/living/target, value)
	return
/datum/preference/ear_secondary_colors/apply_to_silicon(mob/living/silicon/target, value)
	return
/datum/preference/ear_secondary_colors/apply_to_animal(mob/living/simple_mob/target, value)
	return
