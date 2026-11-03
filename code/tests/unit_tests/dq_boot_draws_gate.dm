/// The map's deferred first draws gate entry: while the refresh queue still holds them, the round does not start (and observing and an
/// admin ghost from the lobby are refused through the same check), and the gate opens for good once the queue is empty.
/datum/unit_test/dq_boot_draws_gate_blocks_round_start/Run()
	var/list/saved_queue = GLOB.refresh_queue
	var/saved_flag = GLOB.boot_draws_outstanding
	var/datum/pending = new
	GLOB.refresh_queue = list(pending)
	GLOB.boot_draws_outstanding = TRUE
	TEST_ASSERT(boot_draws_pending(), "first draws are still queued, so they are pending")
	TEST_ASSERT(SSticker.round_start_blocked(), "the round may not start while the map's first draws are still queued")
	GLOB.refresh_queue = list()
	TEST_ASSERT(!boot_draws_pending(), "an empty queue opens the map")
	TEST_ASSERT(isnull(SSticker.round_start_blocked()), "with the draws done the round may start")
	GLOB.refresh_queue = list(pending)
	TEST_ASSERT(!boot_draws_pending(), "once open the gate stays open (later draws are ordinary refreshes)")
	GLOB.refresh_queue = saved_queue
	GLOB.boot_draws_outstanding = saved_flag
	SSticker.draws_wait_announced = FALSE
	qdel(pending)
