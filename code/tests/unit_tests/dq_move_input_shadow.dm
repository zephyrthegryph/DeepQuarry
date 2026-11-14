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
	var/scanned_before = GLOB.gaze_chunks_entered
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
	log_test("MOVE_COST: [steps] steps raised [marks] marks ([round(marks / max(1, steps), 0.1)] a step), scanned [GLOB.gaze_chunks_entered - scanned_before] chunks")
	TEST_ASSERT(marks <= steps * 6, "a step raises a handful of marks at most ([marks] over [steps] steps)")
	TEST_ASSERT_EQUAL(GLOB.gaze_chunks_entered - scanned_before, 0, "and walks no chunk of the gaze grid when nobody watches")

/// A walking human's step is split into the parts the MOVE_COST trace names, and the parts never add up to more than the Moved() chain they sit in.
/datum/unit_test/dq_move_cost_parts_add_up

/datum/unit_test/dq_move_cost_parts_add_up/Run()
	set_global(nameof(GLOB.move_cost_steps), GLOB.move_cost_steps)
	set_global(nameof(GLOB.move_cost_sampled), GLOB.move_cost_sampled)
	set_global(nameof(GLOB.move_cost_slow), GLOB.move_cost_slow)
	set_global(nameof(GLOB.move_cost_worst_ms), GLOB.move_cost_worst_ms)
	set_global(nameof(GLOB.move_cost_total_ms), GLOB.move_cost_total_ms)
	set_global(nameof(GLOB.move_cost_on), FALSE)
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	refresh_flush()
	var/list/sum = new /list(MOVE_COST_PART_COUNT)
	for(var/part in 1 to MOVE_COST_PART_COUNT)
		sum[part] = 0
	var/moved = 0
	var/total = 0
	var/walk_dir = EAST
	for(var/i in 1 to 120)
		var/turf/next = get_step(H, walk_dir)
		if(!next || next.density)
			walk_dir = turn(walk_dir, 180)
			next = get_step(H, walk_dir)
		if(!next)
			break
		var/started = move_cost_begin()
		if(H.Move(next, walk_dir))
			moved++
		total += TICK_USAGE_REAL - started
		move_cost_end(started, H, null, GLOB.refresh_marks_raised, GLOB.gaze_chunks_entered, 0)
		for(var/part in 1 to MOVE_COST_PART_COUNT)
			sum[part] += GLOB.move_cost_parts[part]
		refresh_flush()
	TEST_ASSERT(moved >= 40, "the mob walked ([moved] steps)")
	var/inside = 0
	for(var/part in MOVE_COST_LIGHTS to MOVE_COST_INSIDE_LAST)
		inside += sum[part]
	TEST_ASSERT(inside <= sum[MOVE_COST_MOVED] * 1.01 + 0.01, "the parts inside the Moved() chain add up to no more than it ([TICK_DELTA_TO_MS(inside)] of [TICK_DELTA_TO_MS(sum[MOVE_COST_MOVED])] ms)")
	log_test("MOVE_COST parts over [moved] steps, ms a step: whole [round(TICK_DELTA_TO_MS(total) / moved, 0.001)], handlers [round(TICK_DELTA_TO_MS(sum[MOVE_COST_MOVE]) / moved, 0.001)], Moved() [round(TICK_DELTA_TO_MS(sum[MOVE_COST_MOVED]) / moved, 0.001)] (notices [round(TICK_DELTA_TO_MS(sum[MOVE_COST_NOTICES]) / moved, 0.001)], loc readers [round(TICK_DELTA_TO_MS(sum[MOVE_COST_LOC_READS]) / moved, 0.001)], loc draw [round(TICK_DELTA_TO_MS(sum[MOVE_COST_LOC_DRAW]) / moved, 0.001)], hops [round(TICK_DELTA_TO_MS(sum[MOVE_COST_HOPS]) / moved, 0.001)], heat [round(TICK_DELTA_TO_MS(sum[MOVE_COST_HEAT]) / moved, 0.001)], interest [round(TICK_DELTA_TO_MS(sum[MOVE_COST_INTEREST]) / moved, 0.001)], living [round(TICK_DELTA_TO_MS(sum[MOVE_COST_LIVING]) / moved, 0.001)], body [round(TICK_DELTA_TO_MS(sum[MOVE_COST_BODY]) / moved, 0.001)], follow [round(TICK_DELTA_TO_MS(sum[MOVE_COST_FOLLOW]) / moved, 0.001)], lights [round(TICK_DELTA_TO_MS(sum[MOVE_COST_LIGHTS]) / moved, 0.001)], lifeform [round(TICK_DELTA_TO_MS(sum[MOVE_COST_LIFEFORM]) / moved, 0.001)], publish [round(TICK_DELTA_TO_MS(sum[MOVE_COST_MOB_PUBLISH]) / moved, 0.001)])")

/// A source in a chunk a viewer holds is queued ahead of every source elsewhere, and the step drains the near ones first.
/datum/unit_test/dq_move_near_light_source_drains_first

/datum/unit_test/dq_move_near_light_source_drains_first/Run()
	draw_isolate()
	var/turf/home = test_floor()
	var/turf/far = draw_chunks_from(home, 4)
	TEST_ASSERT(home && far, "the map has room")
	var/obj/machinery/light/near_light = allocate(/obj/machinery/light, home)
	var/obj/machinery/light/far_light = allocate(/obj/machinery/light, far)
	SSlighting.light_step(0, TRUE)
	var/datum/light_source/near_source = near_light.light
	var/datum/light_source/far_source = far_light.light
	TEST_ASSERT(near_source && far_source, "both fixtures have a light source")
	gaze_view_set("dq-test-viewer", home, null, world.view)
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
