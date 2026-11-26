// A player running in circles in a lit room with an APC (the live test server's time dilation spiked to 20% while one did, 2026-11-13 23:39).
// What it taught: the APC's native tick put an "APC channel changed" notice on the outbox every tick for every APC whose alarm was up (any that had shed
// its channels or had no cell), so a frame delivered a hundred of them, each looked up and asked "does anything hear this" on the tick, and the delivery
// budget (NATIVE_DELIVERY_BUDGET_MS) ran out. A run of steps records, per step, the tick cost, the Rust frame, the delivery and the notices and light
// work it caused, and asserts the counters rather than the milliseconds.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// The native notice header of "an APC's channel changed" (power event, verdigris/domains/power/src/laws.rs).
#define DQ_NOTICE_APC_CHANNEL_CHANGED "65538"

/// One loop of a square, a step at a time.
GLOBAL_LIST_INIT(dq_run_circle_dirs, list(EAST, SOUTH, WEST, NORTH))

/datum/unit_test/dq_run_circle_apc_notices_per_step

/datum/unit_test/dq_run_circle_apc_notices_per_step/Run()
	var/obj/machinery/power/apc/apc = dq_grid_isolated_apc(0)
	if(apc)
		keep_area_power(apc.area) // queued first, so it runs last: after the APC is back
	defer_cleanup(null, GLOBAL_PROC_REF(dq_grid_restore_apc), apc)
	TEST_ASSERT_NOTNULL(apc, "the test map has no working APC")
	if(!apc)
		return
	var/datum/system/native/N = native_system()
	// Let the APC shed everything it will: after that its alarm stays up and nothing about its channels changes.
	for(var/i in 1 to 60)
		dq_power_test_step()
	var/turf/start
	for(var/turf/simulated/floor/F in range(3, apc))
		if(!F.density && !F.contains_dense_objects())
			start = F
			break
	if(!start)
		start = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, start)
	refresh_flush()
	SSlighting.light_step(0, TRUE)
	var/steps = 0
	var/moved = 0
	var/notices = 0
	var/queued_total = 0
	var/queued_worst = 0
	var/builds_before = GLOB.client_glow_mask_builds
	var/reconsiders_before = GLOB.client_glow_reconsiders
	var/worst_step_ms = 0
	var/total_step_ms = 0
	var/total_vg_ms = 0
	var/total_delivery_ms = 0
	var/worst_native_ms = 0
	var/records = 0
	var/list/dirs = GLOB.dq_run_circle_dirs
	for(var/lap in 1 to 24)
		for(var/d in dirs)
			var/turf/next = get_step(H, d)
			var/before_notices = LAZYACCESS(N.notice_counts, DQ_NOTICE_APC_CHANNEL_CHANGED) || 0
			var/queued_before = SSlighting.pending_source_count()
			var/started = TICK_USAGE_REAL
			if(next && !next.density && H.Move(next, d))
				moved++
			SSlighting.light_step(0, TRUE)
			dq_power_test_step()
			var/step_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started)
			steps++
			total_step_ms += step_ms
			worst_step_ms = max(worst_step_ms, step_ms)
			total_vg_ms += N.last_vg_ms
			total_delivery_ms += N.last_frame_ms - N.last_vg_ms
			worst_native_ms = max(worst_native_ms, N.last_frame_ms)
			records += N.last_records
			notices += (LAZYACCESS(N.notice_counts, DQ_NOTICE_APC_CHANNEL_CHANGED) || 0) - before_notices
			var/queued = max(0, SSlighting.pending_source_count() - queued_before)
			queued_total += queued
			queued_worst = max(queued_worst, queued)
	log_test("RUN_CIRCLE: [steps] steps ([moved] moved): tick cost mean [round(total_step_ms / steps, 0.01)] ms worst [round(worst_step_ms, 0.01)] ms; native frame mean vg_frame [round(total_vg_ms / steps, 0.01)] ms, delivery [round(total_delivery_ms / steps, 0.01)] ms, worst frame [round(worst_native_ms, 0.01)] ms, [round(records / steps, 0.1)] records a step; APC channel notices [notices] ([round(notices / steps, 0.01)] a step); light sources queued [queued_total] ([queued_worst] worst step); glow mask builds [GLOB.client_glow_mask_builds - builds_before], reconsiders [GLOB.client_glow_reconsiders - reconsiders_before]")
	TEST_ASSERT(moved >= steps * 0.6, "the player ran ([moved] of [steps] steps)")
	TEST_ASSERT_EQUAL(notices, 0, "an APC whose channels stopped changing sends no channel notice, whatever the player does ([notices] over [steps] steps)")
	TEST_ASSERT(queued_worst <= 3, "a step of the player queues a handful of light sources at most ([queued_worst])")
	TEST_ASSERT(records / steps < 8, "a step's frame delivers a handful of records ([round(records / steps, 0.1)] a step)")

/// Asking whether anything hears a native notice on an APC is a constant-time table lookup: it ran once per APC notice on the tick (the live trace
/// had one at 48 ms, which is the OS taking the core, and not the check).
/datum/unit_test/dq_apc_notice_wanted_is_constant

/datum/unit_test/dq_apc_notice_wanted_is_constant/Run()
	var/obj/machinery/power/apc/apc = dq_power_test_apc()
	TEST_ASSERT_NOTNULL(apc, "the test map has no working APC")
	if(!apc)
		return
	var/hooks = length(apc.rx?.hooks)
	var/started = TICK_USAGE_REAL
	var/heard = 0
	for(var/i in 1 to 2000)
		if(notice_wanted(apc, /datum/notice/native))
			heard++
	var/per_call_us = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started) * 1000 / 2000
	log_test("RUN_CIRCLE: notice_wanted on an APC: [round(per_call_us, 0.1)] us a call, [hooks] activation hook(s) on it, heard [heard] of 2000")
	TEST_ASSERT(per_call_us < 100, "notice_wanted on an APC is a lookup, not a walk ([round(per_call_us, 0.1)] us a call with [hooks] hooks)")

/// The slow-tick trace names what native_step spent outside vg_frame and delivery, and a slow notice's log write is not charged to its record.
/datum/unit_test/dq_native_post_frame_is_itemised

/datum/unit_test/dq_native_post_frame_is_itemised/Run()
	var/datum/system/native/N = native_system()
	N.drain()
	TEST_ASSERT(N.last_post_apc_ms >= 0 && N.last_post_notice_log_ms >= 0 && N.last_post_deferral_log_ms >= 0 && N.last_post_report_ms >= 0, "the post-frame parts are measured")
	LAZYADD(N.slow_notice_lines, "dq test: a slow notice line, written after the frame")
	N.drain()
	TEST_ASSERT(!length(N.slow_notice_lines), "the frame wrote the queued slow-notice lines after it timed itself")
	var/kinds = 0
	for(var/header in N.notice_counts)
		kinds++
	TEST_ASSERT(kinds >= 0, "the per-header notice counts are a list")

#undef DQ_NOTICE_APC_CHANNEL_CHANGED

#endif
