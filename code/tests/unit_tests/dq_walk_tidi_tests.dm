// Walking time dilation, second pass (live round 2026-11-14): work that cannot be split (one draw, one answer's callback) is not started on a tick
// that is already spent, a slow answer is named, and a step's HUD work is only what the place changes.

/// A scheduler whose tick is always spent: its lane's share is under the tick usage, whatever that is.
/datum/time_scheduler/dq_spent_tick
	limit = -1

/// A draw pass that finds the tick spent starts no draw and loses nothing; after DRAW_STARVED_MAX such passes the next one draws, so the queue still empties.
/datum/unit_test/dq_draw_pass_holds_back_on_a_spent_tick

/datum/unit_test/dq_draw_pass_holds_back_on_a_spent_tick/Run()
	draw_isolate()
	var/turf/T = test_floor()
	var/list/probes = draw_probes(T, 6)
	for(var/obj/dq_draw_probe/probe as anything in probes)
		probe.set_shown(rand(1, 9))
	TEST_ASSERT_EQUAL(draw_depth(), 6, "every change is filed")
	GLOB.draw_n["starved"] = 0
	var/datum/time_scheduler/dq_spent_tick/sched = new
	TEST_ASSERT(sched.over_tick_limit(), "the scheduler's tick is spent")
	var/drawn = GLOB.draw_n["drawn"]
	var/skips = GLOB.draw_n["budget_skips"]
	for(var/pass in 1 to DRAW_STARVED_MAX)
		TEST_ASSERT(!draw_drain(sched), "pass [pass]: the pass reports work left")
	TEST_ASSERT_EQUAL(GLOB.draw_n["drawn"] - drawn, 0, "no draw started on a spent tick")
	TEST_ASSERT_EQUAL(GLOB.draw_n["budget_skips"] - skips, DRAW_STARVED_MAX, "each held-back pass was counted")
	TEST_ASSERT_EQUAL(draw_depth(), 6, "nothing was lost or dropped")
	draw_drain(sched)
	TEST_ASSERT_EQUAL(GLOB.draw_n["drawn"] - drawn, 1, "the pass after the starvation limit draws one and stops (its budget is spent)")
	TEST_ASSERT_EQUAL(GLOB.draw_n["starved"], 0, "and the count starts again")
	draw_flush()
	TEST_ASSERT_EQUAL(draw_depth(), 0, "the queue empties")
	draw_clean(probes)

/// The refresh queue's pass follows the same rule.
/datum/unit_test/dq_refresh_pass_holds_back_on_a_spent_tick

/datum/unit_test/dq_refresh_pass_holds_back_on_a_spent_tick/Run()
	draw_isolate()
	var/turf/T = test_floor()
	var/obj/dq_draw_probe/effect/probe = allocate(/obj/dq_draw_probe/effect, T)
	refresh_flush()
	draw_flush()
	probe.set_shown(5)
	TEST_ASSERT(length(GLOB.refresh_queue) >= 1, "the probe waits in the refresh queue")
	GLOB.draw_n["starved"] = 0
	var/datum/time_scheduler/dq_spent_tick/sched = new
	var/skips = GLOB.draw_n["budget_skips"]
	TEST_ASSERT(!refresh_drain(sched), "the pass on a spent tick reports work left")
	TEST_ASSERT_EQUAL(GLOB.draw_n["budget_skips"] - skips, 1, "it was counted")
	TEST_ASSERT(length(GLOB.refresh_queue) >= 1, "and the probe still waits")
	GLOB.draw_n["starved"] = DRAW_STARVED_MAX
	refresh_drain(sched)
	GLOB.draw_n["starved"] = 0
	refresh_flush()
	draw_flush()

/// An owner whose callback takes IO_SLOW_DELIVERY_MS and more.
/datum/walk_tidi_io_owner
	var/done = 0

/datum/walk_tidi_io_owner/proc/slow_answer(result, error, tag)
	done++
	var/started = TICK_USAGE_REAL
	while(TICK_DELTA_TO_MS(TICK_USAGE_REAL - started) < IO_SLOW_DELIVERY_MS + 2)
		continue

/// A delivery that takes tens of ms is counted and named (IO_SLOW), so the next live trace says which callback it was.
/datum/unit_test/io_transport/dq_io_slow_delivery_is_named

/datum/unit_test/io_transport/dq_io_slow_delivery_is_named/run_io()
	var/datum/walk_tidi_io_owner/E = allocate(/datum/walk_tidi_io_owner)
	var/slow_before = GLOB.io_lane.slow_deliveries
	io_job(E, /datum/io_backend/test, "ok", TYPE_PROC_REF(/datum/walk_tidi_io_owner, slow_answer), "slow")
	for(var/pass in 1 to 40)
		if(!io_job_count())
			break
		io_poll(GLOB.io_lane)
	TEST_ASSERT_EQUAL(E.done, 1, "the job was delivered")
	TEST_ASSERT_EQUAL(GLOB.io_lane.slow_deliveries - slow_before, 1, "the slow delivery was counted")
	TEST_ASSERT(findtext(GLOB.io_lane.slow_what, "slow_answer"), "and named by its callback ([GLOB.io_lane.slow_what])")
	TEST_ASSERT(GLOB.io_lane.slow_ms_max >= IO_SLOW_DELIVERY_MS, "with its cost ([GLOB.io_lane.slow_ms_max] ms)")

/// A step's HUD work from the place is night vision (and the robot's air, the pAI's card), not the whole HUD pass: it draws for a viewer only (a mob with
/// no client has no HUD to adapt) and never redraws the health doll the whole pass redraws.
/datum/unit_test/dq_hud_place_pass_is_the_place_only

/datum/unit_test/dq_hud_place_pass_is_the_place_only/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	H.set_hud_used(new /datum/hud(H))
	H.hud_used.instantiate()
	STATE_SET(H, human_misc, health_doll_key, "untouched")
	TEST_ASSERT(!H.life_hud_place(), "without a client there is no HUD to adapt")
	H.life_hud_place_changed(null)
	TEST_ASSERT_EQUAL(STATE_GET(H, human_misc, health_doll_key), "untouched", "and the place reaction did not redraw the health doll the whole pass would")
