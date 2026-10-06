// Regressions for the OM core review fixes (rewrite/core-fix): event delivery under
// attach/detach, before-event nesting, task interrupts and hook ancestry, the timer
// soonest-cache and id search, the deadline bucket compaction, and interaction shadowing.

// ---------------------------------------------------------------- fixtures

/datum/om/event/cf_probe

/datum/om/event/cf_probe/dispatch(datum/om/behaviour/B, datum/E)
	return B.on_cf_probe(E, src)

/datum/om/behaviour/proc/on_cf_probe(datum/E, datum/om/event/cf_probe/event)
	return

/// Detaches itself (bumping att_ver) when it hears the probe.
/datum/om/behaviour/test/cf_self_detach
	handles = list(/datum/om/event/cf_probe)

/datum/om/behaviour/test/cf_self_detach/on_cf_probe(datum/om_test_entity/E, datum/om/event/cf_probe/event)
	LAZYADD(E.log, "detacher")
	om_detach(E, /datum/om/behaviour/test/cf_self_detach)

/datum/om/behaviour/test/cf_listener
	handles = list(/datum/om/event/cf_probe)

/datum/om/behaviour/test/cf_listener/on_cf_probe(datum/om_test_entity/E, datum/om/event/cf_probe/event)
	E.events++

/datum/om/event/before/cf_outer

/datum/om/event/before/cf_outer/dispatch(datum/om/behaviour/B, datum/om_test_entity/E)
	if(!istype(B, /datum/om/behaviour/test/cf_nesting))
		return null
	LAZYADD(E.log, "outer")
	// A different before-event on the same entity is allowed; its answer is ours.
	return om_emit(E, new /datum/om/event/before/cf_inner)

/datum/om/event/before/cf_inner

/datum/om/event/before/cf_inner/dispatch(datum/om/behaviour/B, datum/om_test_entity/E)
	if(!istype(B, /datum/om/behaviour/test/cf_nesting))
		return null
	LAZYADD(E.log, "inner")
	return E.enabled ? null : EVENT_VETO

/datum/om/behaviour/test/cf_nesting
	handles = list(/datum/om/event/before/cf_outer, /datum/om/event/before/cf_inner)

/// A subtype of the event test_task is interrupted by.
/datum/om/event/test/other/cf_child

/proc/om_cf_global_hit(datum/om_test_entity/L)
	LAZYADD(L.log, "global")

// ---------------------------------------------------------------- events

/// om_deliver() re-finds its place when a handler detaches a behaviour, so the
/// behaviours after it still hear the event exactly once.
/datum/unit_test/om/core_fix_deliver_survives_detach

/datum/unit_test/om/core_fix_deliver_survives_detach/run_om(list/made)
	var/datum/om_test_entity/E = entity(made)
	om_attach(E, /datum/om/behaviour/test/cf_self_detach)
	om_attach(E, /datum/om/behaviour/test/cf_listener)
	om_emit(E, new /datum/om/event/cf_probe)
	TEST_ASSERT_EQUAL(E.events, 1, "the listener heard the event once after the detacher left")
	TEST_ASSERT(!om_attached(E, /datum/om/behaviour/test/cf_self_detach), "the detacher is gone")
	om_emit(E, new /datum/om/event/cf_probe)
	TEST_ASSERT_EQUAL(E.events, 2, "and hears the next one")

/// A before-event may raise a different before-event on the same entity; only
/// the same type re-entering is vetoed.
/datum/unit_test/om/core_fix_nested_before_events

/datum/unit_test/om/core_fix_nested_before_events/run_om(list/made)
	var/datum/om_test_entity/E = entity(made)
	om_attach(E, /datum/om/behaviour/test/cf_nesting)
	var/errors = length(sched.errors)
	TEST_ASSERT_NULL(om_emit(E, new /datum/om/event/before/cf_outer), "nested different before-event is not force-vetoed")
	TEST_ASSERT_EQUAL(length(sched.errors), errors, "and reports nothing")
	TEST_ASSERT(("inner" in E.log), "the inner event was delivered")
	E.enabled = FALSE
	TEST_ASSERT_EQUAL(om_emit(E, new /datum/om/event/before/cf_outer), EVENT_VETO, "the inner veto propagates")
	TEST_ASSERT_NULL(E.om_rec.in_veto, "the guard stack is empty afterwards")
	// Same-type re-entry is still refused (dq_om_core_tests covers the report).
	sched.expect_errors = TRUE
	om_attach(E, /datum/om/behaviour/test/veto_handler)
	var/datum/om/event/before/test_veto/again = new
	again.reenter = TRUE
	TEST_ASSERT_EQUAL(om_emit(E, again), EVENT_VETO, "same-type re-entry is vetoed")

/// Tasks: om_wants() and delivery read a precomputed interrupt set (with subtypes),
/// not "any task wants every event".
// ---------------------------------------------------------------- timers

/// The soonest-due cache and the id binary search: cancelling the soonest timer moves
/// the wheel to the next, cancelling another leaves it, and each fires on time.
/datum/unit_test/om/core_fix_timer_soonest_cache

/datum/unit_test/om/core_fix_timer_soonest_cache/run_om(list/made)
	var/datum/om_test_entity/E = entity(made)
	var/late = after(E, 5 SECONDS, /datum/om_test_entity/proc/timer_hit, with = list("late"))
	var/soon = after(E, 1 SECONDS, /datum/om_test_entity/proc/timer_hit, with = list("soon"))
	var/mid = after(E, 3 SECONDS, /datum/om_test_entity/proc/timer_hit, with = list("mid"))
	var/datum/om/rec/rec = E.om_rec
	TEST_ASSERT_EQUAL(om_timer_index(rec, mid), 2 * OM_TIMER_STRIDE + 1, "binary search finds the third timer")
	TEST_ASSERT_EQUAL(om_timer_index(rec, 999), 0, "and nothing for an unknown id")
	TEST_ASSERT(om_cancel_timer(E, soon), "cancel the soonest")
	TEST_ASSERT(!om_timer_pending(E, soon), "gone")
	TEST_ASSERT(om_timer_pending(E, late) && om_timer_pending(E, mid), "the others remain")
	scheduler_advance(2)
	TEST_ASSERT(!("soon" in E.log), "a cancelled timer never fires")
	TEST_ASSERT(!("mid" in E.log), "not yet")
	scheduler_advance(1.5)
	TEST_ASSERT(("mid" in E.log), "the next soonest fired once the soonest was cancelled")
	TEST_ASSERT(!("late" in E.log), "the late one waits")
	scheduler_advance(2)
	TEST_ASSERT(("late" in E.log), "then it fires")
	TEST_ASSERT_NULL(rec.timer_soonest, "no timers, no soonest")

/// after() decides once whether a proc is global; firing does not re-derive it.
/datum/unit_test/om/core_fix_timer_global_flag

/datum/unit_test/om/core_fix_timer_global_flag/run_om(list/made)
	var/datum/om_test_entity/E = entity(made)
	after(E, 1 SECONDS, /proc/om_cf_global_hit, with = list(E))
	after(E, 1 SECONDS, /datum/om_test_entity/proc/timer_hit, with = list("typed"))
	var/list/T = E.om_rec.timers
	TEST_ASSERT(T[6] & OM_TIMER_GLOBAL, "a /proc/ timer is flagged global")
	TEST_ASSERT(!(T[OM_TIMER_STRIDE + 6] & OM_TIMER_GLOBAL), "a type-proc timer is not")
	scheduler_advance(1.5)
	TEST_ASSERT(("global" in E.log) && ("typed" in E.log), "both fire through the stored flag")

// ---------------------------------------------------------------- deadlines

/// run_bucket() compacts in place: many deadlines sharing a bucket each fire once, and
/// ones not yet due stay put.
/datum/unit_test/om/core_fix_bucket_compaction

/datum/unit_test/om/core_fix_bucket_compaction/run_om(list/made)
	var/list/due = list()
	var/list/later = list()
	for(var/i in 1 to 20)
		var/datum/om_test_entity/E = entity(made)
		om_deadline(E, 1 SECONDS, /datum/om/behaviour/test/deadline_only)
		due += E
	for(var/i in 1 to 5)
		var/datum/om_test_entity/L = entity(made)
		om_deadline(L, 1 SECONDS + OM_DEADLINE_BUCKETS, /datum/om/behaviour/test/deadline_only)
		later += L
	scheduler_advance(1.5)
	for(var/datum/om_test_entity/E as anything in due)
		TEST_ASSERT_EQUAL(E.deadlines, 1, "each shared-bucket deadline fired once")
	for(var/datum/om_test_entity/L as anything in later)
		TEST_ASSERT_EQUAL(L.deadlines, 0, "a deadline a wheel turn away is kept")
		TEST_ASSERT(om_deadline_pending(L, /datum/om/behaviour/test/deadline_only), "and still pending")

// ---------------------------------------------------------------- interactions

/// A headset EXTENDs the radio's interactions instead of discarding its Use (the radio UI).
/datum/unit_test/dq_headset_keeps_radio_use

/datum/unit_test/dq_headset_keeps_radio_use/Run()
	var/obj/item/radio/headset/H = allocate(/obj/item/radio/headset, test_floor())
	var/has_use = FALSE
	var/has_insert = FALSE
	for(var/datum/interaction/I as anything in interaction_candidates(H))
		if(I.default_action == INPUT_ACTION_USE && !I.tool && I.name != "Insert key")
			has_use = TRUE
	// the key slot is the headset's own op now (CAPABILITIES(/obj/item/radio/headset), "Insert key")
	has_insert = op_known_anywhere(null, H, null, "item")
	TEST_ASSERT(has_use, "a headset keeps the radio's Use")
	TEST_ASSERT(has_insert, "and has its own Insert key")
