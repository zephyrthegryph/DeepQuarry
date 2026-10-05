// holds_status(STATUS): a status held on an activation's holder for exactly as long as the activation lives (doc/rewrite/final_api.html, section 5
// "Stats": a status is a stat; section 16.4). Until the statuses move onto the stat layer a status id here is the body's status effect (EFFECT_SLEEPING,
// EFFECT_PARALYZED, ...), held the way a voluntary sleep holds it: no duration, released when the activation ends.
//
//   when(cond_all(nameof(on), STAT_OPERABLE), while_slotted(OCCUPANT_SLOT_CRYO, holds_status(EFFECT_SLEEPING), on = ON_CONTENTS))
//       a working cryo cell keeps its occupant asleep; a cell switched off, unpowered or left lets them wake, with no code that releases anything
//
// It belongs to a granted or slotted activation (a while_slotted() entry, an op's grants()): a type's own CAPABILITIES list has no activation to scope
// it to, and is refused.

/proc/holds_status(status_id)
	return entry_make("holds_status", null, list("status" = status_id))

/datum/entry_engine/status_hold
	kind = "holds_status"

/datum/entry_engine/status_hold/validate(datum/activation/A, datum/entry/E)
	if(!om_status_def(E.args["status"]))
		return "holds_status(): [E.args["status"]] is not a status"
	return null

/datum/entry_engine/status_hold/apply(datum/activation/A, datum/entry/E, datum/centry/C)
	if(A.scope == SCOPE_TYPE)
		declare_report("[A.def.key] on [A.holder?.type]: holds_status() is for a granted or slotted activation; a type holds a status with its own code")
		return FALSE
	return om_hold(A.holder, E.args["status"], status_hold_source(A), TRUE, "activation:[A.serial]")

/datum/entry_engine/status_hold/remove(datum/activation/A, datum/entry/E)
	var/datum/holder = A.holder
	if(holder && !QDELETED(holder))
		om_release(holder, E.args["status"], status_hold_source(A), "activation:[A.serial]")

/// The OM source a status hold of activation A is placed under: the activation's own source when it is a datum (a slot's other side, a granting
/// item), else the holder itself; the key tells one activation's hold from another's. The activation record never gets an OM record of its own.
/proc/status_hold_source(datum/activation/A)
	var/datum/source = A.source
	return (isdatum(source) && !QDELETED(source)) ? source : A.holder
