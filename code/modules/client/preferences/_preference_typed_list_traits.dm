// DQAdd — Trait-list pref base. Delegates per-entry validity to is_trait_takeable_by()
// on the trait itself (entity_validation.dm). Subtypes only declare `required_category`
// so the pref knows which bucket it represents (positive / neutral / negative).
//
// Replaces the per-pref is_valid = islist(value) overrides we had on pos_traits /
// neu_traits / neg_traits. A forged Topic that ships, say, a positive trait in the
// negative bucket is now rejected at update_preference; previously it would pass
// is_valid and only get pruned later by the constraint (if the constraint fired).

/datum/preference/typed_list/traits
	abstract_type = /datum/preference/typed_list/traits
	entry_base_type = /datum/trait

	/// One of TRAIT_TYPE_POSITIVE / TRAIT_TYPE_NEUTRAL / TRAIT_TYPE_NEGATIVE. The pref
	/// only accepts traits whose initial(category) matches. Required.
	var/required_category

/datum/preference/typed_list/traits/entry_is_pickable(path, datum/preferences/preferences)
	if(istext(path))
		path = text2path(path)
	if(!ispath(path, /datum/trait))
		return FALSE
	var/datum/trait/T = path
	if(initial(T.category) != required_category)
		return FALSE
	return is_trait_takeable_by(path, preferences)
