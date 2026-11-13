// Deferred callbacks that stay inside their share of a tick (SLOW_TICK 2026-11-13: client glow scan 44-105 ms, glow store 45-65 ms, io lane poll 47 ms, interest drain 10-75 ms).

#define GLOW_BUDGET_SLOW_MS 3

/// Burns about `ms` server milliseconds (a stand-in for a callback with real cost).
/datum/unit_test/proc/glow_budget_burn(ms)
	var/started = TICK_USAGE_REAL
	while(TICK_DELTA_TO_MS(TICK_USAGE_REAL - started) < ms)
		continue

/// A full scan with a budget stops inside a chunk that holds many lights (one light a step at a zero budget), and the steps together hold what a scan in one go holds.
/datum/unit_test/dq_glow_scan_stops_inside_a_chunk

/datum/unit_test/dq_glow_scan_stops_inside_a_chunk/Run()
	var/list/got = list()
	client_glow_holder_setup(got)
	var/datum/client_glow_holder/whole = got[2]
	var/turf/E = client_glow_test_eye(get_turf(got[1]))
	var/made = 0
	for(var/turf/T as anything in block(locate(max(1, E.x - 3), max(1, E.y - 3), E.z), locate(min(world.maxx, E.x + 3), min(world.maxy, E.y + 3), E.z)))
		if(T.density || locate(/obj/machinery/light) in T)
			continue
		allocate(/obj/machinery/light, T)
		if(++made >= 8)
			break
	TEST_ASSERT(made >= 4, "several lights stand about the eye ([made])")
	SSlighting.light_step(0, TRUE)
	var/datum/client_glow_holder/spread = new
	spread.scan_budget_ms = 0
	spread.view_at(E, 7, 7)
	TEST_ASSERT_NOTNULL(spread.scan_chunks, "the first step leaves work for the next ticks")
	TEST_ASSERT(spread.scan_lights <= 1, "a zero budget examines one light in the first step, not the chunk's [made] ([spread.scan_lights])")
	TEST_ASSERT(spread.scan_partial_steps > 0, "the step stopped inside a chunk")
	var/steps = client_glow_finish_scan(spread, 500)
	TEST_ASSERT(steps >= made, "the lights took a step each ([steps] steps)")
	TEST_ASSERT_NULL(spread.scan_chunks, "the scan closed")
	var/datum/client_glow_holder/direct = new
	direct.view_at(E, 7, 7)
	TEST_ASSERT_EQUAL(client_glow_held_keys(spread), client_glow_held_keys(direct), "a scan stopped inside chunks holds what a scan in one go holds")
	spent(spread)
	spent(direct)
	spent(whole)
	client_lighting_set(FALSE)
	SSlighting.light_step(0, TRUE)

/// Door twins are worked out a few ms a turn, not by the call that held the light: a pump with no budget does one light, and a viewer with a budget leaves the light's twins to the pump.
/datum/unit_test/dq_glow_twins_pump_is_bounded

/datum/unit_test/dq_glow_twins_pump_is_bounded/Run()
	var/list/got = list()
	client_glow_holder_setup(got)
	var/turf/E = client_glow_test_eye(get_turf(got[1]))
	var/list/lights = list()
	for(var/turf/T as anything in block(locate(max(1, E.x - 3), max(1, E.y - 3), E.z), locate(min(world.maxx, E.x + 3), min(world.maxy, E.y + 3), E.z)))
		if(T.density || locate(/obj/machinery/light) in T)
			continue
		var/obj/machinery/light/F = allocate(/obj/machinery/light, T)
		lights += F
		if(length(lights) >= 6)
			break
	SSlighting.light_step(0, TRUE)
	var/datum/client_glow_baker/B = GLOB.client_glow_baker
	B.twin_work = list()
	var/queued = 0
	for(var/obj/machinery/light/F as anything in lights)
		var/datum/light_source/L = F.light
		if(!L?.glow_mask_key)
			continue
		L.glow_twins_for = null
		B.twin_work[L.glow_holder_key || L.glow_holder_key()] = TRUE
		queued++
	TEST_ASSERT(queued >= 3, "several held lights wait for their twins ([queued])")
	TEST_ASSERT_EQUAL(client_glow_twins_pump(0), 1, "a pump with no budget works out one light")
	TEST_ASSERT_EQUAL(length(B.twin_work), queued - 1, "the rest waits for the next turn")
	TEST_ASSERT_EQUAL(client_glow_twins_pump(100000), queued - 1, "a turn with room does what is left")
	TEST_ASSERT(!length(B.twin_work), "nothing is left waiting")
	// A viewer with a budget leaves the work to the pump instead of doing it in the call that held the light.
	var/obj/machinery/light/G = lights[1]
	var/datum/light_source/GL = G.light
	GL.glow_twins_for = null
	var/datum/client_glow_holder/H = got[2]
	H.acquire_budget_ms = 4
	H.twins_later(GL)
	TEST_ASSERT_NULL(GL.glow_twins_for, "the light's twins were not worked out by the call")
	TEST_ASSERT(length(B.twin_work), "the light waits for the pump")
	client_glow_twins_pump(100000)
	TEST_ASSERT_EQUAL(GL.glow_twins_for, GL.glow_mask_key, "and the pump worked them out")
	B.twin_work = list()
	spent(H)
	client_lighting_set(FALSE)
	SSlighting.light_step(0, TRUE)

/datum/glow_budget_owner
	var/done = 0

/datum/glow_budget_owner/proc/slow_done(result, error, tag)
	done++
	var/started = TICK_USAGE_REAL
	while(TICK_DELTA_TO_MS(TICK_USAGE_REAL - started) < GLOW_BUDGET_SLOW_MS)
		continue

/// An I/O lane pass whose answers carry slow callbacks stops once it has spent its own share and goes on the next pass; every job is delivered in the end.
/datum/unit_test/io_transport/dq_io_poll_pass_is_bounded

/datum/unit_test/io_transport/dq_io_poll_pass_is_bounded/run_io()
	var/datum/glow_budget_owner/E = allocate(/datum/glow_budget_owner)
	for(var/i in 1 to 24)
		io_job(E, /datum/io_backend/test, "ok", TYPE_PROC_REF(/datum/glow_budget_owner, slow_done), "j[i]")
	var/started = TICK_USAGE_REAL
	io_poll(GLOB.io_lane)
	var/spent_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started)
	TEST_ASSERT(spent_ms < IO_POLL_BUDGET_MS + 2 * GLOW_BUDGET_SLOW_MS, "one pass delivered a few slow answers, not all 24 ([spent_ms] ms)")
	TEST_ASSERT(E.done > 0 && E.done < 24, "some answers went out and some wait ([E.done] of 24)")
	TEST_ASSERT(GLOB.io_lane.poll_cut > 0, "the pass counted its cut")
	for(var/pass in 1 to 40)
		if(!io_job_count())
			break
		io_poll(GLOB.io_lane)
	TEST_ASSERT_EQUAL(E.done, 24, "every job was delivered over the passes")

/// A drain pass without a cap stops once it has spent its own milliseconds after drawing something; a capped pass (a login) and a pass that drew nothing do not.
/datum/unit_test/dq_interest_drain_pass_has_a_ms_cap

/datum/unit_test/dq_interest_drain_pass_has_a_ms_cap/Run()
	set_global(nameof(GLOB.interest_arrival_step_max), 0)
	set_global(nameof(GLOB.interest_pass_cut), 0)
	GLOB.interest_pass_started = TICK_USAGE_REAL
	TEST_ASSERT(!interest_arrival_pass_full(1), "a fresh pass is not full")
	glow_budget_burn(INTEREST_ARRIVAL_PASS_MS + 1)
	TEST_ASSERT(interest_arrival_pass_full(1), "a pass past its milliseconds that drew something is full")
	TEST_ASSERT(!interest_arrival_pass_full(0), "one that drew nothing still draws its first")
	TEST_ASSERT(!interest_arrival_pass_full(1, 32), "a capped pass is the caller's own and is cut by its cap alone")
