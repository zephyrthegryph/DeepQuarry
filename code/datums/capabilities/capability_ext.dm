// Ordering, replace(), per-instance extras and system membership (doc/rewrite/dx_conventions.md §2).

/datum/capability
	/// CAP_* bits that must be CLEAR for this capability's entries (merged onto them).
	var/blocked_by = NONE
	/// The layer name this capability draws (cover_open, panel_open...), overridable per type; CAP_NO_LAYER
	/// draws nothing (a DMI without that state).
	var/layer_name
	/// Draw order when it must differ from list order (lower first). Null: list position.
	var/layer_order
	/// Examine order when it must differ from list order (lower first). Null: list position.
	var/examine_order
	/// The holder var this capability draws (a slot showing its item): a change to that child marks the
	/// holder too (H2: owners are marked only for children they draw). Null: none.
	var/draws_var
	/// /datum/cap_system types the holder joins while it exists (section 6).
	var/list/joins

/// Systems this capability's holders join, as /datum/cap_system types. Default: `joins`.
/datum/capability/proc/systems()
	return joins

/// L with the entry whose key is `key` (or of type `key`) replaced by `replacement`, in the same
/// position. Returns a new list. Replacing a key that isn't there appends (and is reported in tests).
/proc/replace(list/L, key, datum/capability/replacement)
	. = list()
	var/found = FALSE
	for(var/entry in L)
		var/datum/capability/C = entry
		if(!found && istype(C) && (C.key == key || (ispath(key) && istype(C, key))))
			. += replacement
			found = TRUE
			continue
		. += entry
	if(!found)
#ifdef UNIT_TESTS
		stack_trace("replace(): no capability [key] to replace; appended [replacement.type]")
#endif
		. += replacement

// ---- per-instance extras (M4: a lock fitted later, a scope on a gun) ----

/atom
	/// Capabilities attached to this instance at runtime, after the type's. Lazy.
	var/tmp/list/cap_extras

/// The type's capabilities plus this instance's extras. Shared when there are no extras.
/proc/caps_all(atom/A)
	RETURN_TYPE(/list)
	var/list/type_caps = caps_of(A)
	return A.cap_extras ? type_caps + A.cap_extras : type_caps

/// Attaches C to A (and runs its init). Refuses a key A already has.
/proc/add_capability(atom/A, datum/capability/C)
	if(cap_of_all(A, C.key))
		return FALSE
	LAZYADD(A.cap_extras, C)
	C.on_holder_init(A, FALSE)
	cap_join_systems(A, C)
	changed(A, CHANGE_CAPABILITY)
	return TRUE

/// Detaches the extra capability with key (or type) `key` from A.
/proc/remove_capability(atom/A, key)
	for(var/datum/capability/C as anything in A.cap_extras)
		if(C.key == key || (ispath(key) && istype(C, key)))
			C.on_holder_destroy(A)
			cap_leave_systems(A, C)
			LAZYREMOVE(A.cap_extras, C)
			var/datum/data = A.cap_data?[C.key]
			LAZYREMOVE(A.cap_data, C.key)
			if(isdatum(data))
				qdel(data)
			changed(A, CHANGE_CAPABILITY)
			return TRUE
	return FALSE

/// cap_of() over the type's capabilities and the extras.
/proc/cap_of_all(atom/A, key)
	for(var/datum/capability/C as anything in caps_all(A))
		if(C.key == key || (ispath(key) && istype(C, key)))
			return C
	return null

/// The interaction entries of A's extras (the resolver adds them to the type's candidates).
/proc/cap_extra_interactions(atom/A)
	if(!A.cap_extras)
		return list()
	. = list()
	for(var/datum/capability/C as anything in A.cap_extras)
		. += cap_built_entries(C, A)

// ---- ordering (M1) ----

/// A's capabilities in draw or examine order: list order unless some set layer_order/examine_order.
/// Cached per type (extras append in their own order).
/proc/caps_ordered(atom/A, which)
	var/key = "[A.type]|[which]"
	var/list/ordered = GLOB.caps_order_cache[key]
	if(!ordered)
		ordered = caps_sort(caps_of(A), which)
		GLOB.caps_order_cache[key] = ordered
	return A.cap_extras ? ordered + caps_sort(A.cap_extras, which) : ordered

GLOBAL_LIST_EMPTY(caps_order_cache)

/proc/caps_sort(list/caps, which)
	var/any = FALSE
	for(var/datum/capability/C as anything in caps)
		if(!isnull(which == CAP_ORDER_DRAW ? C.layer_order : C.examine_order))
			any = TRUE
			break
	if(!any)
		return caps
	// Stable: entries without an explicit order keep their list index as the order.
	var/list/keyed = list()
	for(var/i in 1 to length(caps))
		var/datum/capability/C = caps[i]
		var/order = which == CAP_ORDER_DRAW ? C.layer_order : C.examine_order
		keyed += list(list(isnull(order) ? i : order, i, C))
	keyed = sortTim(keyed, GLOBAL_PROC_REF(caps_order_cmp))
	. = list()
	for(var/list/row as anything in keyed)
		. += row[3]

/proc/caps_order_cmp(list/a, list/b)
	if(a[1] != b[1])
		return a[1] - b[1]
	return a[2] - b[2]

// ---- system membership (section 6) ----

/// A system capability holders join: iterate `members` instead of scanning atoms.
/datum/cap_system
	/// Members as an assoc list (atom -> TRUE): joining and leaving are O(1).
	var/list/members = list()

/datum/cap_system/proc/join(atom/A)
	members[A] = TRUE

/datum/cap_system/proc/leave(atom/A)
	members -= A

/// The singleton of a cap_system type.
/proc/cap_system(path)
	RETURN_TYPE(/datum/cap_system)
	var/datum/cap_system/S = GLOB.cap_systems[path]
	if(!S)
		S = new path
		GLOB.cap_systems[path] = S
	return S

GLOBAL_LIST_EMPTY(cap_systems)

/proc/cap_join_systems(atom/A, datum/capability/C)
	for(var/path in C.systems())
		var/datum/cap_system/S = cap_system(path)
		S.join(A)

/proc/cap_leave_systems(atom/A, datum/capability/C)
	for(var/path in C.systems())
		var/datum/cap_system/S = cap_system(path)
		S.leave(A)

