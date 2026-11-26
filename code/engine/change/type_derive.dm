/// TYPE_DERIVES_* of A's type, decided from declarations: its capabilities, type_verbs(), derived() table, look layers, and the
/// overrides of draw(), hidden_verbs()/granted_verbs() and push_to_rust()/on_state_changed() that `analyze gen plans` lists
/// (GLOB.generated_look_overrides, generated_verb_overrides, generated_side_overrides). TYPE_DERIVES_PENDING only before the generated
/// tables are built (very early boot): every output counts as possible and the verdict is not cached, so the next call decides again.
/proc/type_derive_flags(atom/A)
	var/known = GLOB.type_derives_cache[A.type]
	if(!isnull(known))
		return known
	. = 0
	if(length(caps_of(A)) || present_declares_look(A))
		. |= TYPE_DERIVES_CAPS
	if(length(type_list(A, TYPE_PROC_REF(/atom, type_verbs))))
		. |= TYPE_DERIVES_TYPE_VERBS
	if(derived_table_of(A))
		. |= TYPE_DERIVES_DEPS
	if(look_table_has_layers(table_of(A)))
		. |= TYPE_DERIVES_LOOK // look_layer() entries draw through look_layers_draw(): the type has a look the refresh engine keeps up
	var/draws = type_in_generated_owners(A.type, "generated_look_overrides")
	var/hides = type_in_generated_owners(A.type, "generated_verb_overrides")
	var/side = type_overrides_side_effects(A.type)
	if(isnull(draws) || isnull(hides) || isnull(side))
		return . | TYPE_DERIVES_PENDING
	if(draws)
		. |= TYPE_DERIVES_LOOK
	if(hides)
		. |= TYPE_DERIVES_VERBS
	if(side)
		. |= TYPE_DERIVES_SIDE
	GLOB.type_derives_cache[A.type] = .

/// Whether `path` is or descends from a type listed in the generated owner table GLOB.<table_name> ("<type>" -> TRUE). Null while that
/// table is not built yet. The parsed owner paths are kept per table.
/proc/type_in_generated_owners(path, table_name)
	var/static/list/owners_by_table = list()
	var/list/owners = owners_by_table[table_name]
	if(isnull(owners))
		var/list/rows = GLOB.vars[table_name]
		if(!islist(rows))
			return null
		owners = list()
		for(var/text in rows)
			var/owner = text2path(text)
			if(owner)
				owners += owner
		owners_by_table[table_name] = owners
	for(var/owner in owners)
		if(ispath(path, owner))
			return TRUE
	return FALSE

/// Whether A's type derives anything the refresh engine keeps up (a look or hidden verbs; unknown yet
/// counts as yes).
/proc/type_derives(atom/A)
	return !!(type_derive_flags(A) & (TYPE_DERIVES_LOOK | TYPE_DERIVES_VERBS | TYPE_DERIVES_CAPS | TYPE_DERIVES_PENDING))

GLOBAL_LIST_EMPTY(type_derives_cache) // ALLOW(cache): a per-type memo of derive flags, filled on first use and written in place as a type's capabilities change; shared caches hand out read-only values
