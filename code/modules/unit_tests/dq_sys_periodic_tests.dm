// Periodic work declared by state (code/__defines/sys_periodic.dm, doc/rewrite/systems.md section 5).

/// A non-atom holder: New() starts its declarations (lifecycle_decls_init()).
/datum/sys_periodic_test_entity
	var/steps = 0
	var/pulses = 0
	/// pulse() returns REPEAT_STOP once pulses reaches this (0: never).
	var/stop_at = 0

OM_FIELD(/datum/sys_periodic_test_entity, on, FALSE, CHANGE_DATUM_A)
OM_FIELD(/datum/sys_periodic_test_entity, jammed, FALSE, CHANGE_DATUM_B)
OM_FIELD(/datum/sys_periodic_test_entity, pulsing, FALSE, CHANGE_DATUM_C)
DECLARE_PERIODIC_WHILE_ALL(/datum/sys_periodic_test_entity, PERIODIC_SECOND, list("on", "!jammed"))
DECLARE_REPEAT(/datum/sys_periodic_test_entity, 2 SECONDS, pulse, "pulsing")

/datum/sys_periodic_test_entity/New()
	..()
	lifecycle_decls_init(src)

/datum/sys_periodic_test_entity/periodic_step(delta)
	steps++

/datum/sys_periodic_test_entity/proc/pulse()
	pulses++
	if(stop_at && pulses >= stop_at)
		return REPEAT_STOP

/// DECLARE_PERIODIC_WHILE_ALL: the fields' setters start and stop the work; the gate refuses a
/// hand start while the state doesn't hold.
/datum/unit_test/om/sys_periodic_while

/datum/unit_test/om/sys_periodic_while/run_om(list/made)
	var/datum/sys_periodic_test_entity/E = entity(made, /datum/sys_periodic_test_entity)
	TEST_ASSERT_NULL(E.periodic_pipe, "nothing runs while the state doesn't hold")
	TEST_ASSERT(!om_task_periodic(E, PERIODIC_SECOND), "the gate refuses a hand start while off")
	TEST_ASSERT_NULL(E.periodic_pipe, "and the refused start left nothing running")
	E.set_on(TRUE)
	scheduler_advance(0.1)
	TEST_ASSERT_EQUAL(E.periodic_pipe, PERIODIC_SECOND, "set_on(TRUE) starts the declared work")
	// The cadence is kernel work, which the injected-time scheduler does not run: step it by hand, as the kernel would.
	TEST_ASSERT(periodic_run_now(E, PERIODIC_SECOND), "the started work is on its cadence")
	TEST_ASSERT(periodic_run_now(E, PERIODIC_SECOND), "and stays on it")
	TEST_ASSERT(E.steps >= 2, "the body runs on its cadence while on ([E.steps] steps)")
	E.set_jammed(TRUE)
	scheduler_advance(0.1)
	TEST_ASSERT_NULL(E.periodic_pipe, "a negated field that becomes true stops it")
	TEST_ASSERT(!om_task_periodic(E, PERIODIC_SECOND), "the gate refuses while jammed")
	var/frozen = E.steps
	TEST_ASSERT(!periodic_run_now(E, PERIODIC_SECOND), "a stopped entity is not on the cadence")
	TEST_ASSERT_EQUAL(E.steps, frozen, "no steps while stopped")
	E.set_jammed(FALSE)
	scheduler_advance(0.1)
	TEST_ASSERT_EQUAL(E.periodic_pipe, PERIODIC_SECOND, "clearing it restarts the work")
	E.set_on(FALSE)
	scheduler_advance(0.1)
	TEST_ASSERT_NULL(E.periodic_pipe, "set_on(FALSE) stops it")

/// DECLARE_REPEAT: armed while the field holds, cancelled when it stops, REPEAT_STOP ends it.
/datum/unit_test/om/sys_periodic_repeat

/datum/unit_test/om/sys_periodic_repeat/run_om(list/made)
	var/datum/sys_periodic_test_entity/E = entity(made, /datum/sys_periodic_test_entity)
	TEST_ASSERT(!after_pending(E, "sys_repeat:pulse"), "not armed while the field is false")
	E.set_pulsing(TRUE)
	scheduler_advance(0.1)
	TEST_ASSERT(after_pending(E, "sys_repeat:pulse"), "armed once the field holds")
	scheduler_advance(4.5)
	TEST_ASSERT_EQUAL(E.pulses, 2, "runs every delay while the field holds")
	E.set_pulsing(FALSE)
	scheduler_advance(0.1)
	TEST_ASSERT(!after_pending(E, "sys_repeat:pulse"), "the field going false cancels it")
	scheduler_advance(5)
	TEST_ASSERT_EQUAL(E.pulses, 2, "no runs while the field is false")
	E.stop_at = 3
	E.set_pulsing(TRUE)
	scheduler_advance(7)
	TEST_ASSERT_EQUAL(E.pulses, 3, "REPEAT_STOP ends the loop")
	TEST_ASSERT(!after_pending(E, "sys_repeat:pulse"), "and nothing is left pending")

/// The declaration table: fields resolved to their channels, subtypes inherit.
/datum/unit_test/sys_periodic_table

/datum/unit_test/sys_periodic_table/Run()
	var/datum/sys_periodic_table/T = sys_periodic_table_for(/datum/sys_periodic_test_entity)
	TEST_ASSERT_NOTNULL(T, "the declaring type has a table")
	TEST_ASSERT_EQUAL(T.while_def.cadence, PERIODIC_SECOND, "while-declaration cadence")
	TEST_ASSERT_EQUAL(T.while_def.mask, CHANGE_DATUM_A | CHANGE_DATUM_B, "mask is the fields' channels")
	TEST_ASSERT_NOTNULL(T.repeats?["pulse"], "the repeat is keyed by its proc")
	TEST_ASSERT_NULL(sys_periodic_table_for(/datum/om_test_entity), "an undeclared type has none")

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
/datum/sys_periodic_test_target
OM_FIELD(/datum/sys_periodic_test_target, lit, FALSE, CHANGE_DATUM_A)

/datum/sys_periodic_test_holder
/// A relation view (rel_set/rel_clear); a field, so relinking resubscribes the relay.
OM_FIELD_VIEW(/datum/sys_periodic_test_holder, datum/sys_periodic_test_target, target, CHANGE_DATUM_B)
OM_DERIVE_FIELD(/datum/sys_periodic_test_holder, target_lit, list("target.lit"))
DECLARE_PERIODIC_WHILE(/datum/sys_periodic_test_holder, PERIODIC_SECOND, "target_lit")

/datum/sys_periodic_test_holder/New()
	..()
	lifecycle_decls_init(src)

/datum/sys_periodic_test_holder/proc/target_lit()
	return target?.lit

/datum/unit_test/om/sys_periodic_relay

/datum/unit_test/om/sys_periodic_relay/run_om(list/made)
	var/datum/sys_periodic_test_holder/H = entity(made, /datum/sys_periodic_test_holder)
	var/datum/sys_periodic_test_target/A = entity(made, /datum/sys_periodic_test_target)
	var/datum/sys_periodic_test_target/B = entity(made, /datum/sys_periodic_test_target)
	rel_set(H, nameof(H.target), A)
	TEST_ASSERT_NULL(H.periodic_pipe, "an unlit target: no work")
	A.set_lit(TRUE)
	TEST_ASSERT_EQUAL(H.periodic_pipe, PERIODIC_SECOND, "lighting the related target started the holder's work")
	rel_set(H, nameof(H.target), B)
	TEST_ASSERT_NULL(H.periodic_pipe, "relinking to an unlit target stopped it")
	A.set_lit(FALSE)
	A.set_lit(TRUE)
	TEST_ASSERT_NULL(H.periodic_pipe, "the old target no longer relays")
	B.set_lit(TRUE)
	TEST_ASSERT_EQUAL(H.periodic_pipe, PERIODIC_SECOND, "the new target relays")
	rel_clear(H, nameof(H.target))
	TEST_ASSERT_NULL(H.periodic_pipe, "no target: no work")
	rel_set(H, nameof(H.target), B)
	TEST_ASSERT_EQUAL(H.periodic_pipe, PERIODIC_SECOND, "relinking to a lit target resubscribes")
	qdel(B)
	TEST_ASSERT_NULL(H.target, "the view cleared when its target was destroyed")
	TEST_ASSERT_NULL(H.periodic_pipe, "the framework's auto-clear of the relation re-evaluated the derived input")
