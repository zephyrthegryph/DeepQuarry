// DQAdd — Trait list cleanup constraint.
//
// The write path's typed_list/traits.validate already rejects an unpickable trait coming
// from the user. This constraint is for state that becomes unpickable *because of another
// pref change*: the player flips species, toggles synth, switches to meatbag — their
// previously-valid traits may not survive the new context. We prune any that don't.
//
// Both the typed_list validate AND this constraint route through the entity rule
// is_trait_takeable_by(), so the "is this trait legal?" logic exists in exactly one
// place. The constraint adds only what the entity can't know: which structural bucket
// each savefile-loaded trait belongs in (positive/neutral/negative).
//
// Triggers on changes to the trait lists themselves too — that's a no-op now because
// validate already gated the write, but keeps the constraint correct if someone ever
// writes a trait list via write_preference_by_type (which bypasses validate).

/datum/preference_constraint/traits_species_filter
	triggers = list("pos_traits", "neu_traits", "neg_traits", "species", "dirty_synth", "gross_meatbag")
	affects = list("pos_traits", "neu_traits", "neg_traits")

/datum/preference_constraint/traits_species_filter/apply(datum/preferences/preferences, changed_key, old_value, new_value)
	prune_traits(preferences, /datum/preference/typed_list/traits/pos_traits, GLOB.positive_traits)
	prune_traits(preferences, /datum/preference/typed_list/traits/neu_traits, GLOB.neutral_traits)
	prune_traits(preferences, /datum/preference/typed_list/traits/neg_traits, GLOB.negative_traits)

/datum/preference_constraint/traits_species_filter/proc/prune_traits(datum/preferences/preferences, list_type, list/bucket_whitelist)
	var/list/list_value = preferences.read_preference(list_type)
	if(!islist(list_value))
		return
	// read_preference returns a Copy() for list values, so list_value is already an
	// independent reference — safe to mutate without touching the cache. The inner Copy()
	// below is still needed because we're iterating and removing from the same list.
	var/changed = FALSE
	for(var/path in list_value.Copy())
		// Bucket-structural check: the trait must still be in this bucket's whitelist.
		// (A trait moving from positive→neutral on a code change leaves a stale entry.)
		if(!(path in bucket_whitelist))
			list_value -= path
			changed = TRUE
			continue
		// Entity-level rule. Single source of truth — see entity_validation.dm.
		if(!is_trait_takeable_by(path, preferences))
			list_value -= path
			changed = TRUE
	if(changed)
		preferences.update_preference_by_type(list_type, list_value)


/datum/preference_constraint/synth_flag_from_organs
	triggers = list("organ_data")
	affects = list("dirty_synth", "gross_meatbag")

/datum/preference_constraint/synth_flag_from_organs/apply(datum/preferences/preferences, changed_key, old_value, new_value)
	var/list/organ_data = preferences.read_preference(/datum/preference/organ_data)
	if(organ_data && organ_data[O_BRAIN])
		preferences.update_preference_by_type(/datum/preference/toggle/human/dirty_synth, 1)
		preferences.update_preference_by_type(/datum/preference/toggle/human/gross_meatbag, 0)
	else
		preferences.update_preference_by_type(/datum/preference/toggle/human/gross_meatbag, 1)
		preferences.update_preference_by_type(/datum/preference/toggle/human/dirty_synth, 0)


/datum/preference_constraint/trait_budget_reset
	triggers = list("species", "traits_cheating")
	affects = list("starting_trait_points", "max_traits")

/datum/preference_constraint/trait_budget_reset/apply(datum/preferences/preferences, changed_key, old_value, new_value)
	if(preferences.read_preference(/datum/preference/numeric/human/traits_cheating))
		return // admin-cheating prefs persist their custom budget
	var/datum/species/S = GLOB.all_species[preferences.read_preference(/datum/preference/choiced/species)]
	preferences.update_preference_by_type(
		/datum/preference/numeric/human/starting_trait_points,
		S ? S.trait_points : 0,
	)
	preferences.update_preference_by_type(/datum/preference/numeric/human/max_traits, MAX_SPECIES_TRAITS)
