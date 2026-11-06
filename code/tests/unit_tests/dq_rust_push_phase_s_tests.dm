// Phase S delivers the Rust pushes marked since the last frame (refresh_drain_pushes(), code/engine/change/refresh.dm), so the native step of
// the same tick reads them. Before it, a push waited for the presentation lane's drain, which runs after N and under a budget: a freshly bound
// APC stepped on the component's schema defaults (no capacity, no cell) unless connect_to_network() pushed by hand.

/// A finished APC as the map places it, rebound as a fresh component would be: Rust holds the schema defaults until the push.
/datum/unit_test/dq_p2_apc/proc/dq_push_test_apc()
	var/obj/machinery/power/apc/A = p2_apc()
	native_write(A, NATIVE_APC_CAPACITY, 0)
	native_write(A, NATIVE_APC_HAS_CELL, 0)
	return A

/// connect_to_network() marks the push (native_resync()); phase S's drain delivers it, with no presentation drain and no hand-written push.
/datum/unit_test/dq_p2_apc/rust_push_fresh_apc_reaches_rust_at_phase_s/run_gate()
	var/obj/machinery/power/apc/A = dq_push_test_apc()
	TEST_ASSERT(A.vg_entity, "the APC is bound to a Rust entity")
	TEST_ASSERT_NOTNULL(A.cell, "the map APC has a cell")
	if(!A.vg_entity || !A.cell)
		return
	A.connect_to_network()
	TEST_ASSERT(A in GLOB.refresh_push_queue, "the bind queued the APC's push for phase S")
	TEST_ASSERT_EQUAL(native_read(A, NATIVE_APC_CAPACITY), 0, "nothing pushed yet: Rust still holds the default capacity")
	var/drained = GLOB.refresh_pushes_drained
	refresh_drain_pushes() // what the kernel runs in phase S, before the native step
	TEST_ASSERT(GLOB.refresh_pushes_drained > drained, "phase S ran the push")
	TEST_ASSERT_EQUAL(native_read(A, NATIVE_APC_CAPACITY), A.cell.maxcharge, "Rust holds the cell's capacity before the first native step")
	TEST_ASSERT_EQUAL(native_read(A, NATIVE_APC_HAS_CELL), 1, "Rust knows the APC has a cell")
	TEST_ASSERT(!(A in GLOB.refresh_push_queue), "the push queue is empty after the drain")

/// A tracked write the push reads reaches Rust at the next phase S too, not only a bind.
/datum/unit_test/dq_p2_apc/rust_push_tracked_write_reaches_rust_at_phase_s/run_gate()
	var/obj/machinery/power/apc/A = dq_push_test_apc()
	if(!A.vg_entity)
		Fail("the APC is not bound to a Rust entity")
		return
	refresh_drain_pushes()
	var/before = A.chargemode
	A.set_chargemode(!before)
	refresh_drain_pushes()
	TEST_ASSERT_EQUAL(native_read(A, NATIVE_APC_CHARGEMODE), (!before) ? 1 : 0, "the new charge mode reached Rust at phase S")
	A.set_chargemode(before)
