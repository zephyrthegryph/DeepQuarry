// The timers of the references lane (D1 step 7): the wheel names a record by handle, keyed timers live in the owner's record, and a borrower hears that its target was deleted (borrow_ended, K8).

/// Entries on the test scheduler's deadline wheel that name `rec_handle`.
/proc/refs_wheel_entries(datum/time_scheduler/sched, rec_handle)
	. = 0
	for(var/list/L as anything in sched.buckets)
		for(var/i in 1 to length(L) step 4)
			if(L[i] == rec_handle)
				.++

/// The wheel holds a handle (a number), not the record, and the timer fires through it.
/datum/unit_test/dq_timer_fires_on_handle

/datum/unit_test/dq_timer_fires_on_handle/Run()
	var/datum/time_scheduler/sched = scheduler_test_begin()
	defer_cleanup(null, GLOBAL_PROC_REF(scheduler_test_end))
	var/datum/refs_timer_probe/probe = allocate(/datum/refs_timer_probe)
	var/datum/refs_timer_probe/owner = allocate(/datum/refs_timer_probe)
	after(owner, 5 SECONDS, GLOBAL_PROC_REF(refs_timer_probe_fire), with = list(probe, "on_time"))
	var/datum/scheduler_record/rec = owner.sched_rec
	TEST_ASSERT_NOTNULL(rec, "the owner has a record")
	var/rec_handle = handle_of(rec)
	TEST_ASSERT(isnum(rec_handle), "the record is named by a handle")
	TEST_ASSERT_EQUAL(refs_wheel_entries(sched, rec_handle), 1, "and its one wheel entry is that handle, not the record itself")
	for(var/list/L as anything in sched.buckets)
		for(var/i in 1 to length(L) step 4)
			TEST_ASSERT(!isdatum(L[i]), "no wheel entry holds a datum")
	TEST_ASSERT(isnull(rec.att) && isnull(rec.att_pend) && isnull(rec.att_ring) && isnull(rec.att_state), "a record that only holds a timer allocates none of the attachment lists")
	sched.advance(4)
	TEST_ASSERT_EQUAL(probe.fired, 0, "nothing before it is due")
	sched.advance(2)
	TEST_ASSERT_EQUAL(probe.fired, 1, "the timer fires once it is due")
	TEST_ASSERT_EQUAL(probe.last_arg, "on_time", "with its arguments")

/// Deleting the owner cancels its timers, frees its record's slot and leaves the wheel entry naming nothing.
/datum/unit_test/dq_timer_cancelled_on_qdel

/datum/unit_test/dq_timer_cancelled_on_qdel/Run()
	var/datum/time_scheduler/sched = scheduler_test_begin()
	defer_cleanup(null, GLOBAL_PROC_REF(scheduler_test_end))
	var/datum/refs_timer_probe/probe = allocate(/datum/refs_timer_probe)
	var/datum/refs_timer_probe/owner = new
	after(owner, 5 SECONDS, GLOBAL_PROC_REF(refs_timer_probe_fire), with = list(probe, "never"))
	after(owner, 6 SECONDS, GLOBAL_PROC_REF(refs_timer_probe_fire), key = "keyed", with = list(probe, "never keyed"))
	var/datum/scheduler_record/rec = owner.sched_rec
	var/rec_handle = handle_of(rec)
	var/leaks_before = slot_leak_report(log = FALSE)["/datum/scheduler_record"] || 0
	TEST_ASSERT_EQUAL(sched.timer_count(owner), 2, "two timers are pending")
	qdel(owner)
	TEST_ASSERT(rec.torn_down, "the record was torn down with its owner")
	TEST_ASSERT(isnull(rec.timers) && isnull(rec.timer_keys), "its timers and keys went")
	TEST_ASSERT_NULL(handle_get(rec_handle), "the wheel's handle names nothing now, so the entries hold no record")
	TEST_ASSERT_EQUAL(rec.handle_slot, 0, "and the record's slot was released")
	sched.advance(10)
	TEST_ASSERT_EQUAL(probe.fired, 0, "neither timer fired")
	TEST_ASSERT_EQUAL(slot_leak_report(log = FALSE)["/datum/scheduler_record"] || 0, leaks_before, "no record slot leaked")

/// A keyed timer is a field of the owner's record: no reaction state, no ledger row; a replaced key keeps one timer.
/datum/unit_test/dq_keyed_timer_is_a_record_field

/datum/unit_test/dq_keyed_timer_is_a_record_field/Run()
	var/datum/time_scheduler/sched = scheduler_test_begin()
	defer_cleanup(null, GLOBAL_PROC_REF(scheduler_test_end))
	var/datum/refs_timer_probe/probe = allocate(/datum/refs_timer_probe)
	var/datum/refs_timer_probe/owner = allocate(/datum/refs_timer_probe)
	TEST_ASSERT(!after_pending(owner, "k"), "nothing pending")
	after(owner, 5 SECONDS, GLOBAL_PROC_REF(refs_timer_probe_fire), key = "k", with = list(probe, "first"))
	after(owner, 8 SECONDS, GLOBAL_PROC_REF(refs_timer_probe_fire), key = "k", with = list(probe, "second"))
	TEST_ASSERT(after_pending(owner, "k"), "pending")
	TEST_ASSERT_EQUAL(length(owner.sched_rec.timer_keys), 1, "the key is in the owner's record")
	TEST_ASSERT_EQUAL(sched.timer_count(owner), 1, "the same key replaced the first timer")
	TEST_ASSERT_NULL(owner.rx, "no reaction state was made for it")
	TEST_ASSERT(after_left(owner, "k") > 0, "after_left() reads it")
	sched.advance(6)
	TEST_ASSERT_EQUAL(probe.fired, 0, "the replaced timer never fires")
	sched.advance(3)
	TEST_ASSERT_EQUAL(probe.fired, 1, "the replacement fires")
	TEST_ASSERT_EQUAL(probe.last_arg, "second", "with its own arguments")
	TEST_ASSERT(!after_pending(owner, "k"), "and the key is clear")
	TEST_ASSERT_NULL(owner.sched_rec.timer_keys, "the table went with its last key")

/// K8: a waiting op hears that its target was deleted, runs its on_interrupt() with no target and the reason, and ends.
/datum/unit_test/dq_borrow_ended_runs_on_interrupt

/datum/unit_test/dq_borrow_ended_runs_on_interrupt/Run()
	test_driver_begin()
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	H.enable_godmode()
	var/obj/item/refs_k8_tool/T = allocate(/obj/item/refs_k8_tool, run_loc_floor_bottom_left)
	var/obj/structure/closet/target = new(run_loc_floor_bottom_left)
	perform_op(H, target, "k8_probe", T, ORIGIN_AI, AUTH_AI)
	var/datum/pending_op/P = op_pending_of(H)
	TEST_ASSERT_NOTNULL(P, "the op is waiting on its target")
	TEST_ASSERT_EQUAL(T.broke, 0, "and has not been interrupted")
	qdel(target)
	TEST_ASSERT_EQUAL(T.broke, 1, "deleting the target ran on_interrupt() once")
	TEST_ASSERT(T.broke_target_was_null, "with no target")
	TEST_ASSERT_NOTNULL(T.broke_reason, "and the reason")
	test_time(8 SECONDS)
	TEST_ASSERT_EQUAL(T.done, 0, "the op never ran")
	TEST_ASSERT_EQUAL(T.broke, 1, "and was interrupted once, not again when its record went")
	TEST_ASSERT_NULL(op_pending_of(H), "nothing is pending")
	var/obj/structure/closet/second = new(run_loc_floor_bottom_left)
	perform_op(H, second, "k8_probe", T, ORIGIN_AI, AUTH_AI)
	test_time(8 SECONDS)
	TEST_ASSERT_EQUAL(T.done, 1, "a wait that completes runs the op")
	TEST_ASSERT_EQUAL(T.broke, 1, "and does not call the interrupt back")
	qdel(second)
