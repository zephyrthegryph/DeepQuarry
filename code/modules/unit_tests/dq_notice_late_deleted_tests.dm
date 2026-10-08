// The late notice queue and deleted things (doc/rewrite/framework_gaps.md D3). A notice published past the depth cap waits for the next drain point; its
// row names the holder by handle and the notice has no target while it waits, so nothing in the queue keeps a datum alive.
//  - a receiver deleted before the drain gets nothing, and the row is gone;
//  - a holder deleted while its notice waits still has the notice delivered to every other receiver, with the holder in its deleting state;
//  - mob_death-style notices (an observer of a dying mob) still reach the observer.

/// An observer of a late-published notice: counts what it hears and what state the target was in.
/obj/d3_watcher
	name = "d3 watcher"
	anchored = TRUE
	var/heard = 0
	var/target_was_deleting = FALSE
	var/target_type

/obj/d3_watcher/proc/heard_it(datum/act/notice/A)
	heard++
	var/datum/subject = A.target
	target_was_deleting = !!subject && QDELETED(subject)
	target_type = subject?.type

/// A notice holder with its own hook, so a test can tell the holder's hooks from its observers'.
/obj/d3_subject
	name = "d3 subject"
	anchored = TRUE
	var/own_heard = 0

CAPABILITIES(/obj/d3_subject)
	on_notice(/datum/notice/lanea_boomed, then(PROC_REF(own_hear)))

/obj/d3_subject/proc/own_hear(datum/act/notice/A)
	own_heard++

/datum/unit_test/dq_lane_a/late_notice_receiver_deleted_gets_nothing_and_the_row_goes

/datum/unit_test/dq_lane_a/late_notice_receiver_deleted_gets_nothing_and_the_row_goes/run_lane_a()
	var/obj/d3_subject/S = allocate(/obj/d3_subject)
	var/obj/d3_watcher/gone = allocate(/obj/d3_watcher)
	var/obj/d3_watcher/kept = allocate(/obj/d3_watcher)
	observe(S, /datum/notice/lanea_boomed, gone, then(TYPE_PROC_REF(/obj/d3_watcher, heard_it)))
	observe(S, /datum/notice/lanea_boomed, kept, then(TYPE_PROC_REF(/obj/d3_watcher, heard_it)))
	GLOB.act_depth = ACT_MAX_DEPTH
	notice_publish(S, notice_take(/datum/notice/lanea_boomed))
	GLOB.act_depth = 0
	TEST_ASSERT_EQUAL(length(GLOB.notice_late_queue), 1, "the notice waits for the drain")
	var/list/row = GLOB.notice_late_queue[1]
	TEST_ASSERT(istext(row[1]), "the row names its holder by handle, not by reference")
	var/datum/notice/queued = row[2]
	TEST_ASSERT_NULL(queued.target, "and the queued notice has no target: it keeps nothing alive")
	qdel(gone)
	test_drain()
	TEST_ASSERT_EQUAL(gone.heard, 0, "a receiver deleted before the drain gets nothing")
	TEST_ASSERT_EQUAL(kept.heard, 1, "the other receiver hears it")
	TEST_ASSERT_EQUAL(S.own_heard, 1, "and so does the holder's own hook")
	TEST_ASSERT_EQUAL(length(GLOB.notice_late_queue), 0, "the row is gone")

/datum/unit_test/dq_lane_a/late_notice_for_a_deleted_holder_drops_with_the_row

/datum/unit_test/dq_lane_a/late_notice_for_a_deleted_holder_drops_with_the_row/run_lane_a()
	// A row whose holder is already gone with no transaction to flush it (collected, or put there by hand) is dropped at the drain.
	var/obj/d3_subject/S = allocate(/obj/d3_subject)
	var/obj/d3_watcher/W = allocate(/obj/d3_watcher)
	observe(S, /datum/notice/lanea_boomed, W, then(TYPE_PROC_REF(/obj/d3_watcher, heard_it)))
	var/datum/notice/lanea_boomed/N = notice_take(/datum/notice/lanea_boomed)
	GLOB.notice_late_queue += list(list("0:0", N, ACT_COMMITTED, "stale handle"))
	test_drain()
	TEST_ASSERT_EQUAL(W.heard, 0, "a notice whose holder no longer exists reaches nobody")
	TEST_ASSERT_EQUAL(length(GLOB.notice_late_queue), 0, "and its row is gone")

/datum/unit_test/dq_lane_a/late_notice_for_a_holder_deleted_while_queued_reaches_the_others

/datum/unit_test/dq_lane_a/late_notice_for_a_holder_deleted_while_queued_reaches_the_others/run_lane_a()
	var/obj/d3_subject/S = allocate(/obj/d3_subject)
	var/obj/d3_watcher/W = allocate(/obj/d3_watcher)
	var/obj/d3_watcher/W2 = allocate(/obj/d3_watcher)
	observe(S, /datum/notice/lanea_boomed, W, then(TYPE_PROC_REF(/obj/d3_watcher, heard_it)))
	observe(S, /datum/notice/lanea_boomed, W2, then(TYPE_PROC_REF(/obj/d3_watcher, heard_it)))
	GLOB.act_depth = ACT_MAX_DEPTH
	notice_publish(S, notice_take(/datum/notice/lanea_boomed))
	GLOB.act_depth = 0
	TEST_ASSERT_EQUAL(length(GLOB.notice_late_queue), 1, "the notice waits for the drain")
	qdel(S)
	TEST_ASSERT(QDELETED(S), "the holder is deleted")
	TEST_ASSERT_EQUAL(W.heard, 1, "an observer still hears a notice queued for a holder that was deleted")
	TEST_ASSERT_EQUAL(W2.heard, 1, "and every other observer")
	TEST_ASSERT(W.target_was_deleting, "with the holder in its deleting state")
	TEST_ASSERT_EQUAL(W.target_type, /obj/d3_subject, "still whole")
	TEST_ASSERT_EQUAL(S.own_heard, 0, "the dying holder's own hooks do not run")
	TEST_ASSERT_EQUAL(length(GLOB.notice_late_queue), 0, "the row is gone: the queue holds nothing of it")
	test_drain()
	TEST_ASSERT_EQUAL(W.heard, 1, "and the drain delivers nothing twice")

/datum/unit_test/dq_lane_a/late_notice_queue_holds_no_reference_to_its_holder

/datum/unit_test/dq_lane_a/late_notice_queue_holds_no_reference_to_its_holder/run_lane_a()
	var/obj/d3_subject/S = allocate(/obj/d3_subject)
	GLOB.act_depth = ACT_MAX_DEPTH
	notice_publish(S, notice_take(/datum/notice/lanea_boomed))
	GLOB.act_depth = 0
	var/list/row = GLOB.notice_late_queue[1]
	for(var/item in row)
		TEST_ASSERT(item != S, "no element of a queued row is the holder")
	var/datum/notice/queued = row[2]
	TEST_ASSERT(queued.target != S, "nor is the notice's target")
	qdel(S)
	for(var/list/each in GLOB.notice_late_queue)
		TEST_ASSERT(each[1] != S, "a deleted holder leaves no row behind")
	TEST_ASSERT_EQUAL(length(GLOB.notice_late_queue), 0, "the queue is empty: no reference outlived the delete")

/// A mob_death-style notice: a mob published it past the cap, then died; its observer still hears it.
/datum/unit_test/dq_lane_a/late_mob_death_style_notice_still_reaches_observers

/datum/unit_test/dq_lane_a/late_mob_death_style_notice_still_reaches_observers/run_lane_a()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/obj/d3_watcher/W = allocate(/obj/d3_watcher)
	observe(H, /datum/notice/lanea_boomed, W, then(TYPE_PROC_REF(/obj/d3_watcher, heard_it)))
	GLOB.act_depth = ACT_MAX_DEPTH
	notice_publish(H, notice_take(/datum/notice/lanea_boomed))
	GLOB.act_depth = 0
	TEST_ASSERT_EQUAL(W.heard, 0, "queued, not yet delivered")
	test_drain()
	TEST_ASSERT_EQUAL(W.heard, 1, "a live mob's late notice reaches its observer at the drain")
	GLOB.act_depth = ACT_MAX_DEPTH
	notice_publish(H, notice_take(/datum/notice/lanea_boomed))
	GLOB.act_depth = 0
	qdel(H)
	TEST_ASSERT_EQUAL(W.heard, 2, "a mob deleted while its notice waits still reaches its observer")
	TEST_ASSERT(W.target_was_deleting, "with the mob in its deleting state")
	TEST_ASSERT_EQUAL(length(GLOB.notice_late_queue), 0, "and the queue is empty")
