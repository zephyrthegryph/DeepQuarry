// Slot membership is an indexed view of the existing containment ledger.
// The ledger and BYOND loc remain authoritative; no object-model edges are
// retained for each item.
/datum/object_model/relation/slot_member
	from_type = /atom
	to_type = /atom/movable
	virtual = TRUE
	changes_revision = FALSE

/datum/object_model/relation/slot_member/query_from(datum/source)
	var/atom/holder = source
	var/datum/ledger/L = isatom(holder) ? dq_ledger(holder) : null
	return L ? L.ordered() : list()

/datum/object_model/relation/slot_member/query_to(datum/target)
	var/atom/movable/thing = target
	if(!istype(thing) || !isatom(thing.loc))
		return list()
	var/datum/ledger/L = dq_ledger(thing.loc)
	return L?.entries?[thing] ? list(thing.loc) : list()

/datum/object_model/relation/slot_member/virtual_has(datum/source, datum/target)
	var/atom/holder = source
	var/atom/movable/thing = target
	if(!isatom(holder) || !istype(thing) || thing.loc != holder)
		return FALSE
	var/datum/ledger/L = dq_ledger(holder)
	return !!L?.entries?[thing]

/// Legacy COMSIG_SLOT_* remains available; new observers can subscribe to
/// this typed event on a holder. Payload: member, slot ID, inserted.
/datum/object_model/event/slot_membership_changed

/// A member's aggregate contribution or key changed without moving.
/// Payload: member, slot ID.
/datum/object_model/event/slot_contribution_changed

/proc/om_slot_membership_dirty(atom/holder, atom/movable/thing)
	if(!holder?.om_state && !thing?.om_state)
		return
	om_derived_relation_membership_changed(holder, /datum/object_model/relation/slot_member, thing)
	if(holder.om_state)
		om_bump_revision_if_tracked(holder)

/proc/om_slot_membership_event(atom/holder, atom/movable/thing, slot_id, inserted)
	if(holder && (holder.om_state || om_event_has_subscribers(holder, /datum/object_model/event/slot_membership_changed)))
		om_emit(holder, /datum/object_model/event/slot_membership_changed, thing, slot_id, inserted)

/proc/om_slot_contribution_event(atom/holder, atom/movable/thing, slot_id)
	if(holder && (holder.om_state || om_event_has_subscribers(holder, /datum/object_model/event/slot_contribution_changed)))
		om_emit(holder, /datum/object_model/event/slot_contribution_changed, thing, slot_id)
