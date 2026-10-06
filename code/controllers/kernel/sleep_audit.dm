// The missed-wake audit for things that sleep on their own timers or watches (was the OM sleeper behaviours).
//
// Something that parks itself between timers (a camera tracking a target, a belly with occupants, a status display, a
// dormant looping sound, a hibernating AI brain, a proximity-gated object) joins the audit with sleep_audit_join(src) and
// overrides sleep_violation(): null while its sleep holds, else why it should be awake. The kernel samples members on its
// audit step (code/controllers/subsystems/behaviours.dm); a violation is a log line on servers and a failure in tests.
// Members are held by REF text, never strongly: a deleted member drops out at its next sample.

/// REF(member) -> TRUE, for every datum that joined the audit.
GLOBAL_LIST_EMPTY(sleep_audited)

/// `D` sleeps on its own timers or watches: the audit samples it from now on.
/proc/sleep_audit_join(datum/D)
	if(D && !QDELETED(D))
		GLOB.sleep_audited["[REF(D)]"] = TRUE

/// For the audit: null while this datum's sleep holds, else why it should be awake.
/datum/proc/sleep_violation()
	SHOULD_NOT_SLEEP(TRUE)
	return null

/// Samples audit members and asks each whether it sleeps through work. Returns the findings; with `report`, a test failure
/// in unit tests and a log line on servers.
/proc/sleep_audit(sample = 64, report = FALSE)
	var/list/findings = list()
	var/list/pool = GLOB.sleep_audited
	var/count = length(pool)
	if(!count)
		return findings
	var/list/keys = list()
	if(count <= sample)
		keys = pool.Copy()
	else
		for(var/i in 1 to sample)
			keys += pool[rand(1, count)]
	for(var/key in keys)
		var/datum/D = locate(key)
		if(!D || QDELETED(D) || REF(D) != key)
			pool -= key
			continue
		var/violation = D.sleep_violation()
		if(!violation)
			continue
		findings += "[D.type]: [violation]"
		if(!report)
			continue
		var/message = "SLEEP_AUDIT: MISSED WAKE [D] ([D.type]) sleeping: [violation]"
		log_runtime(message)
#if defined(UNIT_TESTS)
		if(GLOB.current_test)
			GLOB.current_test.Fail(message, __FILE__, __LINE__)
#endif
	return findings
