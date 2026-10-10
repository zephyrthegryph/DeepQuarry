// Regressions for the OM core review fixes (rewrite/core-fix): event delivery under
// attach/detach, before-event nesting, task interrupts and hook ancestry, the timer
// soonest-cache and id search, the deadline bucket compaction, and interaction shadowing.

// ---------------------------------------------------------------- fixtures

/datum/om/event/before/cf_outer

/datum/om/event/before/cf_inner

/proc/dq_cf_global_hit(datum/om_test_entity/L)
	LAZYADD(L.log, "global")

// ---------------------------------------------------------------- events

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
	TEST_ASSERT_EQUAL(timer_index(rec, mid), 2 * OM_TIMER_STRIDE + 1, "binary search finds the third timer")
	TEST_ASSERT_EQUAL(timer_index(rec, 999), 0, "and nothing for an unknown id")
	TEST_ASSERT(timer_cancel(E, soon), "cancel the soonest")
	TEST_ASSERT(!timer_pending(E, soon), "gone")
	TEST_ASSERT(timer_pending(E, late) && timer_pending(E, mid), "the others remain")
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
	after(E, 1 SECONDS, /proc/dq_cf_global_hit, with = list(E))
	after(E, 1 SECONDS, /datum/om_test_entity/proc/timer_hit, with = list("typed"))
	var/list/T = E.om_rec.timers
	TEST_ASSERT(T[6] & OM_TIMER_GLOBAL, "a /proc/ timer is flagged global")
	TEST_ASSERT(!(T[OM_TIMER_STRIDE + 6] & OM_TIMER_GLOBAL), "a type-proc timer is not")
	scheduler_advance(1.5)
	TEST_ASSERT(("global" in E.log) && ("typed" in E.log), "both fire through the stored flag")

// ---------------------------------------------------------------- deadlines

// ---------------------------------------------------------------- interactions

/// A headset EXTENDs the radio's interactions instead of discarding its Use (the radio UI).
/datum/unit_test/dq_headset_keeps_radio_use

/datum/unit_test/dq_headset_keeps_radio_use/Run()
	var/obj/item/radio/headset/H = allocate(/obj/item/radio/headset, test_floor())
	// the radio's Use is its "controls" op, in hand (CAPABILITIES(/obj/item/radio)); the headset inherits it
	var/has_use = op_known_anywhere(null, H, null, "controls")
	// the key slot is the headset's own op now (CAPABILITIES(/obj/item/radio/headset), "Insert key")
	var/has_insert = op_known_anywhere(null, H, null, "item")
	TEST_ASSERT(has_use, "a headset keeps the radio's Use")
	TEST_ASSERT(has_insert, "and has its own Insert key")

// ---------------------------------------------------------------- the time engine (code/engine/time/)

/// The due-order heap: many timers on one owner fire in due order (ties in the order they were set), cancelled ones never fire, and the owner's
/// list and soonest cache stay right throughout.
/datum/unit_test/om/time_heap_fires_in_due_order

/datum/unit_test/om/time_heap_fires_in_due_order/run_om(list/made)
	var/datum/om_test_entity/E = entity(made)
	var/list/ids = list()
	var/list/expected = list()
	for(var/i in 1 to 120)
		var/delay = (1 + (i * 37) % 23) * 1 SECONDS // many ties, in no order
		ids["[i]"] = after(E, delay, /datum/om_test_entity/proc/timer_hit, with = list("[i]"))
		expected += list(list(delay, i))
	for(var/i in 3 to 120 step 3)
		TEST_ASSERT(timer_cancel(E, ids["[i]"]), "cancelled timer [i]")
	var/list/kept = list()
	for(var/list/pair in expected)
		if(pair[2] % 3)
			kept += list(pair)
	// (delay, set order) is the firing order
	for(var/a in 1 to length(kept) - 1)
		for(var/b in a + 1 to length(kept))
			var/list/pa = kept[a]
			var/list/pb = kept[b]
			if(pb[1] < pa[1] || (pb[1] == pa[1] && pb[2] < pa[2]))
				kept.Swap(a, b)
	var/datum/om/rec/rec = E.om_rec
	TEST_ASSERT_EQUAL(rec.timer_soonest, timer_local(rec) + kept[1][1], "the soonest follows the heap root once the cancelled ones are gone")
	scheduler_advance(30)
	TEST_ASSERT_EQUAL(length(E.log), length(kept), "every uncancelled timer fired once, no cancelled one did")
	for(var/n in 1 to length(kept))
		TEST_ASSERT_EQUAL(E.log[n], "[kept[n][2]]", "timer [n] fired in due order")
	TEST_ASSERT_NULL(rec.timers, "no timers left")
	TEST_ASSERT_NULL(rec.timer_heap, "and no heap")
	TEST_ASSERT_NULL(rec.timer_soonest, "and no soonest")

/// A heap that outgrew its live timers through cancellations compacts, and a timer set from a firing timer lands in order.
/datum/unit_test/om/time_heap_compacts_and_rearms

/datum/unit_test/om/time_heap_compacts_and_rearms/run_om(list/made)
	var/datum/om_test_entity/E = entity(made)
	for(var/i in 1 to 400)
		var/id = after(E, 50 SECONDS, /datum/om_test_entity/proc/timer_hit, with = list("x"))
		timer_cancel(E, id)
	after(E, 2 SECONDS, /datum/om_test_entity/proc/timer_hit, with = list("one"))
	var/datum/om/rec/rec = E.om_rec
	TEST_ASSERT(length(rec.timer_heap) / OM_TIMER_HEAP_STRIDE <= 2 + OM_TIMER_HEAP_SLACK + 2, "cancelled entries do not pile up in the heap ([length(rec.timer_heap) / OM_TIMER_HEAP_STRIDE])")
	scheduler_advance(3)
	TEST_ASSERT_EQUAL(E.log?.len, 1, "the one live timer fired")
	TEST_ASSERT(!("x" in E.log), "no cancelled timer fired")

/// A world-clock timer without a key names its owner by handle: it fires on a live owner and is dropped, without a runtime, once the owner is deleted.
/datum/unit_test/om/time_world_timer_follows_its_owner

/datum/unit_test/om/time_world_timer_follows_its_owner/run_om(list/made)
	var/datum/om_test_entity/alive = entity(made)
	var/datum/om_test_entity/doomed = entity(made)
	TEST_ASSERT(after(alive, 2 SECONDS, /datum/om_test_entity/proc/timer_hit, clock = CLOCK_WORLD, with = list("alive")), "an unkeyed world timer on a live owner")
	TEST_ASSERT(after(doomed, 2 SECONDS, /datum/om_test_entity/proc/timer_hit, clock = CLOCK_WORLD, with = list("doomed")), "and one on the owner about to be deleted")
	qdel(doomed)
	TEST_ASSERT_EQUAL(after(doomed, 2 SECONDS, /datum/om_test_entity/proc/timer_hit, clock = CLOCK_WORLD, with = list("late")), 0, "a world timer on a deleted owner is refused")
	scheduler_advance(3)
	TEST_ASSERT(("alive" in alive.log), "the live owner's timer fired")
	TEST_ASSERT(!("doomed" in doomed.log) && !("late" in doomed.log), "a deleted owner is never fired on")
