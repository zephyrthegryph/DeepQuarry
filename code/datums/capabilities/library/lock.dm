// The access lock capability (doc/rewrite/dx_conventions.md §2). State: CAP_LOCKED. Swiping an ID
// (or anything whose GetAccess() carries the access) toggles it; entries declaring locked_by = LOCK
// refuse while it is engaged (cap_gate_reason()). Layer: LOOK_LOCKED. Accessor: is_locked().
// The constructor's access is the TYPE DEFAULT (design review H1): a holder whose own req_access /
// req_one_access is set (map edits vary it per instance) is read instead.
//
//	. += cap_lock(access = list(ACCESS_ENGINE))

/datum/capability/lock
	layer_name = LOOK_LOCKED
	/// Every one of these is required (has_access()).
	var/list/req_access
	/// At least one of these is required.
	var/list/req_one_access
	/// What can be swiped.
	var/list/id_types
	/// FALSE when the lock's operations are declared beside it (lock_ops(): a hatch refines and contracts them
	/// by key), so this capability contributes no entries of its own.
	var/entries = TRUE

/// An access lock: access (all required) and/or req_one_access (any one). id_types: what is swiped.
/proc/cap_lock(list/access, list/req_one_access, list/id_types = list(/obj/item/card/id, /obj/item/pda), behind = NONE, blocked_by = NONE, locked_by = NONE, needs, else_say, works_broken = TRUE, works_unpowered = TRUE, log, layer = LOOK_LOCKED, entries = TRUE)
	var/datum/capability/lock/C = new
	C.entries = entries
	C.req_access = access
	C.req_one_access = req_one_access
	C.id_types = id_types
	C.layer_name = layer
	return cap_gating(C, behind = behind, blocked_by = blocked_by, locked_by = locked_by, needs = needs, else_say = else_say, works_broken = works_broken, works_unpowered = works_unpowered, log = log)

/datum/capability/lock/interactions(atom/holder)
	if(!entries)
		return null
	// Electronic: a broken or unpowered holder refuses (the hatch's own lock works either way, lock_op() default).
	return list(adopt_entry(lock_op(id_types, works_broken = FALSE, works_unpowered = FALSE)))

/datum/capability/lock/examine(atom/holder, mob/user)
	return list(is_locked(holder) ? "It is locked." : "It is unlocked.")

/datum/capability/lock/draw(atom/holder, datum/look/look)
	draw_layer(look, when = is_locked(holder))

/datum/capability/lock/ui_data(atom/holder, mob/user, list/data)
	data[LOOK_LOCKED] = is_locked(holder)

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

/**
 * The lock's one operation, CAP_LOCK (action ACT_LOCK): toggle the lock with a credential. A holder adds contracts
 * (cap_require(CAP_LOCK, needs = ...)) and refinements (refine(CAP_LOCK, delay = ...)) to it by key. An alt-click
 * reaches it with anything in hand; a plain click reaches it only with a card the lock accepts in hand (a swipe,
 * `click_with`), so a click with a wrench is still the wrench's. The hatch declares it beside cap_lock(entries = FALSE).
 * It takes no provider slot: the credential is found by cap_lock_credential(), so a silicon can lock with its own access.
 */
/proc/lock_op(list/id_types = list(/obj/item/card/id, /obj/item/pda), behind = NONE, blocked_by = NONE, locked_by = NONE, log, works_broken = TRUE, works_unpowered = TRUE)
	return cap_op("Lock", TYPE_PROC_REF(/atom, cap_lock_toggle), key = CAP_LOCK, action = ACT_LOCK, by = NONE, kind = OP_CONTROL, priority = 10, name_proc = TYPE_PROC_REF(/atom, cap_lock_name), behind = behind, blocked_by = blocked_by, locked_by = locked_by, works_broken = works_broken, works_unpowered = works_unpowered, log = log, click_with = id_types, passes_held = TRUE)

/**
 * The credential provider that opens this lock for `actor`, or null. Credentials are providers, tried like hands:
 * the card held in the hand (when the lock takes that kind of card), then what the actor carries on them (a worn
 * ID or PDA), then the actor themself (a silicon's access). The first that grants is the provider.
 */
/atom/proc/cap_lock_credential(mob/actor, obj/item/held)
	var/datum/capability/lock/C = cap_of(src, /datum/capability/lock)
	if(!C || !actor)
		return null
	if(held && is_type_in_list(held, C.id_types) && C.grants(src, held.GetAccess()))
		return held
	// The actor's own access: the holder's own requirement when it sets one (a map edit, req_access), else the lock's.
	var/obj/O = isobj(src) ? src : null
	var/permitted
	if(O && (length(O.req_access) || length(O.req_one_access)))
		permitted = O.allowed(actor)
	else
		permitted = C.grants(src, actor.GetAccess())
	return permitted ? actor : null

/// The lock op's handler: toggle the lock with the first credential provider that grants it.
/atom/proc/cap_lock_toggle(mob/user, obj/item/held)
	if(!cap_lock_credential(user, held))
		return refuse(user, "Access denied.")
	var/locking = !is_locked(src)
	cap_set(src, CAP_LOCKED, locking)
	act_message(user, src, self = "You [locking ? "lock" : "unlock"] %T%.", others = "%U% [locking ? "locks" : "unlocks"] %T%.")
	return TRUE
