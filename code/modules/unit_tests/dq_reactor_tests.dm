// Unit tests for SSreactor (doc/rewrite/reactor.md): timers, cancel, merged wakes, once per
// lane per tick, REACT_CLEAR on Destroy, the continuous lane, keys, lane budgets, watches
// through the Rust bind (probe domain), rate models, the audit, metrics and the wake-test helper.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// Waits `ticks` MC ticks (SSreactor fires every tick).
/proc/react_test_ticks(ticks)
	sleep(world.tick_lag * ticks)

/**
 * The reactor wake test (reactor.md §7), for any subscriber type: with its input held steady
 * `D` must stay asleep, and after `change` runs it must wake within `ticks`. Returns null on
 * success or the failure. Settles for `ticks` first (a Band watch reports its starting band).
 */
/proc/react_wake_test(datum/D, datum/callback/change, ticks = 4)
	SSreactor.trace(D)
	react_test_ticks(ticks)
	var/before = SSreactor.traced_wakes(D)
	react_test_ticks(ticks)
	if(SSreactor.traced_wakes(D) != before)
		SSreactor.untrace(D)
		return "[D.type] woke while its input held steady"
	change.Invoke()
	react_test_ticks(ticks)
	var/after = SSreactor.traced_wakes(D)
	SSreactor.untrace(D)
	if(after == before)
		return "[D.type] did not wake after its input changed"
	return null

/// Records every wake: list(reason, source, source_kind, step tick, previous step tick).
/datum/react_test_subscriber
	var/list/wakes = list()
	var/list/every_runs = list()
	var/violation
	/// Continuous lane: accumulate `rate` per second; cancel once `stop_at` is reached.
	var/rate = 10
	var/accumulated = 0
	var/elapsed = 0
	var/stop_at = 0
	/// Re-publish our own key this many times from on_react().
	var/republish = 0

/datum/react_test_subscriber/on_react(reason, source, source_kind)
	wakes += list(list(reason, source, source_kind, SSreactor.step_tick, SSreactor.previous_step_tick))
	if(republish > 0)
		republish--
		REACT_PUBLISH(REACT_KEY_TEST, reactor_id, 1)

/datum/react_test_subscriber/react_every(seconds, token)
	every_runs += seconds
	elapsed += seconds
	accumulated += rate * seconds
	if(stop_at && accumulated >= stop_at)
		REACT_CANCEL(src, token)

/datum/react_test_subscriber/react_sleep_violation()
	return violation

/// Tick-precision timers; cancel; spent tokens.
/datum/unit_test/dq_reactor_timers_fire_at_their_tick

/datum/unit_test/dq_reactor_timers_fire_at_their_tick/Run()
	var/datum/react_test_subscriber/S = allocate(/datum/react_test_subscriber)
	var/datum/react_test_subscriber/cancelled = allocate(/datum/react_test_subscriber)
	var/deadline = world.time + 3 * world.tick_lag
	var/deadline_tick = SSreactor.tick_of(deadline)
	var/token = REACT_AT(S, deadline)
	var/other = REACT_AT(cancelled, deadline)
	TEST_ASSERT(isnum(token) && token >= 0, "REACT_AT returned [token]")
	TEST_ASSERT(REACT_CANCEL(cancelled, other), "cancelling a pending timer failed")
	TEST_ASSERT(!REACT_CANCEL(cancelled, other), "cancelling a timer twice succeeded")
	react_test_ticks(6)
	TEST_ASSERT_EQUAL(length(S.wakes), 1, "timer wakes")
	TEST_ASSERT_EQUAL(length(cancelled.wakes), 0, "a cancelled timer fired")
	var/list/wake = S.wakes[1]
	TEST_ASSERT(wake[1] & REACT_REASON_TIMER, "reason [wake[1]] lacks REACT_REASON_TIMER")
	TEST_ASSERT_EQUAL(wake[2], token, "a timer wake's source is its token")
	TEST_ASSERT(wake[4] >= deadline_tick, "fired at tick [wake[4]], before its tick [deadline_tick]")
	TEST_ASSERT(wake[5] < deadline_tick, "fired at tick [wake[4]], not the first step at or after [deadline_tick] (previous step [wake[5]])")
	TEST_ASSERT(!REACT_CANCEL(S, token), "a fired timer's token was still live")
	TEST_ASSERT_EQUAL(vg_react_subscriptions(S.reactor_id), 0, "a fired timer kept its subscription")
	// A deadline already past fires at the next step.
	REACT_AT(S, world.time - 5 SECONDS)
	react_test_ticks(2)
	TEST_ASSERT_EQUAL(length(S.wakes), 2, "a past deadline did not fire at the next step")

/// Timers, keys and several masks landing in one tick merge into one on_react().
/datum/unit_test/dq_reactor_wakes_merge

/datum/unit_test/dq_reactor_wakes_merge/Run()
	var/datum/react_test_subscriber/S = allocate(/datum/react_test_subscriber)
	var/id = REACT_ID(S)
	REACT_ON_KEY(S, REACT_KEY_TEST, id, 1|2|4)
	var/token = REACT_AT(S, world.time)
	REACT_PUBLISH(REACT_KEY_TEST, id, 1)
	REACT_PUBLISH(REACT_KEY_TEST, id, 4)
	REACT_PUBLISH(REACT_KEY_TEST, id, 1)
	react_test_ticks(4)
	TEST_ASSERT_EQUAL(length(S.wakes), 1, "merged wakes")
	var/list/wake = S.wakes[1]
	var/reason = wake[1]
	TEST_ASSERT(reason & REACT_REASON_TIMER, "merged reason lacks the timer")
	TEST_ASSERT(reason & REACT_REASON_KEY, "merged reason lacks the key")
	TEST_ASSERT_EQUAL(reason & REACT_REASON_DETAIL, 1|4, "merged key mask")
	TEST_ASSERT_EQUAL(wake[2], token, "the first reason (the timer) is the source")

/// A subscriber is woken at most once per lane per tick, even when it re-publishes its own
/// key from on_react().
/datum/unit_test/dq_reactor_once_per_lane_per_tick

/datum/unit_test/dq_reactor_once_per_lane_per_tick/Run()
	var/datum/react_test_subscriber/S = allocate(/datum/react_test_subscriber)
	S.republish = 3
	REACT_ON_KEY(S, REACT_KEY_TEST, REACT_ID(S), 1)
	REACT_PUBLISH(REACT_KEY_TEST, S.reactor_id, 1)
	react_test_ticks(10)
	TEST_ASSERT_EQUAL(length(S.wakes), 4, "one wake per publication round")
	var/list/ticks = list()
	for(var/list/wake as anything in S.wakes)
		TEST_ASSERT(!(wake[4] in ticks), "woken twice in step [wake[4]]")
		ticks += wake[4]

/// Keys: masks filter, cancel works, and a key nobody subscribes to is never stored.
/datum/unit_test/dq_reactor_keys

/datum/unit_test/dq_reactor_keys/Run()
	var/datum/react_test_subscriber/S = allocate(/datum/react_test_subscriber)
	var/datum/react_test_subscriber/owner = allocate(/datum/react_test_subscriber)
	var/key_id = REACT_ID(owner)
	var/token = REACT_ON_KEY(S, REACT_KEY_TEST, key_id, 2)
	REACT_PUBLISH(REACT_KEY_TEST, key_id, 1)
	react_test_ticks(3)
	TEST_ASSERT_EQUAL(length(S.wakes), 0, "woke for a mask it did not subscribe to")
	REACT_PUBLISH(REACT_KEY_TEST, key_id, 2|8)
	react_test_ticks(3)
	TEST_ASSERT_EQUAL(length(S.wakes), 1, "key wakes")
	var/list/wake = S.wakes[1]
	TEST_ASSERT_EQUAL(wake[1] & REACT_REASON_DETAIL, 2, "only the subscribed bits are reported")
	TEST_ASSERT_EQUAL(wake[2], key_id, "a key wake's source is the key id")
	TEST_ASSERT_EQUAL(wake[3], REACT_KEY_TEST, "a key wake's source kind is the key kind")
	var/keys_before = SSreactor.rust_stats()["keys"]
	TEST_ASSERT(REACT_CANCEL(S, token), "cancelling a key subscription failed")
	TEST_ASSERT_EQUAL(SSreactor.rust_stats()["keys"], keys_before - 1, "a key with no subscribers is still stored")
	REACT_PUBLISH(REACT_KEY_TEST, key_id, 2)
	react_test_ticks(3)
	TEST_ASSERT_EQUAL(length(S.wakes), 1, "woke after cancelling")

/// qdel() clears every subscription through the base Destroy().
/datum/unit_test/dq_reactor_clear_on_destroy

/datum/unit_test/dq_reactor_clear_on_destroy/Run()
	var/datum/react_test_subscriber/S = new
	REACT_AT(S, world.time + 2 * world.tick_lag)
	REACT_ON_KEY(S, REACT_KEY_TEST, REACT_ID(S), 1)
	REACT_ON(S, REACT_HANDLE(REACT_DOMAIN_PROBE, 40), CH_BIT(CH_PROBE_PRESSURE))
	var/every = REACT_EVERY(S, 1, "test: clear on destroy")
	var/id = S.reactor_id
	TEST_ASSERT_EQUAL(vg_react_subscriptions(id), 3, "subscriptions before qdel")
	TEST_ASSERT(SSreactor.continuous["[every]"], "continuous declaration missing")
	REACT_PUBLISH(REACT_KEY_TEST, id, 1)
	qdel(S)
	TEST_ASSERT_EQUAL(S.reactor_id, 0, "Destroy() did not release the registry index")
	TEST_ASSERT_EQUAL(vg_react_subscriptions(id), 0, "Destroy() left subscriptions in Rust")
	TEST_ASSERT(!SSreactor.continuous["[every]"], "Destroy() left a continuous declaration")
	vg_react_probe_set(40, 500, 300)
	react_test_ticks(4)
	TEST_ASSERT_EQUAL(length(S.wakes), 0, "a destroyed subscriber was woken")
	TEST_ASSERT_EQUAL(length(S.every_runs), 0, "a destroyed subscriber's continuous work ran")

/// The continuous lane scales by elapsed seconds (so the rate is the same at any period) and
/// cancels itself.
/datum/unit_test/dq_reactor_continuous_lane

/datum/unit_test/dq_reactor_continuous_lane/Run()
	var/datum/react_test_subscriber/fast = allocate(/datum/react_test_subscriber)
	var/datum/react_test_subscriber/slow = allocate(/datum/react_test_subscriber)
	var/datum/react_test_subscriber/stopper = allocate(/datum/react_test_subscriber)
	stopper.stop_at = 3
	var/start = world.time
	REACT_EVERY(fast, world.tick_lag, "test: every tick")
	REACT_EVERY(slow, 5 * world.tick_lag, "test: every five ticks")
	var/stop_token = REACT_EVERY(stopper, world.tick_lag, "test: cancels itself")
	react_test_ticks(20)
	TEST_ASSERT(length(fast.every_runs) >= 10, "fast ran [length(fast.every_runs)] times")
	TEST_ASSERT(length(slow.every_runs) >= 2 && length(slow.every_runs) < length(fast.every_runs), "slow ran [length(slow.every_runs)] times")
	for(var/datum/react_test_subscriber/S as anything in list(fast, slow))
		TEST_ASSERT(abs(S.accumulated - S.rate * S.elapsed) < 0.0001, "[S.accumulated] is not rate x elapsed [S.elapsed]")
		TEST_ASSERT(S.elapsed <= (world.time - start) / (1 SECONDS) + 0.0001, "elapsed [S.elapsed] s exceeds real time")
	// Both saw the same rate: the slow one's elapsed covers its longer periods.
	TEST_ASSERT(slow.elapsed >= 4 * world.tick_lag / (1 SECONDS), "slow elapsed [slow.elapsed] s ignores its period")
	TEST_ASSERT(stopper.accumulated >= 3, "stopper stopped early")
	var/stopper_runs = length(stopper.every_runs)
	TEST_ASSERT(!SSreactor.continuous["[stop_token]"], "self-cancel left the declaration")
	react_test_ticks(4)
	TEST_ASSERT_EQUAL(length(stopper.every_runs), stopper_runs, "ran after cancelling itself")
	var/declared = FALSE
	for(var/list/entry as anything in SSreactor.performance_diagnostics()["continuous_declared"])
		if(entry["why"] == "test: every tick")
			declared = TRUE
	TEST_ASSERT(declared, "the declaration is not in the profiler's report")

/// Urgent wakes ignore the budget; normal wakes spread over ticks within it.
/datum/unit_test/dq_reactor_lane_budget

/datum/unit_test/dq_reactor_lane_budget/Run()
	var/old_budget = SSreactor.budget
	SSreactor.budget = 2
	var/datum/react_test_subscriber/owner = allocate(/datum/react_test_subscriber)
	var/key_id = REACT_ID(owner)
	var/list/normal = list()
	for(var/i in 1 to 6)
		var/datum/react_test_subscriber/S = allocate(/datum/react_test_subscriber)
		REACT_ON_KEY(S, REACT_KEY_TEST, key_id, 1)
		normal += S
	var/list/urgent = list()
	for(var/i in 1 to 4)
		var/datum/react_test_subscriber/S = allocate(/datum/react_test_subscriber)
		SSreactor.on_key(S, REACT_KEY_TEST, key_id, 1, REACT_LANE_URGENT)
		urgent += S
	REACT_PUBLISH(REACT_KEY_TEST, key_id, 1)
	react_test_ticks(8)
	SSreactor.budget = old_budget
	var/first_urgent_tick
	for(var/datum/react_test_subscriber/S as anything in urgent)
		TEST_ASSERT_EQUAL(length(S.wakes), 1, "urgent wakes")
		var/list/wake = S.wakes[1]
		if(isnull(first_urgent_tick))
			first_urgent_tick = wake[4]
		TEST_ASSERT_EQUAL(wake[4], first_urgent_tick, "urgent wakes were spread over ticks")
	var/list/per_tick = list()
	for(var/datum/react_test_subscriber/S as anything in normal)
		TEST_ASSERT_EQUAL(length(S.wakes), 1, "normal wakes")
		var/list/wake = S.wakes[1]
		per_tick["[wake[4]]"]++
	TEST_ASSERT(length(per_tick) >= 3, "six normal wakes with a budget of 2 took [length(per_tick)] ticks")
	for(var/tick in per_tick)
		TEST_ASSERT(per_tick[tick] <= 2, "[per_tick[tick]] normal wakes in one tick, over the budget")

/// Watches cross the Rust bind: Changed respects hysteresis and never fires at registration;
/// Threshold, Band and Difference fire on their conditions; bad conditions are rejected.
/datum/unit_test/dq_reactor_probe_watches

/datum/unit_test/dq_reactor_probe_watches/Run()
	for(var/cell in 50 to 54)
		vg_react_probe_set(cell, 100, 293)
	react_test_ticks(2)
	var/datum/react_test_subscriber/changed = allocate(/datum/react_test_subscriber)
	var/datum/react_test_subscriber/hot = allocate(/datum/react_test_subscriber)
	var/datum/react_test_subscriber/band = allocate(/datum/react_test_subscriber)
	var/datum/react_test_subscriber/door = allocate(/datum/react_test_subscriber)
	REACT_ON(changed, REACT_HANDLE(REACT_DOMAIN_PROBE, 50), CH_BIT(CH_PROBE_PRESSURE))
	REACT_WHEN(hot, COND_ABOVE(REACT_HANDLE(REACT_DOMAIN_PROBE, 51), CH_PROBE_TEMPERATURE, 400))
	REACT_WHEN(band, COND_BAND(REACT_HANDLE(REACT_DOMAIN_PROBE, 52), CH_PROBE_PRESSURE, list(50, 150)))
	REACT_WHEN(door, COND_DIFFERENCE(REACT_HANDLE(REACT_DOMAIN_PROBE, 53), REACT_HANDLE(REACT_DOMAIN_PROBE, 54), CH_PROBE_PRESSURE, 50))
	react_test_ticks(3)
	TEST_ASSERT_EQUAL(length(changed.wakes), 0, "Changed fired at registration")
	TEST_ASSERT_EQUAL(length(hot.wakes), 0, "Threshold fired while below")
	TEST_ASSERT_EQUAL(length(band.wakes), 1, "Band reports its starting band once")
	TEST_ASSERT_EQUAL(length(door.wakes), 0, "Difference fired with no difference")
	vg_react_probe_set(50, 100.2, 293) // inside the 0.5 kPa hysteresis
	react_test_ticks(3)
	TEST_ASSERT_EQUAL(length(changed.wakes), 0, "Changed fired inside its hysteresis")
	vg_react_probe_set(50, 110, 293)
	vg_react_probe_set(51, 100, 500)
	vg_react_probe_set(52, 200, 293)
	vg_react_probe_set(54, 200, 293)
	react_test_ticks(3)
	TEST_ASSERT_EQUAL(length(changed.wakes), 1, "Changed wakes")
	var/list/wake = changed.wakes[1]
	TEST_ASSERT(wake[1] & CH_BIT(CH_PROBE_PRESSURE), "Changed reason [wake[1]] lacks the pressure bit")
	TEST_ASSERT_EQUAL(wake[2], 50, "a watch wake's source is the cell")
	TEST_ASSERT_EQUAL(length(hot.wakes), 1, "Threshold wakes")
	wake = hot.wakes[1]
	TEST_ASSERT(wake[1] & REACT_REASON_CONDITION, "Threshold reason lacks REACT_REASON_CONDITION")
	TEST_ASSERT_EQUAL(length(band.wakes), 2, "Band wakes on a new band")
	TEST_ASSERT_EQUAL(length(door.wakes), 1, "Difference wakes")
	// Holding steady: nothing more.
	react_test_ticks(3)
	TEST_ASSERT_EQUAL(length(changed.wakes) + length(hot.wakes) + length(band.wakes) + length(door.wakes), 5, "woke while holding steady")
	// Rust rejects a bad channel at registration.
	var/rejected = FALSE
	try
		REACT_WHEN(hot, COND_ABOVE(REACT_HANDLE(REACT_DOMAIN_PROBE, 51), 9, 1))
	catch
		rejected = TRUE
	TEST_ASSERT(rejected, "a condition on a missing channel was accepted")

/// Rate models: exact crossing ticks, reads, input changes and removal.
/datum/unit_test/dq_reactor_rate_models

/datum/unit_test/dq_reactor_rate_models/Run()
	var/datum/react_test_subscriber/S = allocate(/datum/react_test_subscriber)
	react_test_ticks(1)
	var/model = RATE_LINEAR(0, 10, null, null)
	var/t0 = SSreactor.step_tick
	var/per_tick = REACT_PER_TICK(10)
	var/expected = t0 + CEILING(5 / per_tick, 1)
	REACT_RATE(S, model, REACT_CMP_ABOVE, 5)
	react_test_ticks(CEILING(5 / per_tick, 1) + 3)
	TEST_ASSERT_EQUAL(length(S.wakes), 1, "crossing wakes")
	var/list/wake = S.wakes[1]
	TEST_ASSERT(wake[1] & REACT_REASON_RATE, "reason lacks REACT_REASON_RATE")
	TEST_ASSERT_EQUAL(wake[2], model, "a rate wake's source is the model")
	TEST_ASSERT(wake[4] >= expected && wake[5] < expected, "crossed at tick [wake[4]] (previous step [wake[5]]), expected the first step at or after [expected]")
	var/now_value = RATE_READ(model)
	TEST_ASSERT(abs(now_value - per_tick * (SSreactor.step_tick - t0)) < 0.01, "read [now_value]")
	// Stop it, then run it backwards: a watch below 1 fires at the new exact crossing.
	RATE_SET_RATE(model, -10)
	var/datum/react_test_subscriber/low = allocate(/datum/react_test_subscriber)
	REACT_RATE(low, model, REACT_CMP_BELOW, 1)
	react_test_ticks(CEILING(now_value / per_tick, 1) + 4)
	TEST_ASSERT_EQUAL(length(low.wakes), 1, "the re-scheduled crossing did not fire")
	// A sum model: terms add up.
	var/store = RATE_SUM(0, 0, 100)
	RATE_SET_TERM(store, 1, 20)
	RATE_SET_TERM(store, 2, -10)
	react_test_ticks(4)
	TEST_ASSERT(RATE_READ(store) > 0, "a sum store with net inflow did not fill")
	TEST_ASSERT(RATE_REMOVE(model), "removing a live model failed")
	TEST_ASSERT(!RATE_REMOVE(model), "removed a model twice")
	TEST_ASSERT(RATE_REMOVE(store), "removing the store failed")
	TEST_ASSERT_EQUAL(vg_react_subscriptions(S.reactor_id), 0, "a removed model kept its watches")

/// The audit reports a subscriber sleeping through its input; wake counts are bounded and
/// reach the profiler and the Rust metrics.
/datum/unit_test/dq_reactor_audit_and_metrics

/datum/unit_test/dq_reactor_audit_and_metrics/Run()
	var/datum/react_test_subscriber/S = allocate(/datum/react_test_subscriber)
	REACT_ID(S)
	S.violation = "its input moved while it slept"
	var/list/findings = SSreactor.audit(length(SSreactor.subscribers))
	var/found = FALSE
	for(var/finding in findings)
		if(findtext(finding, "[S.type]"))
			found = TRUE
	TEST_ASSERT(found, "the audit missed a violating sleeper")
	S.violation = null
	REACT_AT(S, world.time)
	react_test_ticks(3)
	var/list/diagnostics = SSreactor.performance_diagnostics()
	var/list/by_type = diagnostics["wakes_by_type"]
	var/list/mine = by_type["[S.type]"]
	TEST_ASSERT(mine && mine["timer"] >= 1, "the timer wake is not counted by type")
	TEST_ASSERT(diagnostics["rust"]["timers_fired"] >= 1, "Rust timer counts are missing")
	var/list/rust = verdigris_metrics_list()
	TEST_ASSERT(!isnull(rust["reactor.timers_fired"]), "reactor metrics are not in verdigris_metrics")
	// Bounded: once full, new types count under "other".
	var/old_max = SSreactor.max_metric_types
	SSreactor.max_metric_types = length(SSreactor.wake_counts)
	SSreactor.count_wake(/datum/unit_test, REACT_REASON_KEY)
	SSreactor.max_metric_types = old_max
	TEST_ASSERT(!SSreactor.wake_counts[/datum/unit_test], "the wake table grew past its bound")
	TEST_ASSERT(SSreactor.wake_counts["other"], "overflow was not counted under other")

/// A subscriber type that watches a probe cell's pressure: the wake-test helper's example.
/datum/react_test_gauge
	var/cell
	var/last_pressure

/datum/react_test_gauge/New(cell)
	src.cell = cell
	REACT_ON(src, REACT_HANDLE(REACT_DOMAIN_PROBE, cell), CH_BIT(CH_PROBE_PRESSURE))

/datum/react_test_gauge/on_react(reason, source, source_kind)
	last_pressure = source

/datum/unit_test/dq_reactor_wake_test_helper

/datum/unit_test/dq_reactor_wake_test_helper/Run()
	vg_react_probe_set(60, 100, 293)
	var/datum/react_test_gauge/gauge = allocate(/datum/react_test_gauge, 60)
	var/failure = react_wake_test(gauge, CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(vg_react_probe_set), 60, 150, 293))
	TEST_ASSERT(!failure, failure)
	// And the helper catches a subscriber that misses its input.
	vg_react_probe_set(61, 100, 293)
	var/datum/react_test_gauge/deaf = allocate(/datum/react_test_gauge, 61)
	failure = react_wake_test(deaf, CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(vg_react_probe_set), 62, 150, 293))
	TEST_ASSERT(findtext(failure, "did not wake"), "the helper passed a subscriber that missed its input")

#endif
