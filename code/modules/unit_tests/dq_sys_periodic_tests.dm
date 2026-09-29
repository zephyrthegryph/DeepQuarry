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
	scheduler_advance(3)
	TEST_ASSERT(E.steps >= 2, "the body runs on its cadence while on ([E.steps] steps)")
	E.set_jammed(TRUE)
	scheduler_advance(0.1)
	TEST_ASSERT_NULL(E.periodic_pipe, "a negated field that becomes true stops it")
	TEST_ASSERT(!om_task_periodic(E, PERIODIC_SECOND), "the gate refuses while jammed")
	var/frozen = E.steps
	scheduler_advance(3)
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
	TEST_ASSERT(!om_timer_slot_pending(E, "sys_repeat:pulse"), "not armed while the field is false")
	E.set_pulsing(TRUE)
	scheduler_advance(0.1)
	TEST_ASSERT(om_timer_slot_pending(E, "sys_repeat:pulse"), "armed once the field holds")
	scheduler_advance(4.5)
	TEST_ASSERT_EQUAL(E.pulses, 2, "runs every delay while the field holds")
	E.set_pulsing(FALSE)
	scheduler_advance(0.1)
	TEST_ASSERT(!om_timer_slot_pending(E, "sys_repeat:pulse"), "the field going false cancels it")
	scheduler_advance(5)
	TEST_ASSERT_EQUAL(E.pulses, 2, "no runs while the field is false")
	E.stop_at = 3
	E.set_pulsing(TRUE)
	scheduler_advance(7)
	TEST_ASSERT_EQUAL(E.pulses, 3, "REPEAT_STOP ends the loop")
	TEST_ASSERT(!om_timer_slot_pending(E, "sys_repeat:pulse"), "and nothing is left pending")

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
	if(!sys_periodic_allows(M, MACHINE_PIPELINE))
		return TRUE
	return M.machine_step() == PROCESS_KILL
