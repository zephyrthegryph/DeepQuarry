// DQAdd — NIF cross-pref invariants.

/datum/preference_constraint/species_strips_protean_nif
	triggers = list("species", "nif_path")
	affects = list("nif_path")

/datum/preference_constraint/species_strips_protean_nif/apply(datum/preferences/preferences, changed_key, old_value, new_value)
	var/nif = preferences.read_preference(/datum/preference/nif_path)
	if(ispath(nif, /obj/item/nif/protean) && preferences.read_preference(/datum/preference/choiced/species) != SPECIES_PROTEAN)
		preferences.update_preference_by_type(/datum/preference/nif_path, null)


/datum/preference_constraint/nif_durability_hydration
	triggers = list("nif_path")
	affects = list("nif_durability")

/datum/preference_constraint/nif_durability_hydration/apply(datum/preferences/preferences, changed_key, old_value, new_value)
	var/obj/item/nif/nif_path = preferences.read_preference(/datum/preference/nif_path)
	if(!ispath(nif_path))
		return
	// Treat 0 the same as null. nif_durability.is_valid rejects 0 (a NIF with 0 durability
	// is broken, not a valid persisted value), so a 0 in the cache means "stale data we
	// should re-seed from the NIF's initial value", same as null.
	var/cur = preferences.read_preference(/datum/preference/numeric/nif_durability)
	if(isnull(cur) || cur == 0)
		preferences.update_preference_by_type(/datum/preference/numeric/nif_durability, initial(nif_path.durability))
