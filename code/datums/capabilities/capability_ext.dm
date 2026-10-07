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
				spent(data)
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
