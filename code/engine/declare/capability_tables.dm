// Generic capability declaration caches and table interning.

/atom
	/// One bit per boolean capability state (CAP_*). A type default is free per instance.
	var/cap_state = 0
	/// Lazily created per-instance capability data: capability key -> datum (cap_data()).
	var/tmp/list/cap_data

/atom/proc/capability_declarations()
	RETURN_TYPE(/list)
	return list()

/proc/caps_build(atom/A)
	return A.capability_declarations()

/// The cached capability list of A's type. Shared: never write into it.
/proc/caps_of(atom/A)
	RETURN_TYPE(/list)
	return type_list(A, GLOBAL_PROC_REF(caps_build), GLOBAL_PROC_REF(caps_intern_list))

/// Interns every capability of a freshly built list: identical constructor calls anywhere in the tree
/// (a type and each subtype that calls ..(), or two types with the same settings) share ONE datum, so
/// its built entries and their compiled predicates are shared too (the flyweight, review 2 H2).
/proc/caps_intern_list(list/built)
	. = list()
	var/list/at_key = list()
	for(var/entry in built)
		if(istype(entry, /datum/capability/refine))
			cap_apply_refine(., at_key, entry)
			continue
		if(!istype(entry, /datum/capability))
			. += entry
			continue
		var/datum/capability/C = cap_intern(entry)
		// One capability per key: a later entry with the same key replaces the earlier one in its
		// position (a bundle's plain panel is replaced by maintenance_hatch()'s gated one).
		var/slot = at_key["[C.key]"]
		if(slot)
			// An op key declared twice is an init error, unless the later one says replace = TRUE
			// (or is a refine(), handled above): two ops of one key silently shadowing each other is a bug.
			if(C.operation_conflicts(.[slot]))
				stack_trace("duplicate op key '[C.operation_key()]' in one capabilities() list: use refine() or replace = TRUE")
			.[slot] = C
			continue
		. += C
		at_key["[C.key]"] = length(.)

/// Applies refine() R to the op it names in list `into` (at_key: key -> position), or, when the key names a
/// capability that is not an op, to that capability through its refined().
/proc/cap_apply_refine(list/into, list/at_key, datum/capability/refine/R)
	var/slot = at_key["op:[R.base_key]"]
	if(slot)
		into[slot] = cap_intern(refined_operation(into[slot], R))
		return
	slot = at_key["[R.base_key]"]
	if(!slot)
		stack_trace("refine('[R.base_key]') refines an op or capability nothing declared")
		return
	var/datum/capability/base = into[slot]
	var/datum/capability/refined = base.refined(R.overrides)
	if(refined)
		refined.key = base.key
		into[slot] = cap_intern(refined)

/proc/capability_lookup(atom/A, key)
	for(var/datum/capability/C as anything in caps_all(A))
		if(C.key == key || (ispath(key) && istype(C, key)))
			return C
	return null

/datum/capability/proc/operation_conflicts(datum/capability/earlier)
	return FALSE

/datum/capability/proc/operation_key()
	return null

/datum/capability/proc/operation_refined(datum/capability/refine/R)
	return null

/proc/refined_operation(datum/capability/base, datum/capability/refine/R)
	return base.operation_refined(R)
/datum/capability/refine
	var/base_key
	var/list/overrides

/atom
	/// Capabilities attached to this instance at runtime, after the type's. Lazy.
	var/tmp/list/cap_extras

/// The type's capabilities plus this instance's extras. Shared when there are no extras.
/proc/caps_all(atom/A)
	RETURN_TYPE(/list)
	var/list/type_caps = caps_of(A)
	return A.cap_extras ? type_caps + A.cap_extras : type_caps
