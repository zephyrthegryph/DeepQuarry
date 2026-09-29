// Keyed ids: machines linked by a shared id (buttons and the blast doors, airlocks, mass drivers,
// conveyors ... they control) use REL_KEYED / REL_KEYED_LIST views on the source and KEYED_TARGET
// on the target (doc/rewrite/ownership.md §4.1). The framework links them when either end
// materializes. An id can also change at runtime (multitool, construction prompts): set it
// through keyed_set_id(), so the old links drop and the new ones form.

/// Sets D's id var `key_var` to `new_value` and re-links every keyed relation that matches on it,
/// whether D is a REL_KEYED source keyed by that var or a KEYED_TARGET indexed by it.
/proc/keyed_set_id(datum/D, key_var, new_value)
	if(!D || D.vars[key_var] == new_value)
		return
	var/materialized = isatom(D) && !QDELETED(D)
	if(materialized)
		rel_keyed_dematerialize(D)
	// As a target: sources linked to D through their keyed views drop it.
	if(D.keyed_target_var() == key_var)
		for(var/list/pair as anything in rel_sources(D))
			var/datum/source = pair[1]
			var/list/entry = own_table_of(source).entries[pair[2]]
			if(entry && entry[OWNE_EXTRA])
				rel_remove(source, pair[2], D)
	// As a source: its views keyed by this var drop their targets.
	var/datum/own_table/T = own_table_of(D)
	for(var/var_name in T.keyed_vars)
		var/list/spec = T.entries[var_name][OWNE_EXTRA]
		if(spec[2] == key_var)
			rel_clear(D, var_name)
	D.vars[key_var] = new_value
	if(materialized)
		rel_keyed_materialize(D)
