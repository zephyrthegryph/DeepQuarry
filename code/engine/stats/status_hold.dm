// holds_status(STATUS): a status held on an activation's holder for exactly as long as the activation lives (doc/rewrite/final_api.html, section 5
// "Stats": a status is a stat; section 16.4). The status is a status stat (STAT_SLEEPING, STAT_PARALYZED, ...), held the way a voluntary sleep holds
// it: no duration, under the activation's source, released when the activation ends.
//
//   when(cond_all(nameof(on), STAT_OPERABLE), while_slotted(OCCUPANT_SLOT_CRYO, holds_status(STAT_SLEEPING), on = ON_CONTENTS))
//       a working cryo cell keeps its occupant asleep; a cell switched off, unpowered or left lets them wake, with no code that releases anything
//
// It belongs to a granted or slotted activation (a while_slotted() entry, an op's grants()): a type's own CAPABILITIES list has no activation to scope
// it to, and is refused.

/proc/holds_status(status_id)
	return entry_make("holds_status", null, list("status" = status_id))

/datum/entry_engine/status_hold
	kind = "holds_status"

/datum/entry_engine/status_hold/validate(datum/activation/A, datum/entry/E)
	var/datum/stat_def/def = stat_def_of(E.args["status"])
	if(!def?.units)
		return "holds_status(): [E.args["status"]] is not a status"
	return null

/datum/entry_engine/status_hold/apply(datum/activation/A, datum/entry/E, datum/centry/C)
	if(A.scope == SCOPE_TYPE)
		declare_report("[A.def.key] on [A.holder?.type]: holds_status() is for a granted or slotted activation; a type holds a status with its own code")
		return FALSE
	return hold(A.holder, E.args["status"], 1, status_hold_source(A))

/datum/entry_engine/status_hold/remove(datum/activation/A, datum/entry/E)
	var/datum/holder = A.holder
	if(holder && !QDELETED(holder))
		release(holder, E.args["status"], status_hold_source(A))

/// The source a status hold of activation A is placed under: the activation's own source when it is a datum (a slot's other side, a granting
/// item), else the activation itself.
/proc/status_hold_source(datum/activation/A)
	var/datum/source = A.source
	return (isdatum(source) && !QDELETED(source)) ? source : A
