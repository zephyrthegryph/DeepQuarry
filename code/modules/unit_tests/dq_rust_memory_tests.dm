// Phase 4b guard (doc/rewrite/init_and_turfs.md §0.1-0.2): the Rust heap peak
// once reached 1.85 GB during a Southern Cross boot, and in the 32-bit
// DreamDaemon that left too little address space for a large explosion (15 of
// 21 explosion boots died on a failed Rust allocation). Bulk writes into the
// live stores and chunk-sized command batches brought it to ~230 MB. The peak
// is process-wide and monotonic, so this checks boot plus every test that ran
// before it; the ceiling leaves headroom for that and still fails long before
// a regression reaches the old failure range.

/// Rust heap peak ceiling for a booted test world, in MB.
#define DQ_RUST_HEAP_PEAK_CEILING_MB 512

/datum/unit_test/dq_rust_heap_peak_bounded

/datum/unit_test/dq_rust_heap_peak_bounded/Run()
	var/list/heap = vg_verdigris_allocator_diagnostics()
	TEST_ASSERT(islist(heap) && length(heap) >= 2, "verdigris_allocator_diagnostics returned no (current, peak) pair")
	var/current_mb = heap[1] / 1048576
	var/peak_mb = heap[2] / 1048576
	TEST_ASSERT(peak_mb > 0, "the Rust tracking allocator reports a zero peak; the guard would pass vacuously")
	TEST_ASSERT(peak_mb >= current_mb, "the Rust heap peak ([peak_mb] MB) is below the live heap ([current_mb] MB)")
	TEST_ASSERT(peak_mb <= DQ_RUST_HEAP_PEAK_CEILING_MB, "Rust heap peak is [round(peak_mb, 0.1)] MB, above the [DQ_RUST_HEAP_PEAK_CEILING_MB] MB ceiling (live [round(current_mb, 0.1)] MB). A boot-time store or command batch is holding a whole-grid copy again; see doc/rewrite/init_and_turfs.md §0.2.")

#undef DQ_RUST_HEAP_PEAK_CEILING_MB
