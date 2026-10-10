// Common atom OM events (object_model_core.md sec 10, signal_migration_map.md).
//
// These replace the DCS signals of the same name for behaviours: a sender emits
// the event through om_wants()/om_emit(), so an atom with no interested
// behaviour pays one lookup and no allocation. Payload vars are untyped (the
// event lives for one delivery and holds nothing past it); handlers cast.

// ---------------------------------------------------------------- examine

/// Notification: `user` examined the atom. Handlers
/// append lines to `texts`, the examine output list.
/datum/definition_event/examine
	coalesce = FALSE
	/// The examining mob.
	var/user
	/// The examine output list (appended to in place).
	var/list/texts

/datum/definition_event/examine/New(user, list/texts)
	src.user = user
	src.texts = texts

/datum/definition_event/examine/dispatch(datum/scheduled_behaviour/B, datum/E)
	return B.on_examine(E, src)

/datum/scheduled_behaviour/proc/on_examine(datum/E, datum/definition_event/examine/event)
	return

// ---------------------------------------------------------------- moved

/// Notification: the movable changed loc.
/datum/definition_event/moved
	coalesce = FALSE
	/// The previous loc.
	var/old_loc
	var/direction
	var/forced

/datum/definition_event/moved/New(old_loc, direction, forced)
	src.old_loc = old_loc
	src.direction = direction
	src.forced = forced

/datum/definition_event/moved/dispatch(datum/scheduled_behaviour/B, datum/E)
	return B.on_moved(E, src)

/datum/scheduled_behaviour/proc/on_moved(datum/E, datum/definition_event/moved/event)
	return

// ---------------------------------------------------------------- attack_self / attackby

/// Veto: `user` uses the item in hand; EVENT_VETO
/// means a behaviour handled it and the attack chain stops.
/datum/definition_event/before/attack_self
	var/user

/datum/definition_event/before/attack_self/New(user)
	src.user = user

/datum/definition_event/before/attack_self/dispatch(datum/scheduled_behaviour/B, datum/E)
	return B.on_before_attack_self(E, src)

/datum/scheduled_behaviour/proc/on_before_attack_self(datum/E, datum/definition_event/before/attack_self/event)
	return

/// Veto: `user` hits the atom with `item`; EVENT_VETO
/// means a behaviour handled it and the attack chain stops.
/datum/definition_event/before/attackby
	var/item
	var/user
	var/params

/datum/definition_event/before/attackby/New(item, user, params)
	src.item = item
	src.user = user
	src.params = params

/datum/definition_event/before/attackby/dispatch(datum/scheduled_behaviour/B, datum/E)
	return B.on_before_attackby(E, src)

/datum/scheduled_behaviour/proc/on_before_attackby(datum/E, datum/definition_event/before/attackby/event)
	return

// ---------------------------------------------------------------- attack_hand

/// Veto (from hand_gate()): `user` touches the atom;
/// EVENT_VETO means a behaviour handled it and the touch stops there.
/datum/definition_event/before/attack_hand
	var/user

/datum/definition_event/before/attack_hand/New(user)
	src.user = user

/datum/definition_event/before/attack_hand/dispatch(datum/scheduled_behaviour/B, datum/E)
	return B.on_before_attack_hand(E, src)

/datum/scheduled_behaviour/proc/on_before_attack_hand(datum/E, datum/definition_event/before/attack_hand/event)
	return

// ---------------------------------------------------------------- hitby

/// Notification: the atom was hit by thrown `source`.
/datum/definition_event/hitby
	coalesce = FALSE
	var/source
	var/throwingdatum

/datum/definition_event/hitby/New(source, throwingdatum)
	src.source = source
	src.throwingdatum = throwingdatum

/datum/definition_event/hitby/dispatch(datum/scheduled_behaviour/B, datum/E)
	return B.on_hitby(E, src)

/datum/scheduled_behaviour/proc/on_hitby(datum/E, datum/definition_event/hitby/event)
	return
