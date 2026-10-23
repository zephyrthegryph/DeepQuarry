// Mind/Body specialty prefs.
//
// Two flat typed_lists (body_perks + mind_perks), one entry per selected perk path.
// Pool budgets are PER CATEGORY (each Body sub-category and each Mind department),
// derived from age at read-time; the validator delegates per-entry to
// dq_perk_is_pickable_by which checks the entry's category pool.

/datum/preference/typed_list/body_perks
	savefile_key = "body_perks"
	savefile_identifier = PREFERENCE_CHARACTER
	category = PREFERENCE_CATEGORY_MANUALLY_RENDERED
	can_randomize = FALSE
	entry_base_type = /datum/perk/body

/datum/preference/typed_list/body_perks/entry_is_pickable(path, datum/preferences/preferences)
	if(istext(path))
		path = text2path(path)
	if(!ispath(path, /datum/perk/body))
		return FALSE
	return dq_perk_is_pickable_by(path, preferences)

/datum/preference/typed_list/body_perks/apply_to_human(mob/living/carbon/human/target, value)
	return
/datum/preference/typed_list/body_perks/apply_to_living(mob/living/target, value)
	return
/datum/preference/typed_list/body_perks/apply_to_silicon(mob/living/silicon/target, value)
	return
/datum/preference/typed_list/body_perks/apply_to_animal(mob/living/simple_mob/target, value)
	return

/datum/preference/typed_list/mind_perks
	savefile_key = "mind_perks"
	savefile_identifier = PREFERENCE_CHARACTER
	category = PREFERENCE_CATEGORY_MANUALLY_RENDERED
	can_randomize = FALSE
	entry_base_type = /datum/perk/mind

/datum/preference/typed_list/mind_perks/entry_is_pickable(path, datum/preferences/preferences)
	if(istext(path))
		path = text2path(path)
	if(!ispath(path, /datum/perk/mind))
		return FALSE
	return dq_perk_is_pickable_by(path, preferences)

/datum/preference/typed_list/mind_perks/apply_to_human(mob/living/carbon/human/target, value)
	return
/datum/preference/typed_list/mind_perks/apply_to_living(mob/living/target, value)
	return
/datum/preference/typed_list/mind_perks/apply_to_silicon(mob/living/silicon/target, value)
	return
/datum/preference/typed_list/mind_perks/apply_to_animal(mob/living/simple_mob/target, value)
	return
