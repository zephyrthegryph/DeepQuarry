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
	/// /datum/system types the holder joins while it exists (section 6).
	var/list/joins

/// Systems this capability's holders join, as /datum/system types. Default: `joins`.
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
	C = cap_intern(C)
	if(cap_of_all(A, C.key))
		return FALSE
	LAZYADD(A.cap_extras, C)
	C.legacy_holder_init(A, FALSE)
	cap_join_systems(A, C)
	refresh_granted_verbs(A)
	changed(A, CHANGE_CAPABILITY)
	return TRUE

/// Detaches the extra capability with key (or type) `key` from A.
/proc/remove_capability(atom/A, key)
	for(var/datum/capability/C as anything in A.cap_extras)
		if(C.key == key || (ispath(key) && istype(C, key)))
			C.legacy_holder_destroy(A)
			cap_leave_systems(A, C)
			LAZYREMOVE(A.cap_extras, C)
			refresh_granted_verbs(A)
			var/datum/data = A.cap_data?[C.key]
			LAZYREMOVE(A.cap_data, C.key)
			if(isdatum(data))
				qdel(data) // ALLOW(lifecycle): capability data is a plain datum in the holder's cap_data table with no slot of its own; the lifecycle verbs only take atoms
			changed(A, CHANGE_CAPABILITY)
			return TRUE
	return FALSE

/// cap_of() over the type's capabilities and the extras.
/proc/cap_of_all(atom/A, key)
	return cap_of(A, key)

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

GLOBAL_LIST_EMPTY(caps_order_cache) // ALLOW(cache): a per-(type, order) memo of sorted capability lists, filled on first use and never invalidated

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

// A capability's `joins` names /datum/system types (controllers/kernel/system.dm): membership is the kernel's
// O(1) join and swap-remove in the one MEMBER store, and the singleton comes from the system registry.

/// A holder joins every system its capability names, held by that capability (so two capabilities naming the same
/// system are two sources, and it leaves when the last goes), and the capability's own type key when some work item
/// runs per member of it (kernel_register_work(..., members = capability type)).
/proc/cap_join_systems(atom/A, datum/capability/C)
	for(var/path in C.systems())
		var/datum/system/S = system(path)
		S.kernel_join(A, C, C.system_role())
	if(kernel().cap_wanted[C.type])
		member_join(C.type, A, C)

/proc/cap_leave_systems(atom/A, datum/capability/C)
	for(var/path in C.systems())
		var/datum/system/S = system(path)
		S.kernel_leave(A, C)
	if(kernel().cap_wanted[C.type])
		member_leave(C.type, A, C)

/// The role the holder plays in the systems this capability names (indexed by members_of(system, role)), or null.
/datum/capability/proc/system_role()
	return null
