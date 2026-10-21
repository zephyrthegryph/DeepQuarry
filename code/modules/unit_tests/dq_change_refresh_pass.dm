// The OUTPUT queue's per-pass stamp (doc/rewrite/proposals/change_graph.md section 11 step 4): an entity marked any number of times runs its
// outputs once in a refresh_drain() pass, and the pass number it carries is the drain's.

/datum/unit_test/dq_change_refresh_pass

/datum/unit_test/dq_change_refresh_pass/Run()
	var/turf/T = test_floor()
	refresh_flush()
	var/obj/dq_stamp_plain/A = new(T)
	var/obj/dq_stamp_plain/B = new(T)
	refresh_flush()
	var/before = GLOB.refresh_bench_drained
	refresh_mark(A, DEP_ALL)
	refresh_mark(A, DEP_ALL)
	refresh_mark(B, DEP_ALL)
	refresh_mark(A, DEP_ALL)
	var/pass_before = GLOB.refresh_drain_pass
	refresh_drain(null)
	TEST_ASSERT_EQUAL(GLOB.refresh_drain_pass, pass_before + 1, "a drain takes one pass number")
	TEST_ASSERT_EQUAL(GLOB.refresh_bench_drained - before, 2, "three marks of A and one of B run two entities once each")
	TEST_ASSERT_EQUAL(A.refresh_pass, GLOB.refresh_drain_pass, "A carries the pass that ran it")
	TEST_ASSERT_EQUAL(B.refresh_pass, GLOB.refresh_drain_pass, "B carries it too")
	TEST_ASSERT(!A.refresh_queued && !B.refresh_queued, "nothing is left queued")
	// A mark after the drain runs in the next pass, not never.
	refresh_mark(A, DEP_ALL)
	var/second = GLOB.refresh_bench_drained
	refresh_drain(null)
	TEST_ASSERT_EQUAL(GLOB.refresh_bench_drained - second, 1, "a later mark runs in the next pass")
	TEST_ASSERT_EQUAL(A.refresh_pass, GLOB.refresh_drain_pass, "with the next pass number")
