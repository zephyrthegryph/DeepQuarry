// Phase 4 of the destroy transaction: relations and ownership (doc/rewrite/ownership.md).
//
// Every object-typed var is exactly one of own / shared / proto / relation, declared next to its
// type (code/__defines/ownership.dm). The ownership framework (code/datums/ownership/) does the
// work; this file is the transaction's entry point and the lifecycle report channel.

/// Runs in the destroy transaction just before phase 4 (links) nulls, deletes and
/// unlinks the declared vars: the place for teardown that must still read them
/// (a holder ending its busy state, a hologram handing bellies back to its master,
/// a projectile drawing its tracers from owned beam segments). Must not sleep.
/datum/proc/lifecycle_prerelease()
	return

/// Assoc: our cache var name -> its invalidation rule, CACHE_ON_CHANGE(bits),
/// CACHE_ON_EVENT(path) or CACHE_ON_RELATION(path) (code/__DEFINES/om.dm). A
/// cache may hold object references; the object-model core nulls it when the
/// rule fires (om_cache_scan(), entity.dm), and tools/ci/declared_refs_lint.py
/// rejects an entry with no rule.
/datum/proc/declared_cache_vars()
	return null

/// Phase 4 (doc/rewrite/lifecycle.md sec 2): rich relation edges, watches and forwards (the OM
/// core), the sparse declared links, then owned values by policy, then REF views on both ends.
/proc/dq_lifecycle_clear_links(datum/D)
	if(D.om_rec)
		entity_teardown_links(D)
	if(D.rx?.link_ends)
		link_teardown(D) // sparse declared links (code/engine/declare/link_state.dm): both ends told, the other end's policy applied
	if(GLOB.dq_lifecycle_trace_depth)
		log_world("LIFECYCLE_TRACE: [D.type] [ref(D)] links: om teardown done")
	own_teardown(D)
	if(GLOB.dq_lifecycle_trace_depth)
		log_world("LIFECYCLE_TRACE: [D.type] [ref(D)] links: owned values done")
	rel_teardown(D)
	if(GLOB.dq_lifecycle_trace_depth)
		log_world("LIFECYCLE_TRACE: [D.type] [ref(D)] links: relation views done")

/// While a list, lifecycle framework reports (ownership cycles, leaks) are
/// appended here instead of raised as runtimes (unit tests of the checks).
GLOBAL_VAR(dq_lifecycle_report_capture)

/// Reports a lifecycle framework violation: a stack_trace (a runtime, so a
/// test run fails), or into GLOB.dq_lifecycle_report_capture while a test
/// captures. Each distinct message is reported once per round.
/proc/dq_lifecycle_report(message)
	var/list/capture = GLOB.dq_lifecycle_report_capture
	if(islist(capture))
		capture += message
		return
	var/static/list/reported = list()
	if(reported[message])
		return
	reported[message] = TRUE
	stack_trace(message)

