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
