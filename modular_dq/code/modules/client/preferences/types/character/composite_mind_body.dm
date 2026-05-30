// DQAdd — Mind/Body specialty prefs.
//
//   body_points_spent : numeric, 0…body_pool(age). Linear allocation that grants per-point
//                       stat tweaks AND gates which Body threshold perks are buyable.
//   body_perks        : typed_list of /datum/perk/body. Threshold perks the player has
//                       bought from their remaining Body budget.
//   mind_perks        : typed_list of /datum/perk/mind. Per-department perks bought from
//                       the Mind budget.
//
// Pool sizes are derived from the age pref via dq_body_pool_for_age / dq_mind_pool_for_age
// (see _formulas.dm). The constraints in constraints/mind_body_validity.dm re-trim selections
// when the pool shrinks or perk validity changes.

// ─── Linear Body allocation ─────────────────────────────────────────────────────────────

/datum/preference/numeric/body_points_spent
	savefile_key = "body_points_spent"
	savefile_identifier = PREFERENCE_CHARACTER
	category = PREFERENCE_CATEGORY_MANUALLY_RENDERED
	can_randomize = FALSE
	minimum = 0
	maximum = MIND_BODY_BASE_BODY_AT_18  // hard ceiling; constraint refits to pool

/datum/preference/numeric/body_points_spent/create_default_value()
	return 0

/datum/preference/numeric/body_points_spent/apply_to_human(mob/living/carbon/human/target, value)
	return // applied by the Body apply hook (var_changes synthesis path).

// ─── Body threshold perks ──────────────────────────────────────────────────────────────

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

// ─── Mind perks ────────────────────────────────────────────────────────────────────────

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
