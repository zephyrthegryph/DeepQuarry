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

// ---------------------------------------------------------------------------------------------------------------------
// Walking time dilation, third pass (live round 2026-11-14, master 7e34ae142c): the flat light read skips the glows out of reach,
// a finished mask bake is taken in by the baker's turn and not by the io callback, and the extra step parts add up.

/// A turf past a glow's rim draws none of its light (the profile is 0 from the rim): the read skips the glow before building its reach key, and the turf beside the light is lit.
/datum/unit_test/dq_flat_light_read_skips_glows_out_of_reach

/datum/unit_test/dq_flat_light_read_skips_glows_out_of_reach/Run()
	set_global(nameof(GLOB.client_lighting), FALSE) // a failed run leaves the mode off for the next test
	client_glow_counters_restore()
	var/turf/T = run_loc_floor_bottom_left
	client_lighting_set(TRUE)
	SSlighting.light_step(0, TRUE)
	var/obj/machinery/light/lamp = allocate(/obj/machinery/light, T)
	SSlighting.light_step(0, TRUE)
	var/obj/effect/overlay/client_glow/G = lamp.light.glow
	TEST_ASSERT(G, "the lamp glows")
	var/half_width = WORLD_ICON_SIZE / 2 - G.pixel_x
	var/reach_tiles = CEILING(half_width / WORLD_ICON_SIZE, 1)
	var/list/near = client_flat_light_rgb(T)
	TEST_ASSERT(max(near[1], near[2], near[3]) > 0, "the turf the lamp stands on is lit")
	var/turf/far = locate(T.x + reach_tiles + 1, T.y, T.z)
	TEST_ASSERT(far, "the map has room past the glow's rim")
	if(far.has_dynamic_lighting()) // a turf outside dynamic lighting carries a white tile whatever the glows do
		var/list/gone = client_flat_light_rgb(far)
		TEST_ASSERT_EQUAL(max(gone[1], gone[2], gone[3]), 0, "a turf past the glow's rim draws none of its light")
	client_lighting_set(FALSE)
	SSlighting.light_step(0, TRUE)

/// The io callback of a finished mask bake only files the answer: the bake's pending mark stays until a baker turn takes it in, a turn with no budget takes one in, and
/// a turn with room takes the rest, so one io pass never pays for a bake's whole arrival.
/datum/unit_test/dq_glow_mask_answer_is_filed_then_taken_in_by_a_turn

/datum/unit_test/dq_glow_mask_answer_is_filed_then_taken_in_by_a_turn/Run()
	var/datum/client_glow_baker/B = GLOB.client_glow_baker
	var/list/keys = list("dq-walk3-a", "dq-walk3-b", "dq-walk3-c")
	var/list/pending = list()
	var/list/asked = list()
	for(var/key in keys)
		pending[key] = TRUE
		asked[key] = REALTIMEOFDAY
	set_var(B, nameof(B.finished), list())
	set_var(B, nameof(B.inflight), 3)
	set_var(B, nameof(B.pending), pending)
	set_var(B, nameof(B.asked_at), asked)
	set_var(B, nameof(B.failed), B.failed)
	var/failed_before = B.failed
	for(var/key in keys)
		client_glow_mask_job_done(null, "test error", key, "sheet-[key]")
	TEST_ASSERT_EQUAL(length(B.finished), 3, "the three answers were filed")
	TEST_ASSERT_EQUAL(B.inflight, 0, "and the bakes are no longer in flight")
	TEST_ASSERT_EQUAL(B.failed, failed_before, "the callback took nothing in")
	TEST_ASSERT(B.pending[keys[1]], "the shape is still pending until a turn takes it in")
	TEST_ASSERT(B.turn_waiting, "the baker's turn was armed")
	TEST_ASSERT_EQUAL(client_glow_finished_run(-1), 1, "a turn with no budget takes one in")
	TEST_ASSERT_EQUAL(B.failed, failed_before + 1, "it was counted")
	TEST_ASSERT(!B.pending[keys[1]], "and its pending mark is gone")
	TEST_ASSERT(B.pending[keys[2]], "the next one waits")
	TEST_ASSERT_EQUAL(client_glow_finished_run(100000), 2, "a turn with room takes the rest")
	TEST_ASSERT_EQUAL(length(B.finished), 0, "nothing is left filed")
	TEST_ASSERT_EQUAL(B.failed, failed_before + 3, "all three were counted")
	TEST_ASSERT(!B.pending[keys[3]], "no pending mark is left")

/// A step's parts (the living tail's pieces and the nutrition write among them) are numbered inside the table, so a trace line can name them.
/datum/unit_test/dq_move_cost_parts_name_the_living_tail

/datum/unit_test/dq_move_cost_parts_name_the_living_tail/Run()
	TEST_ASSERT(MOVE_COST_LIVING_PUBLISH > MOVE_COST_EYE_GLOW && MOVE_COST_BODY_NUTRITION <= MOVE_COST_PART_COUNT, "the new parts sit past the older ones and inside the table")
	TEST_ASSERT_EQUAL(length(GLOB.move_cost_parts), MOVE_COST_PART_COUNT, "the table has a slot for each")
