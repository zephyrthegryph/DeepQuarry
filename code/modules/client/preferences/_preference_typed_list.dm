// DQAdd — Generic base class for preferences whose value is a list of typepaths.
//
// The shape we kept rewriting by hand on every list-of-X pref was:
//   1. is the value a list at all?
//   2. is every entry a typepath under some base type?
//   3. is every entry actually pickable by the current player (species gate, can_take
//      flags, admin allowance, etc.)?
//
// Steps 1-2 are structural and go in is_valid. Step 3 is contextual and goes in validate.
// Subtypes hand the per-entry contextual check off to the entity itself via
// entry_is_pickable(path, prefs); the rule lives with the thing it validates, not
// duplicated across every list-shaped pref.
//
// Subclasses MUST set entry_base_type. They SHOULD override entry_is_pickable when there
// are runtime gates on which entries the player can have. They MAY override
// sanitize_entry() if the wire format needs normalisation (e.g. text → typepath).
//
// Storage on the savefile is always a flat list of typepaths (DM serialises typepaths as
// strings on disk; the load path text2paths them back). check_list_copy on serialise so
// downstream readers can't mutate our cached copy.

/datum/preference/typed_list
	abstract_type = /datum/preference/typed_list

	/// All entries must be a typepath descending from this. Required.
	var/entry_base_type = null

/datum/preference/typed_list/create_default_value()
	return list()

/datum/preference/typed_list/pref_deserialize(input, datum/preferences/preferences)
	if(!islist(input))
		return list()
	var/list/cleaned = list()
	for(var/entry in input)
		var/path = sanitize_entry(entry)
		if(path)
			cleaned += path
	return cleaned

/datum/preference/typed_list/pref_serialize(input)
	if(!islist(input))
		return list()
	return check_list_copy(input)

/// Structural check only — no /datum/preferences access. Subtypes can tighten further
/// (e.g. cap the list length), but the contract is "shape, not policy."
/datum/preference/typed_list/is_valid(value)
	if(!islist(value))
		return FALSE
	if(!entry_base_type)
		return FALSE
	for(var/entry in value)
		if(!ispath(entry, entry_base_type))
			return FALSE
	return TRUE

/// Contextual check: structurally OK AND every entry passes the entity-level pickability
/// rule. update_preference calls this, so a forged Topic with an out-of-species trait /
/// admin-only gear is rejected before reaching write().
/datum/preference/typed_list/validate(datum/preferences/preferences, value)
	if(!is_valid(value))
		return FALSE
	for(var/entry in value)
		if(!entry_is_pickable(entry, preferences))
			return FALSE
	return TRUE

/// Hook for subtypes: is this entry typepath actually pickable for `preferences` right now?
/// The default lets anything structurally valid through. Override on the subtype to delegate
/// to whichever entity-level method owns the rule.
/datum/preference/typed_list/proc/entry_is_pickable(path, datum/preferences/preferences)
	return TRUE

/// Hook for subtypes: normalise / type-coerce an entry coming off the wire. The default
/// accepts already-resolved typepaths and tries text2path on strings (savefile entries are
/// serialised as strings by DM). Subtypes can override to reject specific shapes, look up
/// names against a registry, etc.
/datum/preference/typed_list/proc/sanitize_entry(entry)
	if(ispath(entry, entry_base_type))
		return entry
	if(istext(entry))
		var/path = text2path(entry)
		if(ispath(path, entry_base_type))
			return path
	return null
