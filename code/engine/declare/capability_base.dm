// Shared capability definition fields and declaration hooks.

/datum/capability
	/// Identity for without(): defaults to the type. Two entries with one key cannot coexist.
	var/key
	/// This capability's entries need these CAP_* bits SET (behind = COVER|PANEL: reachable only with
	/// the cover / panel open). Merged onto its entries by cap_apply_gating().
	var/behind = NONE
	/// Entries refused while this lock bit is set (LOCK).
	var/locked_by = NONE
	/// PROC_REF on the holder, (mob/user, obj/item/held): TRUE, FALSE (else_say) or a reason text.
	var/needs
	var/else_say
	/// Capability-level: FALSE makes every entry this capability builds refuse while the holder is
	/// broken / unpowered (merged onto the entries by cap_apply_gating()). TRUE (the default) leaves
	/// each entry's own works_broken / works_unpowered in charge.
	var/works_broken = TRUE
	var/works_unpowered = TRUE
	/// LOG_GAME, LOG_ADMIN or null: the dispatcher logs each successful entry at this level.
	var/log
	/// The compartment (BAY_*) the capability's entries are used at, or null (see op_at_reason()).
	var/bay_at

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
	var/datum/D = A.cap_data?[C.key]
	if(D || !C.data_type)
		return D
	D = new C.data_type
	LAZYSET(A.cap_data, C.key, D)
	return D

/datum/capability
	/// The datum type cap_data() creates per instance, or null for bit-only state.
	var/data_type
	/// This capability's interaction entries, built once (shared by every holder of the type).
	var/tmp/list/built_entries
