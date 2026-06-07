// DQAdd — Entity-level pickability rules.
//
// The principle: the rule for "is this trait/gear/style legal for player X right now?"
// lives on the entity (the trait, the gear, the accessory), not duplicated as is_valid
// procs on every pref that holds a list of them.
//
// is_trait_takeable_by(path, prefs) is the canonical answer for traits. It reads only
// trait-declared fields (banned_species, allowed_species, custom_only, can_take, category)
// and the prefs the trait actually cares about (species, dirty_synth, gross_meatbag).
// All checks are static via initial() because trait datums are singletons we don't want
// to instantiate during validation.
//
// Future entities (gear, accessories, body markings) get their own
// is_<entity>_takeable_by procs in this file. The /datum/preference/typed_list/<entity>
// subtype calls them via entry_is_pickable.

/// Returns TRUE if `path` (a /datum/trait typepath) is currently legal for `prefs`.
/// Static — only consults compile-time fields on the trait via initial().
///
/// `path` may legitimately arrive as a typepath (in-memory writes) or as a text path
/// (savefile loads, forged Topic). The proc converts text → path defensively; an
/// unresolvable string is FALSE.
///
/// `prefs` may be null when called from a structural-only context; treat null as "no
/// player to consult" and return TRUE for the entity-shape questions (we're just asking
/// "could this ever be pickable?"). The typed_list validate() path always passes a real
/// prefs; null is only for offline registry walks.
/proc/is_trait_takeable_by(path, datum/preferences/prefs)
	if(istext(path))
		path = text2path(path)
	if(!ispath(path, /datum/trait))
		return FALSE

	if(!prefs)
		return TRUE

	var/datum/trait/T = path
	var/pref_species = prefs.read_preference(/datum/preference/choiced/species)

	// Species gates declared on the trait itself.
	var/list/banned = initial(T.banned_species)
	if(banned && (pref_species in banned))
		return FALSE
	var/list/allowed = initial(T.allowed_species)
	if(allowed && length(allowed) && !(pref_species in allowed))
		return FALSE
	var/custom_only = initial(T.custom_only)
	if(custom_only && pref_species != SPECIES_CUSTOM)
		return FALSE

	// Synthetic / organic compatibility.
	var/can_take = initial(T.can_take)
	var/synth = prefs.read_preference(/datum/preference/toggle/human/dirty_synth)
	var/meat = prefs.read_preference(/datum/preference/toggle/human/gross_meatbag)
	if(synth && !(can_take & SYNTHETICS))
		return FALSE
	if(meat && !(can_take & ORGANICS))
		return FALSE

	return TRUE
