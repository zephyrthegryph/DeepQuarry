// DQ-migrated: trait-budget composite prefs + blood_color.

/datum/preference/color/human/blood_color
	savefile_key = "blood_color"
	savefile_identifier = PREFERENCE_CHARACTER
	category = PREFERENCE_CATEGORY_MANUALLY_RENDERED
	can_randomize = FALSE

/datum/preference/color/human/blood_color/create_default_value()
	return "#A10808"

/datum/preference/color/human/blood_color/apply_to_human(mob/living/carbon/human/target, value)
	return


/datum/preference/numeric/human/starting_trait_points
	savefile_key = "starting_trait_points"
	savefile_identifier = PREFERENCE_CHARACTER
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	can_randomize = FALSE
	minimum = 0
	maximum = 10000
	widget = PREF_WIDGET_HIDDEN  // accumulated trait-point pool, managed by the trait picker

/datum/preference/numeric/human/starting_trait_points/create_default_value()
	return 0

/datum/preference/numeric/human/starting_trait_points/apply_to_human(mob/living/carbon/human/target, value)
	return


/datum/preference/numeric/human/max_traits
	savefile_key = "max_traits"
	savefile_identifier = PREFERENCE_CHARACTER
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	can_randomize = FALSE
	minimum = 0
	maximum = 100
	widget = PREF_WIDGET_HIDDEN  // computed cap, managed by the trait picker

/datum/preference/numeric/human/max_traits/create_default_value()
	return MAX_SPECIES_TRAITS

/datum/preference/numeric/human/max_traits/apply_to_human(mob/living/carbon/human/target, value)
	return


/datum/preference/numeric/human/traits_cheating
	savefile_key = "traits_cheating"
	savefile_identifier = PREFERENCE_CHARACTER
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	can_randomize = FALSE
	minimum = 0
	maximum = 1
	widget = PREF_WIDGET_HIDDEN  // unlock-cheats flag, set by the trait picker


/datum/preference/numeric/human/traits_cheating/create_default_value()
	return 0

/datum/preference/numeric/human/traits_cheating/apply_to_human(mob/living/carbon/human/target, value)
	return


// Trait list prefs — structural shape (list-of-/datum/trait-paths) and contextual
// pickability (species gates, can_take, category) all owned by /datum/preference/typed_list/traits.
// No bespoke is_valid / pref_deserialize / pref_serialize needed; the base handles them.
//
// `required_category` is the only per-bucket declaration.

/datum/preference/typed_list/traits/pos_traits
	savefile_key = "pos_traits"
	savefile_identifier = PREFERENCE_CHARACTER
	category = PREFERENCE_CATEGORY_MANUALLY_RENDERED
	can_randomize = FALSE
	required_category = TRAIT_TYPE_POSITIVE

/datum/preference/typed_list/traits/pos_traits/apply_to_human(mob/living/carbon/human/target, value)
	return
/datum/preference/typed_list/traits/pos_traits/apply_to_living(mob/living/target, value)
	return
/datum/preference/typed_list/traits/pos_traits/apply_to_silicon(mob/living/silicon/target, value)
	return
/datum/preference/typed_list/traits/pos_traits/apply_to_animal(mob/living/simple_mob/target, value)
	return


/datum/preference/typed_list/traits/neu_traits
	savefile_key = "neu_traits"
	savefile_identifier = PREFERENCE_CHARACTER
	category = PREFERENCE_CATEGORY_MANUALLY_RENDERED
	can_randomize = FALSE
	required_category = TRAIT_TYPE_NEUTRAL

/datum/preference/typed_list/traits/neu_traits/apply_to_human(mob/living/carbon/human/target, value)
	return
/datum/preference/typed_list/traits/neu_traits/apply_to_living(mob/living/target, value)
	return
/datum/preference/typed_list/traits/neu_traits/apply_to_silicon(mob/living/silicon/target, value)
	return
/datum/preference/typed_list/traits/neu_traits/apply_to_animal(mob/living/simple_mob/target, value)
	return


/datum/preference/typed_list/traits/neg_traits
	savefile_key = "neg_traits"
	savefile_identifier = PREFERENCE_CHARACTER
	category = PREFERENCE_CATEGORY_MANUALLY_RENDERED
	can_randomize = FALSE
	required_category = TRAIT_TYPE_NEGATIVE

/datum/preference/typed_list/traits/neg_traits/apply_to_human(mob/living/carbon/human/target, value)
	return
/datum/preference/typed_list/traits/neg_traits/apply_to_living(mob/living/target, value)
	return
/datum/preference/typed_list/traits/neg_traits/apply_to_silicon(mob/living/silicon/target, value)
	return
/datum/preference/typed_list/traits/neg_traits/apply_to_animal(mob/living/simple_mob/target, value)
	return
