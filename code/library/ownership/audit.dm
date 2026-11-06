// Orphan audit (doc/rewrite/ownership.md Â§1.5).
//
// Two findings:
//   - orphan: an entity stamped as owned whose owner no longer names it (or is dying);
//   - dropped with a rec: an entity nothing owns or references except the slot table its record's handle named it in,
//     which kept it alive with live timers and hooks. Found with refcount(): any reference beyond the table's means someone else
//     still has it. The audit tears the record down (timers, hooks, tasks), releases the slot and reports it.
//
// Test builds audit every OWN_AUDIT_INTERVAL and fail the run on a finding; servers audit on
// demand ("Ownership Audit" debug verb). The audit walks every live datum (a native loop, well
// under a second on a full map) rather than keeping an index: a per-stamp and per-rec index cost
// a weak key per entity at boot, most of Atoms init on Southern Cross.

#define OWN_AUDIT_INTERVAL (5 MINUTES)

/// Test builds: names the type that stamped D when the key now resolves to another type (a
/// recycled key: the real owner is gone and an unrelated datum reuses its ref).
/proc/own_audit_owner_note(datum/D, datum/H)
	#ifdef UNIT_TESTS
	if(D.own_holder_type && D.own_holder_type != H?.type)
		return " (stamped by [D.own_holder_type]; its key was recycled)"
	#endif
	return ""

/// Runs the audit. Returns the report lines (each also reported through OWN_REPORT unless `quiet`).
/proc/own_audit(quiet = FALSE)
	. = list()
	// Collected first (in a helper, so no loop variable of this frame holds a datum while
	// own_audit_rec_dropped() counts references): the checks below unstamp and tear down.
	var/list/found = own_audit_collect()
	var/list/stamped = found[1]
	var/list/recs = found[2]
	found = null
	for(var/datum/D as anything in stamped)
		if(D.own_holder_ref == null || QDELETED(D))
			continue
		var/datum/H = slot_datum(D.own_holder_ref)
		if(!isdatum(H))
			. += "orphan: [D.type] names an owner that no longer exists ([D.own_slot])[own_audit_owner_note(D, null)]"
			own_unstamp(D)
		else if(QDELETED(H))
			. += "orphan: [D.type] is still owned by [H.type].[D.own_slot], which was destroyed[own_audit_owner_note(D, H)]"
		else if(!own_names(H, D.own_slot, D))
			. += "orphan: [D.type] is stamped as owned by [H.type].[D.own_slot], which no longer holds it (overwritten or dropped without _own_set/own_take)[own_audit_owner_note(D, H)]"
			own_unstamp(D)
	stamped = null
	for(var/datum/scheduler_record/rec as anything in recs)
		if(rec.torn_down || !rec.owner_h)
			continue
		if(own_audit_rec_dropped(rec))
			var/datum/dropped = rec.owner()
			. += "dropped with a rec: [dropped.type] is held only by the slot table behind its scheduler record ([length(rec.timers) / SCHED_TIMER_STRIDE] timer\s); tearing it down"
			entity_teardown_rest(dropped)
			dq_lifecycle_release_slot(dropped)
	if(!quiet)
		for(var/line in .)
			OWN_REPORT("AUDIT: [line]")

/// Every live datum stamped as owned, and every scheduler record: list(stamped, recs).
/proc/own_audit_collect()
	var/list/stamped = list()
	var/list/recs = list()
	for(var/datum/thing) // every live datum
		if(thing.own_holder_ref)
			stamped += thing
		else if(istype(thing, /datum/scheduler_record))
			recs += thing
	return list(stamped, recs)

/// TRUE when rec's owner is held by nothing but the slot table: unowned, not in the world, not a registered singleton, and the slot table's reference is
/// the only one left (the record names its owner by handle, so the record holds nothing; the table keeps the entity until its destroy transaction releases the slot).
/proc/own_audit_rec_dropped(datum/scheduler_record/rec)
	if(!own_audit_owner_candidate(rec))
		return FALSE
	// No variable of this frame holds the owner: slot_refs() counts the table's reference and its own local, the baseline slot_only_refs() measured the same way.
	var/id = rec.owner_h & (SLOT_SPAN - 1)
	return slot_refs(id) <= slot_only_refs()

/// The owner of rec is something the audit may judge dropped: a live, unregistered, unowned datum that is not placed in the world.
/proc/own_audit_owner_candidate(datum/scheduler_record/rec)
	var/datum/O = rec.owner()
	if(!O || QDELETED(O) || is_registered(O) || owner_of(O))
		return FALSE
	if(isatom(O))
		var/atom/A = O
		if(A.loc || isturf(A) || isarea(A))
			return FALSE
	if(istype(O, /datum/controller) || istype(O, /datum/core_definition))
		return FALSE
	// An entity fading out on its own (expire(): a pending self-delete) is on its way out,
	// not dropped.
	if(after_pending(O, "lifecycle_lifetime_timer"))
		return FALSE
	return TRUE

/// World time of the next periodic audit (test builds).
GLOBAL_VAR_INIT(own_audit_next, 0)

/// Test builds: the periodic audit. The suite runner calls it between tests once OWN_AUDIT_INTERVAL has passed (own_audit_due()); it is not a
/// scheduler callback because the walk over every live datum is long enough for the runtime to yield it, and a scheduler callback must not sleep.
/proc/own_audit_periodic()
	// Re-armed first: each finding is reported as a runtime (OWN_REPORT), which unwinds this proc,
	// and a finding must not end the periodic audit for the rest of the run.
	COOLDOWN_START(GLOB, own_audit_next, OWN_AUDIT_INTERVAL)
	var/list/lines = own_audit()
	log_world("OWN AUDIT: [length(lines)] finding\s")

/// TRUE when the periodic audit is due.
/proc/own_audit_due()
	return COOLDOWN_FINISHED(GLOB, own_audit_next)

ADMIN_VERB(ownership_audit, R_DEBUG, "Ownership Audit", "Runs the ownership orphan audit now.", ADMIN_CATEGORY_DEBUG_MISC)
	var/list/lines = own_audit(quiet = TRUE)
	to_chat(user, span_notice("Ownership audit: [length(lines)] finding\s."))
	for(var/line in lines)
		to_chat(user, line)
	log_admin("[key_name(user)] ran the ownership audit: [length(lines)] finding\s.")
