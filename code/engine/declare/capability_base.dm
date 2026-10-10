// Shared capability definition fields and declaration hooks.

/datum/capability
	/// Identity for without(): defaults to the type. Two entries with one key cannot coexist.
	var/key

/datum/capability/proc/owned()
	RETURN_TYPE(/list)
	return list()

/datum/capability/proc/refined(list/overrides)
	stack_trace("refine('[key]'): [type] has nothing refine() can change")
	return null

/proc/cap_intern(datum/capability/C)
	var/signature = datum_signature(C)
	var/datum/capability/known = GLOB.caps_interned[signature]
	if(known)
		return known
	GLOB.caps_interned[signature] = C
	return C

/// signature -> the one shared capability with those settings.
GLOBAL_LIST_EMPTY(caps_interned)


/datum/capability/New()
	..()
	if(isnull(key))
		key = type

/proc/capability_list_without(list/L, key)
	. = list()
	for(var/entry in L)
		var/datum/capability/C = entry
		if(istype(C) && (C.key == key || (ispath(key) && istype(C, key))))
			continue
		. += entry

/proc/capability_instance_data(atom/A, datum/capability/C)
	var/datum/D = capability_data(A)?[C.key]
	if(D || !C.data_type)
		return D
	D = new C.data_type
	LAZYSET(capability_runtime(A).data, C.key, D)
	return D

/datum/capability
	/// The datum type cap_data() creates per instance, or null for bit-only state.
	var/data_type
	/// This capability's interaction entries, built once (shared by every holder of the type).
	var/tmp/list/built_entries
