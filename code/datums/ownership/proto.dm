// Proto (doc/rewrite/ownership.md §3): copy-on-write. A PROTO var holds a registered prototype
// (shared, never deleted) or a private copy stamped with the holder as its owner. Mutating
// code asks for proto_private() first; teardown deletes private copies only.

/// A private copy of this prototype, unowned (proto_private() stamps it). Types with cheaper or
/// domain-specific copies override it; the default clones the owned subtree (entity_clone()).
/datum/proc/proto_copy()
	return entity_clone(src)

/// TRUE when holder.var_name holds a private copy the holder owns.
/proc/proto_is_private(datum/holder, var_name)
	var/datum/value = holder.vars[var_name]
	return isdatum(value) && value.own_holder_ref == ref(holder) && value.own_slot == var_name

/// holder.var_name as a private copy the holder may mutate: made (and owned) on first call.
/proc/proto_private(datum/holder, var_name)
	var/datum/value = holder.vars[var_name]
	if(!isdatum(value) || proto_is_private(holder, var_name))
		return value
	var/datum/copy = value.proto_copy()
	if(!isdatum(copy))
		OWN_REPORT("[value.type]/proto_copy() returned [copy]")
		return value
	own_stamp(copy, holder, var_name)
	holder.vars[var_name] = copy // ALLOW(ownership): the accessor
	return copy

/// Points holder.var_name at a prototype (a registered instance) or adopts an unowned private
/// value. The private copy it replaces is deleted.
/proc/proto_set(datum/holder, var_name, datum/value)
	var/datum/old = holder.vars[var_name]
	if(old == value)
		return value
	var/old_private = proto_is_private(holder, var_name)
	if(isdatum(value) && !registry_has(value))
		if(!own_stamp(value, holder, var_name))
			return null
	holder.vars[var_name] = value // ALLOW(ownership): the accessor
	if(old_private)
		own_unstamp(old)
		if(!QDELETED(old))
			qdel(old)
	return value

/// Teardown: a private copy is deleted, a prototype is just let go.
/proc/proto_teardown(datum/holder, var_name)
	var/datum/value = holder.vars[var_name]
	if(isnull(value))
		return
	var/private = proto_is_private(holder, var_name)
	holder.vars[var_name] = null // ALLOW(ownership): lifecycle teardown
	if(private)
		own_unstamp(value)
		if(!QDELETED(value))
			qdel(value)
