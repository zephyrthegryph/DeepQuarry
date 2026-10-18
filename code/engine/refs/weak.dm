// Weak references (doc/rewrite/proposals/relations.md D5): ref_one/ref_many(nameof(v), type, weak = TRUE).
//
// The var holds an entity_handle() of its target (a list of handles for a many). It pins nothing: the target is collected as if nobody named
// it, and the generated accessor v() (analyze gen declare, weak_get()) reads null once it is gone, or after a z-level recycle for a turf.
// Nothing is indexed, published or run when the target dies, so a reader that must react to the death declares a normal ref_one. Writes go
// through rel_set / rel_add / rel_remove / rel_clear, which dispatch here on OWNK_WEAK.

/// The weak entry of holder.var_name, or null (reported) when the var is not declared weak.
/proc/weak_entry(datum/holder, var_name, want_list)
	var/list/entry = own_table_of(holder).entries[var_name]
	if(!entry || entry[OWNE_KIND] != OWNK_WEAK)
		OWN_REPORT("[holder.type].[var_name] is not declared ref_one/ref_many(weak = TRUE)")
		return null
	if(!!entry[OWNE_LIST] != !!want_list)
		OWN_REPORT("[holder.type].[var_name] is a weak [entry[OWNE_LIST] ? "many: use rel_add/rel_remove" : "one: use rel_set"]")
		return null
	return entry

/// Points a weak one at `value` (a datum) or clears it with null. Returns `value`, or null when refused.
/proc/weak_set(datum/holder, var_name, datum/value)
	var/list/entry = weak_entry(holder, var_name, FALSE)
	if(!entry)
		return null
	if(!isnull(value) && (!isdatum(value) || !own_type_ok(holder, var_name, entry, value)))
		if(!isdatum(value))
			OWN_REPORT("[holder.type].[var_name] is a weak reference: refused [value], not a datum")
		return null
	var/handle = isnull(value) ? null : entity_handle(value)
	if(holder.vars[var_name] == handle)
		return value
	holder.vars[var_name] = handle
	own_field_changed(holder, var_name)
	return value

/// Adds `value` to a weak many (once). Returns `value`, or null when refused.
/proc/weak_add(datum/holder, var_name, datum/value)
	var/list/entry = weak_entry(holder, var_name, TRUE)
	if(!entry || isnull(value))
		return null
	if(!isdatum(value) || !own_type_ok(holder, var_name, entry, value))
		if(!isdatum(value))
			OWN_REPORT("[holder.type].[var_name] is a weak reference: refused [value], not a datum")
		return null
	var/handle = entity_handle(value)
	var/list/L = holder.vars[var_name]
	if(islist(L) && (handle in L))
		return value
	if(!islist(L))
		L = list()
		holder.vars[var_name] = L
	L += handle
	own_field_changed(holder, var_name)
	return value

/// Drops `value` from a weak many, and any member whose target is gone. TRUE when `value` was a member.
/proc/weak_remove(datum/holder, var_name, datum/value)
	if(!weak_entry(holder, var_name, TRUE) || isnull(value))
		return FALSE
	var/list/L = holder.vars[var_name]
	if(!islist(L))
		return FALSE
	var/handle = entity_handle(value)
	if(!(handle in L))
		return FALSE
	L -= handle
	own_field_changed(holder, var_name)
	return TRUE

/// Empties a weak one or many.
/proc/weak_clear(datum/holder, var_name)
	var/list/entry = own_table_of(holder).entries[var_name]
	if(!entry || entry[OWNE_KIND] != OWNK_WEAK)
		OWN_REPORT("[holder.type].[var_name] is not declared ref_one/ref_many(weak = TRUE)")
		return
	if(isnull(holder.vars[var_name]))
		return
	holder.vars[var_name] = null
	own_field_changed(holder, var_name)

/// What the generated accessor reads: the live target of a weak one (null once it is gone), or a fresh list of the live targets of a weak many
/// (members whose targets are gone are pruned from the var as they are found). Resolve once per proc, not per member per tick.
/proc/weak_get(datum/holder, var_name)
	var/value = holder.vars[var_name]
	if(isnull(value))
		return null
	if(!islist(value))
		return resolve_handle(value)
	. = list()
	var/list/L = value
	var/list/gone
	for(var/handle in L)
		var/datum/D = resolve_handle(handle)
		if(D)
			. += D
		else
			LAZYADD(gone, handle)
	if(gone)
		L -= gone
