// Orphan audit (doc/rewrite/ownership.md Â§1.5).
//
// Two findings:
//   - orphan: an entity stamped as owned whose owner no longer names it (or is dying);
//   - dropped with a rec: an entity nothing owns or references except its own OM record (the
//     rec.owner cycle), which kept it alive with live timers and hooks. Found with refcount():
//     every reference to the owner beyond the ones its own record holds means someone else
//     still has it. The audit tears the record down (timers, hooks, tasks) and reports it.
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
		var/datum/H = own_locate(D.own_holder_ref)
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
		if(rec.torn_down || !rec.owner)
			continue
		if(own_audit_rec_dropped(rec))
			var/owner_type = rec.owner.type
			. += "dropped with a rec: [owner_type] is referenced only by its own OM record ([length(rec.timers) / OM_TIMER_STRIDE] timer\s); tearing it down"
			om_teardown_rest(rec.owner)
	if(!quiet)
		for(var/line in .)
			OWN_REPORT("AUDIT: [line]")

/// Every live datum stamped as owned, and every OM record: list(stamped, recs).
/proc/own_audit_collect()
	var/list/stamped = list()
	var/list/recs = list()
	for(var/datum/thing) // every live datum
		if(thing.own_holder_ref)
			stamped += thing
		else if(istype(thing, /datum/scheduler_record))
			recs += thing
	return list(stamped, recs)

/// TRUE when rec's owner is referenced by nothing but its own record: unowned, not in the world,
/// not a registered singleton, and refcount() accounted for by the record's internal references.
/proc/own_audit_rec_dropped(datum/scheduler_record/rec)
	var/datum/O = rec.owner
	if(QDELETED(O) || is_registered(O) || owner_of(O))
		return FALSE
	if(isatom(O))
		var/atom/A = O
		if(A.loc || isturf(A) || isarea(A))
			return FALSE
	if(istype(O, /datum/controller) || istype(O, /datum/core_definition))
		return FALSE
	// An entity fading out on its own (om_qdel_after(): a pending self-delete) is on its way out,
	// not dropped.
	var/list/timers = rec.timers
	for(var/i in 1 to length(timers) step OM_TIMER_STRIDE)
		if(timers[i + 2] == /datum/proc/om_qdel_self)
			return FALSE
	var/internal = 1 // rec.owner
	for(var/name in rec.vars)
		if(name == "owner" || name == "vars")
			continue
		internal += state_count_refs_in(rec.vars[name], O, 0)
	for(var/datum/relation_edge/edge as anything in rec.edges)
		if(edge.source == O)
			internal++
		if(edge.target == O)
			internal++
	// One reference is this proc's own `O`; the overhead is what the scheduler holds for an armed
	// entity (measured on a probe the same way).
	return refcount(O) - internal - 1 <= own_audit_refcount_overhead()

/// References own_audit_rec_dropped() itself holds while counting, measured once on a probe.
/proc/own_audit_refcount_overhead()
	var/static/overhead
	if(isnull(overhead))
		var/datum/own_audit_probe/probe = new
		// Armed like the entities the audit looks for (a pending timer), so the scheduler's own
		// references to it (its deadline) are part of the measured overhead.
		after(probe, 1 HOURS, TYPE_PROC_REF(/datum/own_audit_probe, noop))
		var/datum/scheduler_record/rec = om_rec_of(probe)
		var/internal = 1
		for(var/name in rec.vars)
			if(name == "owner" || name == "vars")
				continue
			internal += state_count_refs_in(rec.vars[name], probe, 0)
		// `probe` here stands in for the audit loop's own variable.
		overhead = refcount(probe) - internal - 1
		om_teardown_rest(probe)
		spent(probe)
	return overhead

/datum/own_audit_probe

/datum/own_audit_probe/proc/noop()
	return

/// Test builds: the periodic audit (started from the unit-test world's start).
/proc/own_audit_periodic()
	// Re-armed first: each finding is reported as a runtime (OWN_REPORT), which unwinds this proc,
	// and a finding must not end the periodic audit for the rest of the run.
	after(om_global_owner(), OWN_AUDIT_INTERVAL, GLOBAL_PROC_REF(own_audit_periodic))
	var/list/lines = own_audit()
	log_world("OWN AUDIT: [length(lines)] finding\s")

ADMIN_VERB(ownership_audit, R_DEBUG, "Ownership Audit", "Runs the ownership orphan audit now.", ADMIN_CATEGORY_DEBUG_MISC)
	var/list/lines = own_audit(quiet = TRUE)
	to_chat(user, span_notice("Ownership audit: [length(lines)] finding\s."))
	for(var/line in lines)
		to_chat(user, line)
	log_admin("[key_name(user)] ran the ownership audit: [length(lines)] finding\s.")
