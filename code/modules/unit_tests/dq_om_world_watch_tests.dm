// Unit tests for the Rust world on the OM scheduler (code/datums/om/world_watch.dm,
// object_model_core.md §4.8): timers, cancel, merged wakes, once per tick, owner deletion,
// keys, lanes and the wake budget, watches through the Rust bind (probe and gas domains),
// rate models, diagnostics and the wake-test helper.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// Waits `ticks` MC ticks (SSbehaviours runs the scheduler, and so the world step, every tick).
/proc/om_test_ticks(ticks)
	sleep(world.tick_lag * ticks)

/**
 * Waits, a tick at a time and for at most `max_ticks`, until `D.vars[var_name]` is truthy (a non-empty list
 * counts). A world watch's wake is delivered by the kernel's urgent phase, which a loaded world (sharded test
 * boots, overrun ticks) can skip for several ticks, so a positive assertion waits for the delivery itself
 * instead of guessing a tick count with om_test_ticks(). Returns whether it arrived.
 */
/proc/om_test_wait_for(datum/D, var_name, max_ticks = 60)
	for(var/attempt in 1 to max_ticks)
		if(om_test_has_arrived(D.vars[var_name]))
			return TRUE
		sleep(world.tick_lag)
	return om_test_has_arrived(D.vars[var_name])

/proc/om_test_has_arrived(value)
	return islist(value) ? length(value) > 0 : !!value

/// A test probe entity (a Probe component, verdigris/ffi/src/sched.rs) by a test's own
/// number, created on first use.
/proc/world_test_probe(cell)
	var/static/list/probes = list()
	var/entity = probes["[cell]"]
	if(!entity || !vg_component_has(entity, VG_KIND_PROBE))
		entity = vg_component_bind(0, VG_KIND_PROBE, list())
		probes["[cell]"] = entity
	return entity

/proc/world_test_probe_set(cell, kpa, kelvin)
	var/entity = world_test_probe(cell)
	vg_component_set(entity, VG_KIND_PROBE, VG_PROBE_FIELD_KPA, -1, kpa)
	vg_component_set(entity, VG_KIND_PROBE, VG_PROBE_FIELD_KELVIN, -1, kelvin)

#define WORLD_PROBE(cell) WORLD_HANDLE(VG_KIND_PROBE, world_test_probe(cell))
#define WORLD_TEST_WAKE TYPE_PROC_REF(/datum/world_test_subscriber, on_world_wake)

/**
 * The wake test for any world-watch owner: with its input held steady `D` must stay
 * asleep, and after `change` runs it must wake within `ticks`. Returns null on success or
 * the failure. Settles for `ticks` first (a Band watch reports its starting band).
 */
/proc/om_world_wake_test(datum/D, list/change, ticks = 4)
	om_world_trace(D)
	om_test_ticks(ticks)
	var/before = om_world_traced_wakes(D)
	om_test_ticks(ticks)
	if(om_world_traced_wakes(D) != before)
		om_world_untrace(D)
		return "[D.type] woke while its input held steady"
	deferred_run(change)
	// Positive: wait for the wake itself (bounded), not a guessed tick count.
	OM_TEST_WAIT_UNTIL(om_world_traced_wakes(D) != before, max(ticks, 30))
	var/after = om_world_traced_wakes(D)
	om_world_untrace(D)
	if(after == before)
		return "[D.type] did not wake after its input changed"
	return null

/// Whether every subscriber in `subs` has been woken at least once.
/proc/om_test_all_woken(list/subs)
	for(var/datum/world_test_subscriber/S as anything in subs)
		if(!length(S.wakes))
			return FALSE
	return TRUE

/// Records every wake: list(reason, source, source_kind, step tick, previous step tick, lane).
/datum/world_test_subscriber
	var/list/wakes = list()
	/// Change probe cell `republish_cell`'s pressure this many more times from the wake (each change a new value, past the hysteresis).
	var/republish = 0
	var/republish_cell

/datum/world_test_subscriber/proc/on_world_wake(datum/native_watch/world/watch, reason, source, source_kind)
	var/datum/om/scheduler/sched = GLOB.om_live_sched
	wakes += list(list(reason, source, source_kind, sched.world_step_tick, sched.world_previous_step_tick, watch.lane))
	if(republish > 0)
		republish--
		world_test_probe_set(republish_cell, 200 + 100 * (3 - republish), 293)

/// Several changes landing in one tick merge into one wake.
/datum/unit_test/dq_world_wakes_merge

/datum/unit_test/dq_world_wakes_merge/Run()
	world_test_probe_set(70, 100, 293)
	om_test_ticks(2)
	var/datum/world_test_subscriber/S = allocate(/datum/world_test_subscriber)
	var/datum/native_watch/world/W = om_world_on_change(S, WORLD_PROBE(70), CH_BIT(CH_PROBE_PRESSURE), WORLD_TEST_WAKE)
	om_test_ticks(2)
	world_test_probe_set(70, 110, 293)
	world_test_probe_set(70, 120, 293)
	world_test_probe_set(70, 130, 293)
	OM_TEST_WAIT_UNTIL(length(S.wakes) >= 1, 60)
	om_test_ticks(3) // a wake that failed to merge would be a second one
	TEST_ASSERT_EQUAL(length(S.wakes), 1, "merged wakes")
	var/list/wake = S.wakes[1]
	TEST_ASSERT(wake[1] & CH_BIT(CH_PROBE_PRESSURE), "merged reason lacks the pressure bit")
	qdel(W)

/// A watch is woken at most once per tick, even when it changes its own input from the wake.
/datum/unit_test/dq_world_once_per_tick

/datum/unit_test/dq_world_once_per_tick/Run()
	world_test_probe_set(71, 100, 293)
	om_test_ticks(2)
	var/datum/world_test_subscriber/S = allocate(/datum/world_test_subscriber)
	S.republish = 3
	S.republish_cell = 71
	var/datum/native_watch/world/W = om_world_on_change(S, WORLD_PROBE(71), CH_BIT(CH_PROBE_PRESSURE), WORLD_TEST_WAKE)
	om_test_ticks(2)
	world_test_probe_set(71, 200, 293)
	OM_TEST_WAIT_UNTIL(length(S.wakes) >= 4, 80)
	om_test_ticks(3) // a fifth wake would be a double wake
	TEST_ASSERT_EQUAL(length(S.wakes), 4, "one wake per change round")
	var/list/ticks = list()
	for(var/list/wake as anything in S.wakes)
		TEST_ASSERT(!(wake[4] in ticks), "woken twice in step [wake[4]]")
		ticks += wake[4]
	qdel(W)

/// A cancelled watch is never woken, and its Rust subscription is gone.
/datum/unit_test/dq_world_cancel

/datum/unit_test/dq_world_cancel/Run()
	world_test_probe_set(72, 100, 293)
	om_test_ticks(2)
	var/datum/world_test_subscriber/S = allocate(/datum/world_test_subscriber)
	var/datum/native_watch/world/W = om_world_on_change(S, WORLD_PROBE(72), CH_BIT(CH_PROBE_PRESSURE), WORLD_TEST_WAKE)
	var/handle = W.handle
	TEST_ASSERT_EQUAL(vg_world_subscriptions(handle), 1, "a new watch has one subscription")
	qdel(W)
	TEST_ASSERT_EQUAL(vg_world_subscriptions(handle), 0, "a cancelled watch kept its subscription")
	world_test_probe_set(72, 200, 293)
	om_test_ticks(4)
	TEST_ASSERT_EQUAL(length(S.wakes), 0, "woke after cancelling")

/// A deleted owner is never called: its watch is dropped (and freed) at its next wake.
/datum/unit_test/dq_world_owner_deleted

/datum/unit_test/dq_world_owner_deleted/Run()
	world_test_probe_set(73, 100, 293)
	om_test_ticks(2)
	var/datum/world_test_subscriber/S = new
	var/datum/native_watch/world/W = om_world_on_change(S, WORLD_PROBE(73), CH_BIT(CH_PROBE_PRESSURE), WORLD_TEST_WAKE)
	var/handle = W.handle
	om_test_ticks(2)
	qdel(S)
	world_test_probe_set(73, 200, 293)
	OM_TEST_WAIT_UNTIL(!W.handle, 60) // the watch is dropped when its wake is delivered
	om_test_ticks(2)
	TEST_ASSERT_EQUAL(length(S.wakes), 0, "a deleted owner was woken")
	TEST_ASSERT(!W.handle, "a watch whose owner is gone was kept")
	TEST_ASSERT_EQUAL(vg_world_subscriptions(handle), 0, "a dropped watch left its subscription in Rust")

/// Wakes run on their watch's lane: urgent ones ignore the budget, the rest spread over ticks.
/datum/unit_test/dq_world_lanes_and_budget

/datum/unit_test/dq_world_lanes_and_budget/Run()
	var/datum/om/scheduler/sched = GLOB.om_live_sched
	world_test_probe_set(74, 100, 293)
	om_test_ticks(2)
	var/old_budget = sched.world_budget
	sched.world_budget = 2
	var/list/watches = list()
	var/list/normal = list()
	for(var/i in 1 to 6)
		var/datum/world_test_subscriber/S = allocate(/datum/world_test_subscriber)
		watches += om_world_on_change(S, WORLD_PROBE(74), CH_BIT(CH_PROBE_PRESSURE), WORLD_TEST_WAKE)
		normal += S
	var/list/urgent = list()
	for(var/i in 1 to 4)
		var/datum/world_test_subscriber/S = allocate(/datum/world_test_subscriber)
		watches += om_world_on_change(S, WORLD_PROBE(74), CH_BIT(CH_PROBE_PRESSURE), WORLD_TEST_WAKE, LANE_URGENT)
		urgent += S
	om_test_ticks(2)
	world_test_probe_set(74, 200, 293)
	// Six normal wakes at two per tick take three ticks; wait for all ten deliveries (bounded).
	OM_TEST_WAIT_UNTIL(om_test_all_woken(normal) && om_test_all_woken(urgent), 80)
	sched.world_budget = old_budget
	var/first_urgent_tick
	for(var/datum/world_test_subscriber/S as anything in urgent)
		TEST_ASSERT_EQUAL(length(S.wakes), 1, "urgent wakes")
		var/list/wake = S.wakes[1]
		TEST_ASSERT_EQUAL(wake[6], LANE_URGENT, "an urgent watch ran on lane [wake[6]]")
		if(isnull(first_urgent_tick))
			first_urgent_tick = wake[4]
		TEST_ASSERT_EQUAL(wake[4], first_urgent_tick, "urgent wakes were spread over ticks")
	// Per step: at most the budget times the ticks it covers (skipped ticks carry over).
	var/list/per_step = list()
	var/list/allowed = list()
	for(var/datum/world_test_subscriber/S as anything in normal)
		TEST_ASSERT_EQUAL(length(S.wakes), 1, "normal wakes")
		if(!length(S.wakes))
			continue
		var/list/wake = S.wakes[1]
		TEST_ASSERT_EQUAL(wake[6], LANE_SIMULATION, "a default watch ran on lane [wake[6]]")
		per_step["[wake[4]]"]++
		allowed["[wake[4]]"] = 2 * clamp(wake[4] - wake[5], 1, 8)
	for(var/step in per_step)
		TEST_ASSERT(per_step[step] <= allowed[step], "[per_step[step]] normal wakes in step [step], over its budget [allowed[step]]")
	for(var/datum/native_watch/W as anything in watches)
		qdel(W)

/// Watches cross the Rust bind: Changed respects hysteresis and never fires at registration;
/// Threshold, Band and Difference fire on their conditions; bad conditions are rejected.
/datum/unit_test/dq_world_probe_watches

/datum/unit_test/dq_world_probe_watches/Run()
	for(var/cell in 50 to 54)
		world_test_probe_set(cell, 100, 293)
	om_test_ticks(2) // settle the new cells; nothing is asserted on it
	var/datum/world_test_subscriber/changed = allocate(/datum/world_test_subscriber)
	var/datum/world_test_subscriber/hot = allocate(/datum/world_test_subscriber)
	var/datum/world_test_subscriber/band = allocate(/datum/world_test_subscriber)
	var/datum/world_test_subscriber/door = allocate(/datum/world_test_subscriber)
	var/list/watches = list(
		om_world_on_change(changed, WORLD_PROBE(50), CH_BIT(CH_PROBE_PRESSURE), WORLD_TEST_WAKE),
		om_world_when(hot, COND_ABOVE(WORLD_PROBE(51), CH_PROBE_TEMPERATURE, 400), WORLD_TEST_WAKE),
		om_world_when(band, COND_BAND(WORLD_PROBE(52), CH_PROBE_PRESSURE, list(50, 150)), WORLD_TEST_WAKE),
		om_world_when(door, COND_DIFFERENCE(WORLD_PROBE(53), WORLD_PROBE(54), CH_PROBE_PRESSURE, 50), WORLD_TEST_WAKE),
	)
	OM_TEST_WAIT_UNTIL(length(band.wakes) >= 1, 60) // the starting band is the delivery to wait for
	om_test_ticks(3) // the others must stay quiet over the same span
	TEST_ASSERT_EQUAL(length(changed.wakes), 0, "Changed fired at registration")
	TEST_ASSERT_EQUAL(length(hot.wakes), 0, "Threshold fired while below")
	TEST_ASSERT_EQUAL(length(band.wakes), 1, "Band reports its starting band once")
	TEST_ASSERT_EQUAL(length(door.wakes), 0, "Difference fired with no difference")
	world_test_probe_set(50, 100.2, 293) // inside the 0.5 kPa hysteresis
	om_test_ticks(3)
	TEST_ASSERT_EQUAL(length(changed.wakes), 0, "Changed fired inside its hysteresis")
	world_test_probe_set(50, 110, 293)
	world_test_probe_set(51, 100, 500)
	world_test_probe_set(52, 200, 293)
	world_test_probe_set(54, 200, 293)
	OM_TEST_WAIT_UNTIL(length(changed.wakes) >= 1 && length(hot.wakes) >= 1 && length(band.wakes) >= 2 && length(door.wakes) >= 1, 60)
	TEST_ASSERT_EQUAL(length(changed.wakes), 1, "Changed wakes")
	var/list/wake = changed.wakes[1]
	TEST_ASSERT(wake[1] & CH_BIT(CH_PROBE_PRESSURE), "Changed reason [wake[1]] lacks the pressure bit")
	TEST_ASSERT_EQUAL(wake[2], world_test_probe(50), "a watch wake's source is the watched entity")
	TEST_ASSERT_EQUAL(length(hot.wakes), 1, "Threshold wakes")
	wake = hot.wakes[1]
	TEST_ASSERT(wake[1] & WORLD_REASON_CONDITION, "Threshold reason lacks WORLD_REASON_CONDITION")
	TEST_ASSERT_EQUAL(length(band.wakes), 2, "Band wakes on a new band")
	TEST_ASSERT_EQUAL(length(door.wakes), 1, "Difference wakes")
	// Holding steady: nothing more.
	om_test_ticks(3)
	TEST_ASSERT_EQUAL(length(changed.wakes) + length(hot.wakes) + length(band.wakes) + length(door.wakes), 5, "woke while holding steady")
	// Rust rejects a bad channel at registration.
	var/rejected = FALSE
	try
		om_world_when(hot, COND_ABOVE(WORLD_PROBE(51), 9, 1), WORLD_TEST_WAKE)
	catch
		rejected = TRUE
	TEST_ASSERT(rejected, "a condition on a missing channel was accepted")
	for(var/datum/native_watch/W as anything in watches)
		qdel(W)

/// Rate models: exact crossing ticks, reads, input changes and removal.
/datum/unit_test/dq_world_rate_models

/datum/unit_test/dq_world_rate_models/Run()
	var/datum/om/scheduler/sched = GLOB.om_live_sched
	var/datum/world_test_subscriber/S = allocate(/datum/world_test_subscriber)
	om_test_ticks(1)
	var/model = om_rate_linear(0, 10, null, null)
	var/t0 = sched.world_step_tick
	var/per_tick = om_world_per_tick(10)
	var/expected = t0 + CEILING(5 / per_tick, 1)
	var/datum/native_watch/world/high = om_world_on_rate(S, model, WORLD_CMP_ABOVE, 5, WORLD_TEST_WAKE)
	OM_TEST_WAIT_UNTIL(length(S.wakes) >= 1, CEILING(5 / per_tick, 1) + 60)
	om_test_ticks(2)
	TEST_ASSERT_EQUAL(length(S.wakes), 1, "crossing wakes")
	var/list/wake = S.wakes[1]
	TEST_ASSERT(wake[1] & WORLD_REASON_RATE, "reason lacks WORLD_REASON_RATE")
	TEST_ASSERT_EQUAL(wake[2], model, "a rate wake's source is the model")
	TEST_ASSERT(wake[4] >= expected && wake[5] < expected, "crossed at tick [wake[4]] (previous step [wake[5]]), expected the first step at or after [expected]")
	var/now_value = om_rate_read(model)
	TEST_ASSERT(abs(now_value - per_tick * (sched.world_step_tick - t0)) < 0.01, "read [now_value]")
	// Run it backwards: a watch below 1 fires at the new exact crossing.
	om_rate_set_rate(model, -10)
	var/datum/world_test_subscriber/low = allocate(/datum/world_test_subscriber)
	var/datum/native_watch/world/low_watch = om_world_on_rate(low, model, WORLD_CMP_BELOW, 1, WORLD_TEST_WAKE)
	OM_TEST_WAIT_UNTIL(length(low.wakes) >= 1, CEILING(now_value / per_tick, 1) + 60)
	TEST_ASSERT_EQUAL(length(low.wakes), 1, "the re-scheduled crossing did not fire")
	// A sum model: terms add up.
	var/store = om_rate_sum(0, 0, 100)
	om_rate_set_term(store, 1, 20)
	om_rate_set_term(store, 2, -10)
	OM_TEST_WAIT_UNTIL(om_rate_read(store) > 0, 60)
	TEST_ASSERT(om_rate_read(store) > 0, "a sum store with net inflow did not fill")
	var/handle = high.handle
	TEST_ASSERT(om_rate_remove(model), "removing a live model failed")
	TEST_ASSERT(!om_rate_remove(model), "removed a model twice")
	TEST_ASSERT(om_rate_remove(store), "removing the store failed")
	TEST_ASSERT_EQUAL(vg_world_subscriptions(handle), 0, "a removed model kept its watches")
	qdel(high)
	qdel(low_watch)

/// Wakes are counted by owner type (bounded) and reach the profiler and the Rust metrics.
/datum/unit_test/dq_world_diagnostics

/datum/unit_test/dq_world_diagnostics/Run()
	var/datum/om/scheduler/sched = GLOB.om_live_sched
	var/datum/world_test_subscriber/S = allocate(/datum/world_test_subscriber)
	world_test_probe_set(75, 100, 293)
	om_test_ticks(2)
	var/datum/native_watch/world/W = om_world_on_change(S, WORLD_PROBE(75), CH_BIT(CH_PROBE_PRESSURE), WORLD_TEST_WAKE)
	om_test_ticks(2)
	world_test_probe_set(75, 200, 293)
	OM_TEST_WAIT_UNTIL(length(S.wakes) >= 1, 60)
	qdel(W)
	var/list/diagnostics = om_world_diagnostics()
	var/list/by_type = diagnostics["wakes_by_type"]
	TEST_ASSERT(by_type["[S.type]"] >= 1, "the wake is not counted by type")
	TEST_ASSERT(diagnostics["rust"]["wakes_delivered"] >= 1, "Rust wake counts are missing")
	var/list/rust = verdigris_metrics_list()
	TEST_ASSERT(!isnull(rust["world_sched.wakes_delivered"]), "world scheduler metrics are not in verdigris_metrics")
	// Bounded: once full, new types count under "other".
	var/list/saved = sched.world_wakes_by_type
	var/list/full = list()
	for(var/i in 1 to OM_MAX_STAT_TYPES)
		full["filler [i]"] = 1
	sched.world_wakes_by_type = full
	sched.world_count(/datum/unit_test)
	sched.world_wakes_by_type = saved
	TEST_ASSERT(!full[/datum/unit_test], "the wake table grew past its bound")
	TEST_ASSERT(full["other"], "overflow was not counted under other")

/// An owner that watches a probe cell's pressure: the wake-test helper's example.
/datum/world_test_gauge
	var/last_pressure
	var/datum/native_watch/world/watch

CAPABILITIES(/datum/world_test_gauge)
	owns_one(nameof(watch))

/datum/world_test_gauge/New(cell)
	rel_set(src, nameof(watch), om_world_on_change(src, WORLD_PROBE(cell), CH_BIT(CH_PROBE_PRESSURE), PROC_REF(on_pressure)))



/datum/world_test_gauge/proc/on_pressure(datum/native_watch/world/W, reason, source, source_kind)
	last_pressure = source

/datum/unit_test/dq_world_wake_test_helper

/datum/unit_test/dq_world_wake_test_helper/Run()
	world_test_probe_set(60, 100, 293)
	var/datum/world_test_gauge/gauge = allocate(/datum/world_test_gauge, 60)
	var/failure = om_world_wake_test(gauge, deferred_call(null, GLOBAL_PROC_REF(world_test_probe_set), 60, 150, 293))
	TEST_ASSERT(!failure, failure)
	// And the helper catches an owner that misses its input.
	world_test_probe_set(61, 100, 293)
	var/datum/world_test_gauge/deaf = allocate(/datum/world_test_gauge, 61)
	failure = om_world_wake_test(deaf, deferred_call(null, GLOBAL_PROC_REF(world_test_probe_set), 62, 150, 293))
	TEST_ASSERT(findtext(failure, "did not wake"), "the helper passed an owner that missed its input")

#undef WORLD_PROBE

/// Gas is a Rust world domain (M1b): a Threshold on a turf's gas pressure and a
/// Changed on a main-owned mixture wake their owners, and stay quiet while the
/// gas holds steady.
/datum/unit_test/dq_world_gas_watches

/datum/unit_test/dq_world_gas_watches/Run()
	var/turf/open/T
	for(var/turf/simulated/floor/cand in world)
		if(cand.air && !cand.blocks_air && !cand.planetary_atmos && cand.air.arena_id() >= GAS_HANDLE_TURF_BASE)
			T = cand
			break
	TEST_ASSERT_NOTNULL(T, "no floor whose air is a gas field cell")
	// Seal it so the injected gas stays over the threshold for the frame.
	var/turf/open/partner = null
	for(var/turf/open/N as anything in vg_atmos_adjacent_turfs(T))
		partner = N
		break
	TEST_ASSERT_NOTNULL(partner, "the watched floor has no open neighbour")
	dq_atmos_test_isolate_pair(T, partner)
	var/datum/world_test_subscriber/turf_sub = allocate(/datum/world_test_subscriber)
	var/datum/world_test_subscriber/tank_sub = allocate(/datum/world_test_subscriber)
	var/datum/gas_mixture/tank = new(70)
	heat_set(tank, T20C, HEAT_SOURCE_OTHER)
	tank.adjust_gas(/datum/gas/oxygen, 10)
	SSair.run_gas_frames(2)
	var/limit = T.air.return_pressure() + 200
	var/datum/native_watch/world/turf_watch = om_world_when(turf_sub, COND_ABOVE(WORLD_GAS_HANDLE(T.air), CH_GAS_PRESSURE, limit), WORLD_TEST_WAKE, LANE_URGENT)
	var/datum/native_watch/world/tank_watch = om_world_on_change(tank_sub, WORLD_GAS_HANDLE(tank), CH_BIT(CH_GAS_PRESSURE), WORLD_TEST_WAKE, LANE_URGENT)
	SSair.run_gas_frames(2)
	om_test_ticks(3)
	TEST_ASSERT_EQUAL(length(turf_sub.wakes), 0, "turf gas threshold fired while below")
	TEST_ASSERT_EQUAL(length(tank_sub.wakes), 0, "Changed on a tank fired at registration")

	var/datum/gas_mixture/donor = new(70)
	heat_set(donor, T20C, HEAT_SOURCE_OTHER)
	donor.adjust_gas(/datum/gas/nitrogen, 2000)
	T.assume_air(donor)
	tank.adjust_gas(/datum/gas/oxygen, 10)
	SSair.run_gas_frames(1)
	om_test_wait_for(turf_sub, nameof(turf_sub.wakes))
	om_test_wait_for(tank_sub, nameof(tank_sub.wakes))
	TEST_ASSERT(length(turf_sub.wakes) >= 1, "turf gas pressure crossed [limit] kPa ([T.air.return_pressure()]) but the watch did not wake")
	if(length(turf_sub.wakes))
		var/list/wake = turf_sub.wakes[1]
		TEST_ASSERT(wake[1] & WORLD_REASON_CONDITION, "turf gas wake reason [wake[1]] lacks WORLD_REASON_CONDITION")
		TEST_ASSERT_EQUAL(wake[2], T.air.arena_id(), "a gas wake's source is the gas handle")
	TEST_ASSERT(length(tank_sub.wakes) >= 1, "tank pressure changed but its Changed watch did not wake")

	// Put the turf back.
	qdel(turf_watch)
	qdel(tank_watch)
	var/datum/gas_mixture/removed = T.air.remove(2000)
	qdel(removed)
	qdel(tank)
	dq_atmos_test_restore_walls()
	SSair.run_gas_frames(2)

#undef WORLD_TEST_WAKE

#endif
