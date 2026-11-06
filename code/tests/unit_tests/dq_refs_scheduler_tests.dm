// The scheduler's references (D1 step 8): a record names its owner by handle, and the queues, rings and cross-entity lists name records and
// entities by handle; a pending op borrows its act and holds no reference to the caller's result.

/// A thing that looks at its own record from its on_destroy(), where the destroy transaction has already marked it deleted.
/datum/refs_sched_dying_probe
	var/seen_owner = FALSE
	var/seen_by_handle_get = FALSE

CAPABILITIES(/datum/refs_sched_dying_probe)

/datum/refs_sched_dying_probe/on_destroy(force)
	var/datum/scheduler_record/rec = sched_rec
	if(rec)
		seen_owner = rec.owner() == src
		seen_by_handle_get = !isnull(handle_get(rec.owner_h))
	..()

/// The record holds its owner's handle (a number) and resolves it; nothing else of the record names the owner.
/datum/unit_test/dq_sched_record_names_owner_by_handle

/datum/unit_test/dq_sched_record_names_owner_by_handle/Run()
	scheduler_test_begin()
	defer_cleanup(null, GLOBAL_PROC_REF(scheduler_test_end))
	var/datum/refs_timer_probe/probe = allocate(/datum/refs_timer_probe)
	var/datum/refs_timer_probe/owner = allocate(/datum/refs_timer_probe)
	after(owner, 5 SECONDS, GLOBAL_PROC_REF(refs_timer_probe_fire), with = list(probe, "x"))
	var/datum/scheduler_record/rec = owner.sched_rec
	TEST_ASSERT_NOTNULL(rec, "the owner has a record")
	TEST_ASSERT(isnum(rec.owner_h), "the record holds a number for its owner")
	TEST_ASSERT_EQUAL(rec.owner_h, entity_handle_of(owner), "which is the owner's handle")
	TEST_ASSERT_EQUAL(rec.owner(), owner, "and resolves to it")
	for(var/name in rec.vars)
		TEST_ASSERT(rec.vars[name] != owner, "[name] of the record holds the owner itself")

/// The owner is still reachable from its record while it is being deleted (hooks and the teardown need it), and not after the teardown.
/datum/unit_test/dq_sched_record_owner_survives_into_teardown

/datum/unit_test/dq_sched_record_owner_survives_into_teardown/Run()
	var/datum/time_scheduler/sched = scheduler_test_begin()
	defer_cleanup(null, GLOBAL_PROC_REF(scheduler_test_end))
	var/datum/refs_timer_probe/probe = allocate(/datum/refs_timer_probe)
	var/datum/refs_sched_dying_probe/owner = new
	after(owner, 5 SECONDS, GLOBAL_PROC_REF(refs_timer_probe_fire), with = list(probe, "never"))
	var/datum/scheduler_record/rec = owner.sched_rec
	TEST_ASSERT_NOTNULL(rec, "the owner has a record")
	qdel(owner)
	TEST_ASSERT(owner.seen_owner, "the record still named its owner in the owner's on_destroy()")
	TEST_ASSERT(!owner.seen_by_handle_get, "where handle_get() already reads the deleted owner as gone")
	TEST_ASSERT(rec.torn_down, "the record was torn down with its owner")
	TEST_ASSERT_NULL(owner.sched_rec, "the owner let go of it")
	TEST_ASSERT_NULL(rec.owner(), "and the record names no owner any more")
	sched.advance(10)
	TEST_ASSERT_EQUAL(probe.fired, 0, "the timer did not fire")

/// Two entities watch through handles: the lists of numbers hold neither entity, and a deleted one is cleared from the other's lists.
/datum/unit_test/dq_sched_cross_entity_lists_hold_handles

/datum/unit_test/dq_sched_cross_entity_lists_hold_handles/Run()
	scheduler_test_begin()
	defer_cleanup(null, GLOBAL_PROC_REF(scheduler_test_end))
	var/datum/refs_timer_probe/watcher = new
	var/datum/refs_timer_probe/target = allocate(/datum/refs_timer_probe)
	var/datum/scheduled_behaviour/B = definition_registry().timer_behaviour
	TEST_ASSERT(entity_watch(watcher, target, CHANGE_RELATED, B), "the watch was made")
	var/datum/scheduler_record/trec = target.sched_rec
	var/datum/scheduler_record/wrec = watcher.sched_rec
	TEST_ASSERT_EQUAL(length(trec.watches_in), 3, "the target lists its watcher")
	TEST_ASSERT(isnum(trec.watches_in[1]), "by a number")
	TEST_ASSERT_EQUAL(trec.watches_in[1], entity_handle_of(watcher), "its handle")
	TEST_ASSERT(isnum(wrec.watching[1]), "the watcher lists what it watches by a number")
	TEST_ASSERT_EQUAL(wrec.watching[1], entity_handle_of(target), "the target's handle")
	qdel(watcher)
	TEST_ASSERT(!length(trec.watches_in), "deleting the watcher took it out of the target's list")
	var/datum/refs_timer_probe/second = new
	TEST_ASSERT(entity_watch(second, target, CHANGE_RELATED, B), "a second watch was made")
	var/datum/scheduler_record/srec = second.sched_rec
	qdel(target)
	TEST_ASSERT_NULL(srec.watching, "deleting the target took it out of the watcher's list")
	qdel(second)

/// The pending op borrows its act, which the op's end gives back, and holds nothing of the caller's result: the result is the act's and is filled in as the op ends.
/datum/unit_test/dq_pending_op_borrows_act_and_not_result

/datum/unit_test/dq_pending_op_borrows_act_and_not_result/Run()
	test_driver_begin()
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	H.enable_godmode()
	var/obj/item/refs_k8_tool/T = allocate(/obj/item/refs_k8_tool, run_loc_floor_bottom_left)
	var/obj/structure/closet/target = allocate(/obj/structure/closet, run_loc_floor_bottom_left)
	var/datum/op_result/started = perform_op(H, target, "k8_probe", T, ORIGIN_AI, AUTH_AI)
	var/datum/pending_op/P = op_pending_of(H)
	TEST_ASSERT_NOTNULL(P, "the op is waiting")
	TEST_ASSERT(!("result" in P.vars), "the pending op has no var for the result")
	TEST_ASSERT_NOTNULL(P.act, "it carries its act")
	TEST_ASSERT_EQUAL(P.act.result, started, "and the act carries the caller's result")
	TEST_ASSERT_NULL(started.outcome, "which is still open")
	test_time(8 SECONDS)
	TEST_ASSERT_EQUAL(T.done, 1, "the op ran")
	TEST_ASSERT_EQUAL(started.outcome, ACT_COMMITTED, "the caller's result was filled in when it ended")
	TEST_ASSERT(QDELETED(P), "the pending op ended")
	TEST_ASSERT_NULL(P.act, "and gave the act back")
