// Common atom OM events (object_model_core.md sec 10, signal_migration_map.md).
//
// These replace the DCS signals of the same name for behaviours: a sender emits
// the event through om_wants()/om_emit(), so an atom with no interested
// behaviour pays one lookup and no allocation. Payload vars are untyped (the
// event lives for one delivery and holds nothing past it); handlers cast.

// ---------------------------------------------------------------- examine

/// Notification (COMSIG_ATOM_EXAMINE): `user` examined the atom. Handlers
/// append lines to `texts`, the examine output list.
/datum/om/event/examine
	coalesce = FALSE
	/// The examining mob.
	var/user
	/// The examine output list (appended to in place).
	var/list/texts

/datum/om/event/examine/New(user, list/texts)
	src.user = user
	src.texts = texts

/datum/om/event/examine/dispatch(datum/om/behaviour/B, datum/E)
	return B.on_examine(E, src)

/datum/om/behaviour/proc/on_examine(datum/E, datum/om/event/examine/event)
	return

/// Emits /datum/om/event/examine on `A` when a behaviour wants it.
/proc/om_emit_examine(atom/A, mob/user, list/texts)
	if(om_wants(A, /datum/om/event/examine))
		om_emit(A, new /datum/om/event/examine(user, texts))

// ---------------------------------------------------------------- moved

/// Notification (COMSIG_MOVABLE_MOVED): the movable changed loc.
/datum/om/event/moved
	coalesce = FALSE
	/// The previous loc.
	var/old_loc
	var/direction
	var/forced

/datum/om/event/moved/New(old_loc, direction, forced)
	src.old_loc = old_loc
	src.direction = direction
	src.forced = forced

/datum/om/event/moved/dispatch(datum/om/behaviour/B, datum/E)
	return B.on_moved(E, src)

/datum/om/behaviour/proc/on_moved(datum/E, datum/om/event/moved/event)
	return

/// Emits /datum/om/event/moved on `AM` when a behaviour wants it.
/proc/om_emit_moved(atom/movable/AM, atom/old_loc, direction, forced)
	if(om_wants(AM, /datum/om/event/moved))
		om_emit(AM, new /datum/om/event/moved(old_loc, direction, forced))

// ---------------------------------------------------------------- cross

/// Veto (was COMSIG_MOVABLE_CROSS): `crosser` tries to cross the movable; EVENT_VETO blocks it.
/datum/om/event/before/cross
	/// The movable crossing.
	var/crosser

/datum/om/event/before/cross/New(crosser)
	src.crosser = crosser

/datum/om/event/before/cross/dispatch(datum/om/behaviour/B, datum/E)
	return B.on_before_cross(E, src)

/datum/om/behaviour/proc/on_before_cross(datum/E, datum/om/event/before/cross/event)
	return

/// TRUE when a behaviour on `AM` vetoes `crosser` crossing it.
/proc/om_cross_vetoed(atom/movable/AM, atom/movable/crosser)
	return om_wants(AM, /datum/om/event/before/cross) && om_emit(AM, new /datum/om/event/before/cross(crosser)) == EVENT_VETO

// ---------------------------------------------------------------- attack_self / attackby

/// Veto (beside COMSIG_ITEM_ATTACK_SELF): `user` uses the item in hand; EVENT_VETO
/// means a behaviour handled it and the attack chain stops.
/datum/om/event/before/attack_self
	var/user

/datum/om/event/before/attack_self/New(user)
	src.user = user

/datum/om/event/before/attack_self/dispatch(datum/om/behaviour/B, datum/E)
	return B.on_before_attack_self(E, src)

/datum/om/behaviour/proc/on_before_attack_self(datum/E, datum/om/event/before/attack_self/event)
	return

/// Veto (beside COMSIG_ATOM_ATTACKBY): `user` hits the atom with `item`; EVENT_VETO
/// means a behaviour handled it and the attack chain stops.
/datum/om/event/before/attackby
	var/item
	var/user
	var/params

/datum/om/event/before/attackby/New(item, user, params)
	src.item = item
	src.user = user
	src.params = params

/datum/om/event/before/attackby/dispatch(datum/om/behaviour/B, datum/E)
	return B.on_before_attackby(E, src)

/datum/om/behaviour/proc/on_before_attackby(datum/E, datum/om/event/before/attackby/event)
	return

// ---------------------------------------------------------------- attack_hand

/// Veto (beside COMSIG_ATOM_ATTACK_HAND, from hand_gate()): `user` touches the atom;
/// EVENT_VETO means a behaviour handled it and the touch stops there.
/datum/om/event/before/attack_hand
	var/user

/datum/om/event/before/attack_hand/New(user)
	src.user = user

/datum/om/event/before/attack_hand/dispatch(datum/om/behaviour/B, datum/E)
	return B.on_before_attack_hand(E, src)

/datum/om/behaviour/proc/on_before_attack_hand(datum/E, datum/om/event/before/attack_hand/event)
	return
