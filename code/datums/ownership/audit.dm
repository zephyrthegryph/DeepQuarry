// Orphan audit (doc/rewrite/ownership.md §1.5).
//
// Two findings:
//   - orphan: an entity stamped as owned whose owner no longer names it (or is dying);
//   - dropped with a rec: an entity nothing owns or references except its own OM record (the
//     rec.owner cycle), which kept it alive with live timers and hooks. Found with refcount():
//     every reference to the owner beyond the ones its own record holds means someone else
//     still has it. The audit tears the record down (timers, hooks, tasks) and reports it.
//
// Test builds audit every OWN_AUDIT_INTERVAL and fail the run on a finding; servers audit on
// demand ("Ownership Audit" debug verb).

#define OWN_AUDIT_INTERVAL (5 MINUTES)

#ifdef UNIT_TESTS
/// Test builds: every rec's ref text (om_rec_of() adds, the rec's teardown removes).
GLOBAL_LIST_EMPTY(om_rec_audit_index)
#endif

/// Runs the audit. Returns the report lines (each also reported through OWN_REPORT unless `quiet`).
/proc/own_audit(quiet = FALSE)
	. = list()
	#ifdef UNIT_TESTS
	for(var/ref_text in GLOB.own_audit_index.Copy())
		var/datum/D = locate(ref_text)
		if(!isdatum(D) || D.own_holder_ref == null)
			GLOB.own_audit_index -= ref_text
			continue
		if(QDELETED(D))
			continue
		var/datum/H = locate(D.own_holder_ref)
		if(!isdatum(H))
			. += "orphan: [D.type] names an owner that no longer exists ([D.own_slot])"
			own_unstamp(D)
		else if(QDELETED(H))
			. += "orphan: [D.type] is still owned by [H.type].[D.own_slot], which was destroyed"
		else if(!own_names(H, D.own_slot, D))
			. += "orphan: [D.type] is stamped as owned by [H.type].[D.own_slot], which no longer holds it (overwritten or dropped without own_set/own_take)"
			own_unstamp(D)
	for(var/ref_text in GLOB.om_rec_audit_index.Copy())
		var/datum/om/rec/rec = locate(ref_text)
		if(!istype(rec) || rec.torn_down || !rec.owner)
			GLOB.om_rec_audit_index -= ref_text
			continue
		if(own_audit_rec_dropped(rec))
			var/owner_type = rec.owner.type
			. += "dropped with a rec: [owner_type] is referenced only by its own OM record ([length(rec.timers) / OM_TIMER_STRIDE] timer\s); tearing it down"
			om_teardown_rest(rec.owner)
			GLOB.om_rec_audit_index -= ref_text
	#endif
	if(!quiet)
		for(var/line in .)
			OWN_REPORT("AUDIT: [line]")

/// TRUE when rec's owner is referenced by nothing but its own record: unowned, not in the world,
/// not a registered singleton, and refcount() accounted for by the record's internal references.
/proc/own_audit_rec_dropped(datum/om/rec/rec)
	var/datum/O = rec.owner
	if(QDELETED(O) || registry_has(O) || owner_of(O))
		return FALSE
	if(isatom(O))
		var/atom/A = O
		if(A.loc || isturf(A) || isarea(A))
			return FALSE
	if(istype(O, /datum/controller) || istype(O, /datum/om))
		return FALSE
	var/internal = 1 // rec.owner
	for(var/name in rec.vars)
		if(name == "owner" || name == "vars")
			continue
		internal += state_count_refs_in(rec.vars[name], O, 0)
	for(var/datum/om/edge/edge as anything in rec.edges)
		if(edge.source == O)
			internal++
		if(edge.target == O)
			internal++
	// Three references are this proc's: `O`, the argument path through rec, and refcount()'s own.
	return refcount(O) - internal <= own_audit_refcount_overhead()

/// References own_audit_rec_dropped() itself holds while counting, measured once on a probe.
/proc/own_audit_refcount_overhead()
	var/static/overhead
	if(isnull(overhead))
		var/datum/own_audit_probe/probe = new
		var/datum/om/rec/rec = om_rec_of(probe)
		var/internal = 1
		for(var/name in rec.vars)
			if(name == "owner" || name == "vars")
				continue
			internal += state_count_refs_in(rec.vars[name], probe, 0)
		// `probe` here stands in for the audit loop's own variable.
		overhead = refcount(probe) - internal - 1
		om_teardown_rest(probe)
		qdel(probe)
	return overhead

/datum/own_audit_probe

/// Test builds: the periodic audit (started from the unit-test world's start).
/proc/own_audit_periodic()
	var/list/lines = own_audit()
	log_world("OWN AUDIT: [length(lines)] finding\s")
	om_after(om_global_owner(), OWN_AUDIT_INTERVAL, GLOBAL_PROC_REF(own_audit_periodic))

/client/proc/cmd_ownership_audit()
	set name = "Ownership Audit"
	set category = "Debug.Investigate"
	if(!check_rights(R_DEBUG))
		return
	var/list/lines = own_audit(quiet = TRUE)
	to_chat(usr, span_notice("Ownership audit: [length(lines)] finding\s[length(lines) ? "" : " (the index is only kept in test builds)"]."))
	for(var/line in lines)
		to_chat(usr, line)
