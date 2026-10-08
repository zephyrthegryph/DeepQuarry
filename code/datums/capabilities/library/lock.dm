// The access lock capability (doc/rewrite/dx_conventions.md §2). State: CAP_LOCKED. Swiping an ID
// (or anything whose GetAccess() carries the access) toggles it; entries declaring locked_by = LOCK
// refuse while it is engaged (cap_gate_reason()). Draws the part LOOK_LOCKED while locked, or as a `lamp` the
// locked/unlocked glow while the holder is lit and closed up. Accessor: is_locked().
// The constructor's access is the TYPE DEFAULT (design review H1): a holder whose own req_access /
// req_one_access is set (map edits vary it per instance) is read instead.
//
//	. += cap_lock(access = list(ACCESS_ENGINE))

/datum/capability/lock
	/// The key its UI data sits under (caps_ui_data()); what it draws is draw() (the part LOOK_LOCKED, or the lamp).
	layer_name = LOOK_LOCKED
	/// Every one of these is required (has_access()).
	var/list/req_access
	/// At least one of these is required.
	var/list/req_one_access
	/// What can be swiped.
	var/list/id_types
	/// FALSE when the lock's operations are declared beside it (lock_op(): a hatch refines and contracts them
	/// by key), so this capability contributes no entries of its own.
	var/entries = TRUE
	/// TRUE: the lock shows as a lamp (LOOK_LOCKED / LOOK_UNLOCKED, glowing) while the holder is lit and none of blocked_by is open.
	var/lamp = FALSE

/// An access lock: access (all required) and/or req_one_access (any one). id_types: what is swiped.
/proc/cap_lock(list/access, list/req_one_access, list/id_types = list(/obj/item/card/id, /obj/item/pda), needs, else_say, works_broken = TRUE, works_unpowered = TRUE, log, entries = TRUE, lamp = FALSE)
	var/datum/capability/lock/C = new
	C.entries = entries
	C.req_access = access
	C.req_one_access = req_one_access
	C.id_types = id_types
	C.lamp = lamp
	return cap_gating(C, needs = needs, else_say = else_say, works_broken = works_broken, works_unpowered = works_unpowered, log = log)

/datum/capability/lock/interactions(atom/holder)
	if(!entries)
		return null
	// Electronic: a broken or unpowered holder refuses (the hatch's own lock works either way, lock_op() default).
	return list(adopt_entry(lock_op(id_types, works_broken = FALSE, works_unpowered = FALSE)))

/datum/capability/lock/examine(atom/holder, mob/user)
	return list(is_locked(holder) ? "It is locked." : "It is unlocked.")

/datum/capability/lock/draw(atom/holder, datum/look/look)
	if(!lamp)
		look.part(LOOK_LOCKED, is_locked(holder))
	else if(is_lit(holder) && !(blocked_by & capability_bits(holder)))
		look.glow(is_locked(holder) ? LOOK_LOCKED : LOOK_UNLOCKED)

/datum/capability/lock/look_parts()
	return lamp ? list(LOOK_LOCKED, LOOK_UNLOCKED) : list(LOOK_LOCKED)

/datum/capability/lock/legacy_ui_data(atom/holder, mob/user, list/data)
	data[LOOK_LOCKED] = is_locked(holder)

/// Whether `accesses` opens this lock on holder: the holder's own req_access / req_one_access when
/// either is set, else the capability's type default (access_needs(), library/access.dm).
/datum/capability/lock/proc/grants(atom/holder, list/accesses)
	var/list/needs = access_needs(holder, req_access, req_one_access)
	return access_grants(needs[1], needs[2], accesses)

/proc/cap_lock_name(atom/holder, mob/user)
	return is_locked(holder) ? "Unlock" : "Lock"

/**
 * The lock's one operation, CAP_LOCK (action ACT_LOCK): toggle the lock with a credential. A holder adds contracts
 * (cap_require(CAP_LOCK, needs = ...)) and refinements (refine(CAP_LOCK, delay = ...)) to it by key. An alt-click
 * reaches it with anything in hand; a plain click reaches it only with a card the lock accepts in hand (a swipe,
 * `click_with`), so a click with a wrench is still the wrench's. The hatch declares it beside cap_lock(entries = FALSE).
 * It takes no provider slot: the credential is found by cap_lock_credential(src), so a silicon can lock with its own access.
 */
/proc/lock_op(list/id_types = list(/obj/item/card/id, /obj/item/pda), needs, log, works_broken = TRUE, works_unpowered = TRUE)
	var/list/gate = cap_fold_state_needs(needs) // req_set / req_clear: the op's state gates, with their messages
	return cap_op("Lock", GLOBAL_PROC_REF(cap_lock_toggle), key = LEGACY_CAP_LOCK, action = ACT_LOCK, by = NONE, kind = OP_CONTROL, priority = OP_PRIORITY_PART, name_proc = GLOBAL_PROC_REF(cap_lock_name), needs = gate[4], behind = gate[1], blocked_by = gate[2], locked_by = gate[3], works_broken = works_broken, works_unpowered = works_unpowered, log = log, click_with = id_types, passes_held = TRUE)

/**
 * The credential provider that opens this lock for `actor`, or null. Credentials are providers, tried like hands:
 * the card held in the hand (when the lock takes that kind of card), then what the actor carries on them (a worn
 * ID or PDA), then the actor themself (a silicon's access). The first that grants is the provider.
 */
/proc/cap_lock_credential(atom/holder, mob/actor, obj/item/held)
	var/datum/capability/lock/C = cap_of(holder, /datum/capability/lock)
	if(!C || !actor)
		return null
	var/list/needs = access_needs(holder, C.req_access, C.req_one_access)
	return access_credential(holder, actor, held, needs[1], needs[2], C.id_types)

/// The lock op's handler: toggle the lock with the first credential provider that grants it.
/proc/cap_lock_toggle(atom/holder, mob/user, obj/item/held)
	if(!cap_lock_credential(holder, user, held))
		return refuse(user, "Access denied.")
	var/locking = !is_locked(holder)
	cap_set(holder, CAP_LOCKED, locking)
	act_message(user, holder, self = "You [locking ? "lock" : "unlock"] %T%.", others = "%U% [locking ? "locks" : "unlocks"] %T%.")
	return TRUE
