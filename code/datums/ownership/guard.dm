// The one teardown guard (doc/rewrite/ownership.md sec 1.1 O5).
//
// Every accessor that gives an entity something new -- an owned value (own_set/own_add/own_put/
// own_transfer/own_move), a relation (rel_set/rel_add, om_link), a prototype or shared value
// (proto_set/proto_private/shared_set), a timer (om_after/om_after_slot, OWN_TIMER slots), a
// hook (om_hook), a task (om_task) or a contents slot (the ledger's note_enter) -- asks
// own_guard() first, and nothing else decides. Releases (own_take, own_remove, own_clear,
// rel_clear, rel_remove, cancelling a timer) are never refused.
//
// The predicate: the holder or the target is at or past LIFECYCLE_REFUSE_PHASE of its destroy
// transaction (LIFECYCLE_DYING(), the datum's destroy_phase). Then the write is refused, in
// exactly one of two ways:
//
// - Silently, while a destroy transaction is running (GLOB.destroy_transaction_depth > 0). This
//   is the documented teardown-safe case: code reached from inside a teardown (a dying holder's
//   on_destroy or prerelease, a spilled item's Moved()/Crossed(), a light re-reading its holder,
//   a UI closing) touching the dying entity or a neighbour that is dying with it. Whatever it
//   would acquire, phase 4 / phase 8 would release again at once, so refusing is the same
//   outcome without the churn, and the caller needs no guard of its own.
// - With a stack trace (OWN_REPORT) otherwise: outside any teardown, reaching for a dead or dying
//   entity is a real bug (a held reference that outlived its target).
//
// The refused accessor returns what it returns for "nothing written" (null / FALSE / 0).

/// TRUE when `holder` may acquire `target` now (either may be null or a non-datum). `what` names
/// the write for the report.
/proc/own_guard(datum/holder, datum/target, what)
	var/holder_dying = isdatum(holder) && LIFECYCLE_DYING(holder)
	if(!holder_dying && !(isdatum(target) && LIFECYCLE_DYING(target)))
		return TRUE
	if(GLOB.destroy_transaction_depth > 0)
		return FALSE // teardown-safe: see the file header
	var/datum/dying = holder_dying ? holder : target
	OWN_REPORT("refused [what]: [isdatum(holder) ? holder.type : "(none)"] -> [isdatum(target) ? target.type : "(none)"]; [dying.type] is being destroyed (phase [dying.destroy_phase ? LIFECYCLE_PHASE_NAME(min(dying.destroy_phase, LIFECYCLE_PHASE_COUNT)) : "queued"])")
	return FALSE
