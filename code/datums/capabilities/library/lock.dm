// The access lock capability (doc/rewrite/dx_conventions.md §2). State: CAP_LOCKED. Swiping an ID
// (or anything whose GetAccess() carries the access) toggles it; entries declaring locked_by = LOCK
// refuse while it is engaged (cap_gate_reason()). Layer: "locked". Accessor: is_locked().
// The constructor's access is the TYPE DEFAULT (design review H1): a holder whose own req_access /
// req_one_access is set (map edits vary it per instance) is read instead.
//
//	. += access_lock(access = list(ACCESS_ENGINE))
//
// Named access_lock(), not lock(): airlocks have a lock() proc, which a bare call inside their
// capabilities() would reach first.

/datum/capability/lock
	/// Every one of these is required (has_access()).
	var/list/req_access
	/// At least one of these is required.
	var/list/req_one_access
	/// What can be swiped.
	var/list/id_types

/// An access lock: access (all required) and/or req_one_access (any one). id_types: what is swiped.
/proc/cap_lock(list/access, list/req_one_access, list/id_types = list(/obj/item/card/id, /obj/item/pda), behind = NONE, log)
	var/datum/capability/lock/C = new
	C.req_access = access
	C.req_one_access = req_one_access
	C.id_types = id_types
	C.behind = behind
	C.log = log
	return C

/datum/capability/lock/interactions(atom/holder)
	var/datum/capability/entry/wrapper = cap_use_on("Lock", id_types, TYPE_PROC_REF(/atom, cap_lock_swipe), behind = behind, log = log, priority = 10, name_proc = TYPE_PROC_REF(/atom, cap_lock_name))
	return list(own_entry(wrapper, id = "lock:[jointext(id_types, ",")]"))

/datum/capability/lock/examine(atom/holder, mob/user)
	return list(is_locked(holder) ? "It is locked." : "It is unlocked.")

/datum/capability/lock/draw(atom/holder, datum/look/look)
	look.overlay("locked", when = is_locked(holder))

/datum/capability/lock/ui_data(atom/holder, mob/user, list/data)
	data["locked"] = is_locked(holder)

/// Whether `accesses` opens this lock on holder: the holder's own req_access / req_one_access when
/// either is set, else the capability's type default.
/datum/capability/lock/proc/grants(atom/holder, list/accesses)
	var/list/need_all = req_access
	var/list/need_one = req_one_access
	if(isobj(holder))
		var/obj/O = holder
		if(length(O.req_access) || length(O.req_one_access))
			need_all = O.req_access
			need_one = O.req_one_access
	if(!length(need_all) && !length(need_one))
		return TRUE
	if(!length(accesses))
		return FALSE
	return has_access(need_all, need_one, accesses)

/atom/proc/cap_lock_name(mob/user)
	return is_locked(src) ? "Unlock" : "Lock"

/atom/proc/cap_lock_swipe(mob/user, obj/item/held)
	var/datum/capability/lock/C = cap_of(src, /datum/capability/lock)
	if(!C.grants(src, held?.GetAccess()))
		return refuse(user, "Access denied.")
	var/locking = !is_locked(src)
	cap_set(src, CAP_LOCKED, locking)
	act_message(user, src, self = "You [locking ? "lock" : "unlock"] %T%.", others = "%U% [locking ? "locks" : "unlocks"] %T%.")
	return TRUE
