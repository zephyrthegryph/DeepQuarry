// The init frame batches stat settles (code/engine/stats/recompute.dm, stat_settle_defer): a contribution to a virtual stat (an area's demand) made
// while a materialize frame runs places its row at once and queues the recompute. The target's queue is settled once when the frame closes, or earlier
// when anything reads a stat of the target, so a reader never sees a value a queued contribution has not reached.

/datum/unit_test/dq_stat_settle_batch
	abstract_type = /datum/unit_test/dq_stat_settle_batch

/// The demand stat's value as the stat layer cached it, without the read that would settle a queue first.
/datum/unit_test/dq_stat_settle_batch/proc/cached_demand(area/A)
	return A.rx?.stats?.virtual?["[STAT_DEMAND_EQUIP]"]

/// A contribution inside the frame is queued; a read of the stat inside the frame settles it and sees every contribution so far.
/datum/unit_test/dq_stat_settle_batch/read_inside_frame_sees_the_value

/datum/unit_test/dq_stat_settle_batch/read_inside_frame_sees_the_value/Run()
	var/area/target = new /area()
	var/datum/stat_def/def = stat_def_of(STAT_DEMAND_EQUIP)
	var/obj/item/first = allocate(/obj/item/dq_rule_test)
	var/obj/item/second = allocate(/obj/item/dq_rule_test)
	var/queued_before = GLOB.stat_deferred
	var/datum/materialize_batch/frame = SSatoms.batch_open("dq_stat_settle_batch_test")
	stat_row_set(target, def, first, 300, PRIORITY_DEFAULT, null)
	stat_row_set(target, def, second, 120, PRIORITY_DEFAULT, null)
	var/queued = GLOB.stat_deferred - queued_before
	var/waiting = !isnull(target.rx.stats.pending)
	var/frame_queued = frame.stat_settles_queued
	var/frame_targets = frame.stat_settle_targets
	var/seen = stat_value(target, STAT_DEMAND_EQUIP)
	var/waiting_after = !isnull(target.rx.stats.pending)
	stat_row_set(target, def, first, 500, PRIORITY_DEFAULT, null)
	var/seen_again = stat_value(target, STAT_DEMAND_EQUIP)
	SSatoms.batch_close(frame)
	TEST_ASSERT_EQUAL(queued, 2, "both settles were queued, not run")
	TEST_ASSERT(waiting, "the target had a settle waiting")
	TEST_ASSERT_EQUAL(frame_queued, 2, "the frame counted its queued settles")
	TEST_ASSERT_EQUAL(frame_targets, 1, "for one target")
	TEST_ASSERT_EQUAL(seen, 420, "a read inside the frame sees both contributions")
	TEST_ASSERT(!waiting_after, "the read settled the queue")
	TEST_ASSERT_EQUAL(seen_again, 620, "a later contribution is seen by the next read")
	TEST_ASSERT_EQUAL(stat_value(target, STAT_DEMAND_EQUIP), 620, "closing the frame changes nothing the reads saw")

/// Many contributions to one target settle it once, when the frame closes.
/datum/unit_test/dq_stat_settle_batch/close_settles_once_per_target

/datum/unit_test/dq_stat_settle_batch/close_settles_once_per_target/Run()
	var/area/target = new /area()
	var/datum/stat_def/def = stat_def_of(STAT_DEMAND_EQUIP)
	var/queued_before = GLOB.stat_deferred
	var/settles_before = GLOB.stat_deferred_settles
	var/datum/materialize_batch/frame = SSatoms.batch_open("dq_stat_settle_batch_test")
	for(var/i in 1 to 6)
		stat_row_set(target, def, allocate(/obj/item/dq_rule_test), i * 10, PRIORITY_DEFAULT, null)
	var/evals_before = GLOB.stat_evals
	var/cached_inside = cached_demand(target)
	SSatoms.batch_close(frame)
	TEST_ASSERT_EQUAL(GLOB.stat_deferred - queued_before, 6, "six settles were queued")
	TEST_ASSERT_EQUAL(GLOB.stat_deferred_settles - settles_before, 1, "the close ran one settle for the target")
	TEST_ASSERT_EQUAL(GLOB.stat_evals - evals_before, 1, "and one recompute")
	TEST_ASSERT(isnull(cached_inside) || cached_inside != 210, "inside the frame the cached value had not moved")
	TEST_ASSERT_EQUAL(cached_demand(target), 210, "the close settled the stat to the total")
	TEST_ASSERT_NULL(target.rx.stats.pending, "nothing is left queued")
	TEST_ASSERT_EQUAL(length(GLOB.stat_pending_slots), 0, "no target is left listed")

/// A contribution taken away inside the frame (contributes_to release) leaves the total the remaining ones make.
/datum/unit_test/dq_stat_settle_batch/removal_inside_frame

/datum/unit_test/dq_stat_settle_batch/removal_inside_frame/Run()
	var/area/target = new /area()
	var/datum/stat_def/def = stat_def_of(STAT_DEMAND_EQUIP)
	var/datum/stat_contrib/ct
	var/obj/machinery/door/airlock/sample = allocate(/obj/machinery/door/airlock)
	for(var/datum/stat_contrib/candidate as anything in stat_type_of(sample)?.ct_entries)
		if(candidate.stat_id == STAT_DEMAND_EQUIP)
			ct = candidate
			break
	TEST_ASSERT_NOTNULL(ct, "machinery declares a contribution to the equipment demand")
	var/obj/item/stays = allocate(/obj/item/dq_rule_test)
	var/obj/item/leaves = allocate(/obj/item/dq_rule_test)
	var/datum/materialize_batch/frame = SSatoms.batch_open("dq_stat_settle_batch_test")
	stat_row_set(target, def, stays, 200, PRIORITY_DEFAULT, ct.row_key)
	stat_row_set(target, def, leaves, 75, PRIORITY_DEFAULT, ct.row_key)
	stat_ct_release(target, leaves, ct)
	var/seen = stat_value(target, STAT_DEMAND_EQUIP)
	stat_ct_release(target, stays, ct)
	SSatoms.batch_close(frame)
	TEST_ASSERT_EQUAL(seen, 200, "the read after the release sees only the contribution that stayed")
	TEST_ASSERT_EQUAL(stat_value(target, STAT_DEMAND_EQUIP), 0, "with both gone the demand is back to nothing")

/// A target deleted inside the frame is dropped when the frame closes; nothing runs on it and nothing stays queued.
/datum/unit_test/dq_stat_settle_batch/target_deleted_inside_frame

/datum/unit_test/dq_stat_settle_batch/target_deleted_inside_frame/Run()
	var/area/target = new /area()
	var/datum/stat_def/def = stat_def_of(STAT_DEMAND_EQUIP)
	var/datum/materialize_batch/frame = SSatoms.batch_open("dq_stat_settle_batch_test")
	stat_row_set(target, def, allocate(/obj/item/dq_rule_test), 90, PRIORITY_DEFAULT, null)
	qdel(target)
	SSatoms.batch_close(frame)
	TEST_ASSERT_EQUAL(length(GLOB.stat_pending_slots), 0, "no target is left listed")

/// Outside a frame nothing waits: the settle is immediate, as before.
/datum/unit_test/dq_stat_settle_batch/outside_frame_is_immediate

/datum/unit_test/dq_stat_settle_batch/outside_frame_is_immediate/Run()
	var/area/target = new /area()
	var/datum/stat_def/def = stat_def_of(STAT_DEMAND_EQUIP)
	var/queued_before = GLOB.stat_deferred
	stat_row_set(target, def, allocate(/obj/item/dq_rule_test), 40, PRIORITY_DEFAULT, null)
	TEST_ASSERT_EQUAL(GLOB.stat_deferred - queued_before, 0, "nothing was queued")
	TEST_ASSERT_EQUAL(cached_demand(target), 40, "the cached value moved at once")

/// A frame that yields settles the queue, so what runs meanwhile reads settled stats.
/datum/unit_test/dq_stat_settle_batch/yield_settles_the_queue

/datum/unit_test/dq_stat_settle_batch/yield_settles_the_queue/Run()
	var/area/target = new /area()
	var/datum/stat_def/def = stat_def_of(STAT_DEMAND_EQUIP)
	var/datum/materialize_batch/frame = SSatoms.batch_open("dq_stat_settle_batch_test")
	stat_row_set(target, def, allocate(/obj/item/dq_rule_test), 55, PRIORITY_DEFAULT, null)
	SSatoms.batch_suspend(frame)
	var/settled = cached_demand(target)
	SSatoms.batch_close(frame)
	TEST_ASSERT_EQUAL(settled, 55, "the suspended frame left the stat settled")
