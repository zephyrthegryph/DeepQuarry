// What one step of a player costs, and that input and the shadows around the player never wait behind work that can wait
// (the MOVE_COST trace, code/domains/world_model/atom/move_cost.dm; the ring prefetch, code/engine/change/interest.dm; the near light queue,
// code/world/systems/lighting.dm). Uses the helpers of dq_chunk_interest.dm.

/// A walker's step across a chunk edge scans no ring chunk: the ring only lists them, and the drain scans them over its passes, nearest first
/// (a step that scanned four ring chunks of ~300 owed draws cost 35-50 ms on the test server, at every edge a player ran over).
/datum/unit_test/dq_move_step_scans_no_ring_chunk

/datum/unit_test/dq_move_step_scans_no_ring_chunk/Run()
	interest_isolate()
	set_global(nameof(GLOB.interest_ring_listed), GLOB.interest_ring_listed)
	set_global(nameof(GLOB.interest_ring_scans_stale), GLOB.interest_ring_scans_stale)
	var/turf/base = test_floor()
	var/start_x = round((base.x - 1) / INTEREST_CHUNK) * INTEREST_CHUNK + 1
	var/turf/home = locate(start_x, base.y, base.z)
	var/turf/stepped = locate(start_x + 9, base.y, base.z)
	var/turf/ring_spot = locate(start_x + 2 * INTEREST_CHUNK + 4, base.y, base.z) // two chunks east: in the ring of the step, not in the ring of home
	TEST_ASSERT(home && stepped && ring_spot, "the map has room for three chunks")
	var/list/probes = interest_probes(ring_spot, 60)
	set_global(nameof(GLOB.interest_defer_marks), TRUE)
	for(var/obj/dq_interest_probe/probe as anything in probes)
		refresh_mark(probe, DEP_ALL)
	GLOB.interest_test_coverable += "dq-test-walker"
	interest_view_set("dq-test-walker", home, null, world.view)
	GLOB.interest_covered -= "dq-test-walker"
	GLOB.interest_scan_pending -= "dq-test-walker"
	GLOB.interest_ring_scans = list()
	GLOB.interest_prefetched = list()
	var/scanned_before = GLOB.interest_chunks_entered
	var/listed_before = GLOB.interest_ring_listed
	interest_view_set("dq-test-walker", stepped, null, world.view)
	TEST_ASSERT(GLOB.interest_ring_listed > listed_before, "the step entered ring chunks ([GLOB.interest_ring_listed - listed_before])")
	TEST_ASSERT(GLOB.interest_chunks_entered - scanned_before <= 2, "and scanned at most the chunk that became visible, no ring chunk ([GLOB.interest_chunks_entered - scanned_before])")
	TEST_ASSERT(length(GLOB.interest_ring_scans) >= GLOB.interest_ring_listed - listed_before - 2, "the ring chunks wait in the drain's list")
	for(var/obj/dq_interest_probe/probe as anything in probes)
		TEST_ASSERT(probe.refresh_queued, "nothing in the ring was drawn inside the step")
	set_global(nameof(GLOB.interest_arrival_step_max), 16)
	var/passes = 0
	for(var/pass in 1 to 200)
		if(!length(GLOB.interest_prefetched) && !length(GLOB.interest_ring_scans))
			break
		interest_arrival_drain()
		passes++
	TEST_ASSERT(!length(GLOB.interest_ring_scans) && !length(GLOB.interest_prefetched), "the drain worked the ring down ([passes] passes)")
	for(var/obj/dq_interest_probe/probe as anything in probes)
		TEST_ASSERT_EQUAL(probe.refresh_queued, 0, "and everything in it was drawn before the walker could see it")
	interest_clean(probes)

/// A ring chunk the walker left behind before the drain reached it is dropped unscanned.
/datum/unit_test/dq_move_stale_ring_chunk_is_not_scanned

/datum/unit_test/dq_move_stale_ring_chunk_is_not_scanned/Run()
	interest_isolate()
	set_global(nameof(GLOB.interest_ring_scans_stale), GLOB.interest_ring_scans_stale)
	var/turf/base = test_floor()
	var/start_x = round((base.x - 1) / INTEREST_CHUNK) * INTEREST_CHUNK + 1
	var/turf/home = locate(start_x, base.y, base.z)
	var/turf/far = interest_far_from(home)
	TEST_ASSERT(home && far, "the map has room")
	interest_view_set("dq-test-walker", home, null, world.view)
	TEST_ASSERT(length(GLOB.interest_holds["dq-test-walker"]), "it holds chunks")
	// A ring entry for a chunk nobody holds.
	var/far_key = INTEREST_KEY(far.z, INTEREST_CHUNK_OF(far.x), INTEREST_CHUNK_OF(far.y))
	GLOB.interest_ring_scans = list(list(far_key, 0, 0))
	var/scanned_before = GLOB.interest_chunks_entered
	var/stale_before = GLOB.interest_ring_scans_stale
	TEST_ASSERT(interest_ring_scan(), "the entry is consumed")
	TEST_ASSERT_EQUAL(GLOB.interest_chunks_entered, scanned_before, "an unheld chunk is not walked")
	TEST_ASSERT_EQUAL(GLOB.interest_ring_scans_stale - stale_before, 1, "and is counted as stale")

/// A step of a mob costs a bounded number of marks and no interest scans, and the MOVE_COST trace counts it.
/datum/unit_test/dq_move_cost_counters_bounded

/datum/unit_test/dq_move_cost_counters_bounded/Run()
	set_global(nameof(GLOB.move_cost_steps), GLOB.move_cost_steps)
	set_global(nameof(GLOB.move_cost_sampled), GLOB.move_cost_sampled)
	set_global(nameof(GLOB.move_cost_slow), GLOB.move_cost_slow)
	set_global(nameof(GLOB.move_cost_worst_ms), GLOB.move_cost_worst_ms)
	set_global(nameof(GLOB.move_cost_total_ms), GLOB.move_cost_total_ms)
	set_global(nameof(GLOB.move_cost_on), FALSE)
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	refresh_flush()
	var/steps = 0
	var/moved = 0
	var/marks_before = GLOB.refresh_marks_raised
	var/scanned_before = GLOB.interest_chunks_entered
	var/steps_before = GLOB.move_cost_steps
	var/walk_dir = EAST
	for(var/i in 1 to 24)
		var/turf/next = get_step(H, walk_dir)
		if(!next || next.density)
			walk_dir = turn(walk_dir, 180)
			next = get_step(H, walk_dir)
		if(!next)
			break
		var/turf/from = get_turf(H)
		var/started = move_cost_begin()
		if(H.Move(next, walk_dir))
			moved++
		move_cost_end(started, H, from, marks_before, scanned_before, 0)
		steps++
	TEST_ASSERT(moved >= 8, "the mob walked ([moved] of [steps] steps)")
	TEST_ASSERT_EQUAL(GLOB.move_cost_steps - steps_before, steps, "every step was measured")
	TEST_ASSERT(!GLOB.move_cost_on, "and the measuring stopped")
	var/marks = GLOB.refresh_marks_raised - marks_before
	log_test("MOVE_COST: [steps] steps raised [marks] marks ([round(marks / max(1, steps), 0.1)] a step), scanned [GLOB.interest_chunks_entered - scanned_before] chunks")
	TEST_ASSERT(marks <= steps * 6, "a step raises a handful of marks at most ([marks] over [steps] steps)")
	TEST_ASSERT_EQUAL(GLOB.interest_chunks_entered - scanned_before, 0, "and walks no chunk of the interest grid when nobody watches")

/// A source in a chunk a viewer holds is queued ahead of every source elsewhere, and the step drains the near ones first.
/datum/unit_test/dq_move_near_light_source_drains_first

/datum/unit_test/dq_move_near_light_source_drains_first/Run()
	interest_isolate()
	var/turf/home = test_floor()
	var/turf/far = interest_far_from(home)
	TEST_ASSERT(home && far, "the map has room")
	var/obj/machinery/light/near_light = allocate(/obj/machinery/light, home)
	var/obj/machinery/light/far_light = allocate(/obj/machinery/light, far)
	SSlighting.light_step(0, TRUE)
	var/datum/light_source/near_source = near_light.light
	var/datum/light_source/far_source = far_light.light
	TEST_ASSERT(near_source && far_source, "both fixtures have a light source")
	interest_view_set("dq-test-viewer", home, null, world.view)
	// The far one is queued first: it would be served first in arrival order.
	far_source.force_update()
	near_source.force_update()
	TEST_ASSERT(far_source in SSlighting.sources_queue, "a source nobody holds waits in the ordinary queue")
	TEST_ASSERT(handle_of(near_source) in SSlighting.sources_queue_near, "a source in a held chunk waits in the near queue")
	TEST_ASSERT(!(near_source in SSlighting.sources_queue), "and in no other")
	TEST_ASSERT(SSlighting.pending_source_count() >= 2, "the pending count covers both")
	// One drain of the near queue serves the near source and leaves the far one.
	SSlighting.drain_sources(SSlighting.sources_queue_near, FALSE, TRUE)
	TEST_ASSERT_EQUAL(near_source.needs_update, LIGHTING_NO_UPDATE, "the near source was updated")
	TEST_ASSERT(far_source in SSlighting.sources_queue, "the far one still waits")
	TEST_ASSERT(far_source.needs_update != LIGHTING_NO_UPDATE, "and is still owed its update")
	// A source that goes while queued leaves whichever queue holds it.
	near_source.force_update()
	SSlighting.unqueue_source(near_source)
	TEST_ASSERT(!(handle_of(near_source) in SSlighting.sources_queue_near), "unqueue takes it out of the near queue")
	near_source.needs_update = LIGHTING_NO_UPDATE
	SSlighting.light_step(0, TRUE)
	TEST_ASSERT_EQUAL(far_source.needs_update, LIGHTING_NO_UPDATE, "a full step drains the rest")

/// Input never waits behind deferrable work: the input inbox drains first in phase K and the held keys (movement) run straight after it,
/// ahead of the lighting step and every other host service of the phase.
/datum/unit_test/dq_move_input_runs_first_in_phase_k

/datum/unit_test/dq_move_input_runs_first_in_phase_k/Run()
	if(!Kernel.phase_items)
		Kernel.rebuild_work_graph()
	var/list/items = Kernel.phase_items[KERNEL_PHASE_K]
	var/drain_at = 0
	var/keys_at = 0
	var/light_at = 0
	var/index = 0
	for(var/datum/work_item/W as anything in items)
		index++
		var/key = "[W.key]"
		if(findtext(key, "drain_step"))
			drain_at = index
		else if(findtext(key, "key_step"))
			keys_at = index
		else if(findtext(key, "light_step"))
			light_at = index
	TEST_ASSERT(drain_at && keys_at && light_at, "phase K holds the inbox drain ([drain_at]), the key loop ([keys_at]) and the light step ([light_at])")
	TEST_ASSERT(drain_at < keys_at, "the inbox drains before the held keys move anyone")
	TEST_ASSERT(keys_at < light_at, "and the held keys move before the lighting step spends the tick")
	index = 0
	for(var/datum/work_item/W as anything in items)
		index++
		if(index > keys_at || W.first)
			continue
		var/key = "[W.key]"
		TEST_ASSERT(findtext(key, "drain_step") || findtext(key, "key_step"), "[key] runs ahead of the held keys and is not input")

/// An input that finds no room in the tick (the tick is over its threshold) resolves in the next tick's phase K, ahead of the rest of the tick's work.
/datum/unit_test/dq_move_input_over_budget_resolves_next_tick

/datum/unit_test/dq_move_input_over_budget_resolves_next_tick/Run()
	test_driver_begin()
	GLOB.inbox_probe_log = list()
	SSinput.room_override = FALSE
	var/waited_before = SSinput.resolved_queued
	for(var/n in 1 to 5)
		TEST_ASSERT(!input_submit(inbox_probe("[n]", "client_[n]")), "input [n] finds no room and queues")
	TEST_ASSERT_EQUAL(SSinput.queued_total(), 5, "five inputs wait")
	test_phase(KERNEL_PHASE_K)
	TEST_ASSERT_EQUAL(SSinput.queued_total(), 0, "the next tick's phase K served every one of them")
	TEST_ASSERT_EQUAL(SSinput.resolved_queued - waited_before, 5, "each counted as resolved from the inbox")
	TEST_ASSERT_EQUAL(length(GLOB.inbox_probe_log), 5, "and each ran")
	test_driver_end()
