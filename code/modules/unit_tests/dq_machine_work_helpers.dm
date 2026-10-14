// Helpers for the machine work tests: whether a machine's started work (code/library/machine/started_work.dm) may run, is idle, or steps.

/// TRUE when `M` has no step work right now: its declared state doesn't hold (the gate keeps the
/// step from running at all), or its step, run once, says it is done.
/proc/test_machine_idle(obj/machinery/M)
	var/datum/capability/lib/started_work/work = cap_of(M, CAP_STARTED_WORK)
	if(work)
		// A machine with started work (code/library/machine/started_work.dm) is idle when its work is stopped, its `when` does not hold,
		// its gate refuses, or its step ends it.
		if(!work_started(M))
			return TRUE
		if(work.when && !condition_holds(M, work.when))
			return TRUE
		for(var/test in (islist(work.gate) ? work.gate : (work.gate ? list(work.gate) : null)))
			if(!call(M, test)(null))
				return TRUE
		return test_step_machine(M) == PROCESS_KILL
	return TRUE // no declared work: nothing runs

/// TRUE while `M` has started work that may run now (a machine with none never does): the old "is a DM process() subscriber" question.
/proc/machine_stepping(obj/machinery/M)
	return !!cap_of(M, CAP_STARTED_WORK) && test_work_allowed(M)

/// The machine's periodic work may run now: it is started, its `when` holds and its gate passes.
/proc/test_work_allowed(obj/machinery/M)
	var/datum/capability/lib/started_work/work = cap_of(M, CAP_STARTED_WORK)
	if(!work)
		return FALSE
	kernel_drain_now() // a change that starts the work reaches it at the drain
	if(!work_started(M))
		return FALSE
	if(work.when && !condition_holds(M, work.when))
		return FALSE
	for(var/test in (islist(work.gate) ? work.gate : (work.gate ? list(work.gate) : null)))
		if(!call(M, test)(null))
			return FALSE
	return TRUE

/// One step of a machine's periodic work: its started work's step (work_step()).
/proc/test_step_machine(obj/machinery/M)
	. = call(M, "work_step")(null)
	if(. == PROCESS_KILL && cap_of(M, CAP_STARTED_WORK))
		key_set(M, STARTED_WORK_ACTIVE, FALSE) // what the library's step does with PROCESS_KILL
	return .

/// Cross-entity derived input: the holder's work follows a field on the entity its relation names.
