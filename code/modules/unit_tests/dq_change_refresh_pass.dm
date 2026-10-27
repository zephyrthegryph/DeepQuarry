// The OUTPUT queue's per-pass stamp (doc/rewrite/proposals/change_graph.md section 11 step 4): an entity marked any number of times runs its
// outputs once in a refresh_drain() pass, and the pass number it carries is the drain's.

/datum/unit_test/dq_change_refresh_pass

/datum/unit_test/dq_change_refresh_pass/Run()
	refresh_flush()
	var/obj/cap_fixture/dx_core/A = allocate(/obj/cap_fixture/dx_core) // a type that derives something, so its refresh is wanted
	var/obj/cap_fixture/dx_core/B = allocate(/obj/cap_fixture/dx_core)
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

/// A write on a mapped atom that waits for its init publishes nothing (state_changed()'s map-load gate): the init queues its first full
/// refresh itself. Once initialized, the same write queues a refresh again.
/datum/unit_test/dq_change_preinit_write_publishes_nothing

/datum/unit_test/dq_change_preinit_write_publishes_nothing/Run()
	refresh_flush()
	var/source = "[type]"
	var/skipped = GLOB.state_changed_preinit_skipped
	SSatoms.map_loader_begin(source)
	var/obj/cap_fixture/dx_core/A
	try
		A = new(run_loc_floor_bottom_left)
		TEST_ASSERT(!(A.flags & ATOM_INITIALIZED), "an atom made during a map load waits for its init")
		state_changed(A)
		TEST_ASSERT(!(A.refresh_queued & ~DEP_CREATED), "a write before its init queues no refresh")
		TEST_ASSERT_EQUAL(GLOB.state_changed_preinit_skipped, skipped + 1, "the gate answered it")
	catch(var/exception/e)
		SSatoms.map_loader_stop(source)
		throw e
	SSatoms.map_loader_stop(source)
	SSatoms.InitializeAtoms(list(A))
	TEST_ASSERT(A.flags & ATOM_INITIALIZED, "the atom initializes after the load")
	refresh_flush()
	state_changed(A)
	TEST_ASSERT(A.refresh_queued, "an initialized atom's write queues its refresh")
	refresh_flush()
	qdel(A)
