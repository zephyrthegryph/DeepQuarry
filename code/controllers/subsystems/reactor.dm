/**
 * # SSreactor
 *
 * The one scheduler on the DM side (doc/rewrite/reactor.md). Rust (verdigris/ffi/src/reactor.rs)
 * holds every subscription, the timer wheel, the rate models, the DM-owned keys and the wake
 * lanes; a datum holds only its registry index, `reactor_id`. Each tick this subsystem makes one
 * bind call, `vg_react_step`, and calls `on_react(reason, source, source_kind)` on every
 * subscriber it returns, at most once per lane per tick with the reasons merged. It then runs
 * the continuous lane: declared work (`REACT_EVERY`) scaled by the seconds since its last run.
 *
 * Handlers must never sleep (SHOULD_NOT_SLEEP on the base procs). Handlers must cope with
 * spurious and merged wakes: read the current state, never count wakes.
 */
SUBSYSTEM_DEF(reactor)
	name = "Reactor"
	wait = 1 // SS_TICKER: in ticks. Timers fire at tick precision.
	priority = FIRE_PRIORITY_REACTOR
	flags = SS_TICKER|SS_NO_INIT|SS_KEEP_TIMING
	runlevels = RUNLEVEL_LOBBY|RUNLEVELS_DEFAULT

	/// Registry: reactor_id -> subscriber datum.
	var/list/subscribers = list()
	/// Ids free for reuse.
	var/list/free_ids = list()
	/// Ids released this tick; reusable from the next tick, so a wake already returned for
	/// an id never reaches the datum that inherits it.
	var/list/released_ids = list()

	/// Normal plus background wakes delivered per tick (urgent wakes are never limited).
	var/budget = 2000
	/// This tick's flat wake list from vg_react_step, and where dispatch has reached.
	var/list/pending
	var/pending_index = 1
	/// The wheel tick of the last step, and of the one before it (tests check precision).
	var/step_tick = -1
	var/previous_step_tick = -1

	/// Continuous lane: token (negative) -> /datum/react_every.
	var/list/continuous = list()
	/// reactor_id -> list of its continuous tokens (only for datums that declared any).
	var/list/continuous_by_id = list()
	var/next_continuous_token = 0

	/// Wakes by subscriber type: type -> list(REACT_CLASS_COUNT counts). Bounded by
	/// max_metric_types; later types count under "other".
	var/list/wake_counts = list()
	var/max_metric_types = 256
	/// Continuous-lane cost by type: type -> list(runs, total ms).
	var/list/continuous_cost = list()
	var/total_wakes = 0
	var/last_wakes = 0
	var/last_dispatch_ms = 0
	var/last_continuous_ms = 0
	/// Datums whose on_react() calls are counted (wake tests): datum -> count.
	var/list/traced

	/// Missed-wake audit (reactor.md §7), every `audit_interval` while audit_enabled(): always
	/// under UNIT_TESTS/TESTING (where a finding is a runtime, failing the run), and on servers
	/// only with the `reactor_audit` config flag (off by default; an admin can set it for a round).
	var/audit_interval = 30 SECONDS
	var/next_audit = 0
	var/audit_sample = 64
	var/list/last_audit_findings = list()

/datum/controller/subsystem/reactor/stat_entry(msg)
	msg = "S:[length(subscribers) - length(free_ids) - length(released_ids)] W:[last_wakes] C:[length(continuous)] [round(last_dispatch_ms, 0.01)]ms"
	return ..()

/datum/controller/subsystem/reactor/Recover()
	subscribers = SSreactor.subscribers
	free_ids = SSreactor.free_ids
	released_ids = SSreactor.released_ids
	continuous = SSreactor.continuous
	continuous_by_id = SSreactor.continuous_by_id
	next_continuous_token = SSreactor.next_continuous_token
	wake_counts = SSreactor.wake_counts
	continuous_cost = SSreactor.continuous_cost

/// The wheel tick for world.time `time`: the first tick at or after it.
/datum/controller/subsystem/reactor/proc/tick_of(time)
	return CEILING(time / world.tick_lag, 1)

/datum/controller/subsystem/reactor/fire(resumed)
	if(!resumed)
		if(length(released_ids))
			free_ids += released_ids
			released_ids.Cut()
		var/start = TICK_USAGE_REAL
		previous_step_tick = step_tick
		step_tick = tick_of(world.time)
		pending = vg_react_step(step_tick, budget)
		pending_index = 1
		last_wakes = length(pending) / REACT_WAKE_STRIDE
		last_dispatch_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - start)
	if(!dispatch_pending())
		return
	run_continuous()
	if(audit_interval && world.time >= next_audit && audit_enabled())
		next_audit = world.time + audit_interval
		audit(audit_sample, TRUE)

/// The audit is a test and development tool: on servers it needs the config flag.
/datum/controller/subsystem/reactor/proc/audit_enabled()
#if defined(UNIT_TESTS) || defined(TESTING)
	return TRUE
#else
	return CONFIG_GET(flag/reactor_audit)
#endif

/// Calls on_react() for this tick's wakes. FALSE if it paused (resumed next fire).
/datum/controller/subsystem/reactor/proc/dispatch_pending()
	var/list/wakes = pending
	var/count = length(wakes)
	var/start = TICK_USAGE_REAL
	while(pending_index <= count)
		var/id = wakes[pending_index]
		var/reason = wakes[pending_index + 2]
		var/source = wakes[pending_index + 3]
		var/source_kind = wakes[pending_index + 4]
		pending_index += REACT_WAKE_STRIDE
		var/datum/subscriber = id <= length(subscribers) ? subscribers[id] : null
		if(!subscriber || QDELETED(subscriber))
			continue
		count_wake(subscriber.type, reason)
		if(traced && traced[subscriber])
			traced[subscriber]++
		subscriber.on_react(reason, source, source_kind)
		if(MC_TICK_CHECK)
			last_dispatch_ms += TICK_DELTA_TO_MS(TICK_USAGE_REAL - start)
			return FALSE
	last_dispatch_ms += TICK_DELTA_TO_MS(TICK_USAGE_REAL - start)
	pending = null
	return TRUE

// --- Registry ------------------------------------------------------------------------------

/// Gives `D` a registry index (REACT_ID). Idempotent.
/datum/controller/subsystem/reactor/proc/assign_id(datum/D)
	if(D.reactor_id)
		return D.reactor_id
	var/id
	if(length(free_ids))
		id = free_ids[length(free_ids)]
		free_ids.len--
		subscribers[id] = D
	else
		subscribers += D
		id = length(subscribers)
	D.reactor_id = id
	return id

/// REACT_CLEAR: drops every subscription, timer, pending wake and continuous declaration of
/// `D`, and releases its index.
/datum/controller/subsystem/reactor/proc/clear(datum/D)
	var/id = D.reactor_id
	if(!id)
		return
	vg_react_clear(id)
	var/list/tokens = continuous_by_id["[id]"]
	if(tokens)
		for(var/token in tokens)
			continuous -= "[token]"
		continuous_by_id -= "[id]"
	subscribers[id] = null
	released_ids += id
	D.reactor_id = 0

// --- Subscriptions -------------------------------------------------------------------------

/datum/controller/subsystem/reactor/proc/on_change(datum/D, handle, mask, lane = REACT_LANE_NORMAL)
	return vg_react_watch_changed(REACT_HANDLE_DOMAIN(handle), REACT_ID(D), lane, REACT_HANDLE_CELL(handle), mask)

/// REACT_WHEN: registers a COND_* condition. Rust checks it (channel, unit, levels) and
/// raises a runtime with context if it is invalid.
/datum/controller/subsystem/reactor/proc/when(datum/D, list/condition, lane = REACT_LANE_NORMAL)
	var/id = REACT_ID(D)
	switch(condition[1])
		if(REACT_COND_THRESHOLD)
			var/handle = condition[2]
			return vg_react_watch_threshold(REACT_HANDLE_DOMAIN(handle), id, lane, REACT_HANDLE_CELL(handle), condition[3], condition[4], condition[5], condition[6], condition[7])
		if(REACT_COND_BAND)
			var/handle = condition[2]
			return vg_react_watch_band(REACT_HANDLE_DOMAIN(handle), id, lane, REACT_HANDLE_CELL(handle), condition[3], condition[4], condition[5])
		if(REACT_COND_DIFFERENCE)
			var/handle_a = condition[2]
			var/handle_b = condition[3]
			if(REACT_HANDLE_DOMAIN(handle_a) != REACT_HANDLE_DOMAIN(handle_b))
				CRASH("REACT_WHEN difference across domains")
			return vg_react_watch_difference(REACT_HANDLE_DOMAIN(handle_a), id, lane, REACT_HANDLE_CELL(handle_a), REACT_HANDLE_CELL(handle_b), condition[4], condition[5], condition[6], condition[7], condition[8])
	CRASH("REACT_WHEN: unknown condition [condition[1]]")

/// REACT_AT: wakes `D` (reason REACT_REASON_TIMER, source the returned token) at the first
/// tick at or after world.time `time`.
/datum/controller/subsystem/reactor/proc/at(datum/D, time, lane = REACT_LANE_NORMAL)
	return vg_react_at(REACT_ID(D), lane, tick_of(time))

/datum/controller/subsystem/reactor/proc/on_key(datum/D, kind, id, mask, lane = REACT_LANE_NORMAL)
	return vg_react_on_key(REACT_ID(D), kind, id, mask, lane)

/datum/controller/subsystem/reactor/proc/on_rate(datum/D, model, cmp, level, lane = REACT_LANE_NORMAL)
	return vg_rate_watch(model, REACT_ID(D), lane, cmp, level)

/// REACT_CANCEL. Continuous tokens are negative and live here; the rest live in Rust.
/datum/controller/subsystem/reactor/proc/cancel(datum/D, token)
	if(!isnum(token))
		return FALSE
	if(token < 0)
		var/datum/react_every/entry = continuous["[token]"]
		if(!entry)
			return FALSE
		continuous -= "[token]"
		var/list/tokens = continuous_by_id["[entry.owner_id]"]
		if(tokens)
			tokens -= token
			if(!length(tokens))
				continuous_by_id -= "[entry.owner_id]"
		entry.cancelled = TRUE
		return TRUE
	return !!vg_react_cancel(token)

// --- The continuous lane (reactor.md §2) --------------------------------------------------------

/// One declared continuous process. Few exist, so one datum each is fine.
/datum/react_every
	var/datum/owner
	var/owner_id
	var/period
	var/next_run
	var/last_run
	var/why
	var/token
	var/cancelled = FALSE

/// REACT_EVERY: runs D.react_every(seconds) every `period` deciseconds, where `seconds` is the
/// real time since the last run, until REACT_CANCEL. Returns the (negative) token.
/datum/controller/subsystem/reactor/proc/every(datum/D, period, why)
	if(!istext(why) || !length(why))
		CRASH("REACT_EVERY needs a justification: why is [D.type] continuous?")
	var/datum/react_every/entry = new
	entry.owner = D
	entry.owner_id = REACT_ID(D)
	entry.period = max(period, world.tick_lag)
	entry.last_run = world.time
	entry.next_run = world.time + entry.period
	entry.why = why
	entry.token = --next_continuous_token
	continuous["[entry.token]"] = entry
	LAZYADD(continuous_by_id["[entry.owner_id]"], entry.token)
	return entry.token

/datum/controller/subsystem/reactor/proc/run_continuous()
	var/start = TICK_USAGE_REAL
	for(var/key in continuous.Copy())
		var/datum/react_every/entry = continuous[key]
		if(!entry || entry.cancelled || world.time < entry.next_run)
			continue
		var/datum/owner = entry.owner
		if(QDELETED(owner))
			cancel(owner, entry.token)
			continue
		var/seconds = (world.time - entry.last_run) / (1 SECONDS)
		entry.last_run = world.time
		entry.next_run = world.time + entry.period
		var/before = TICK_USAGE_REAL
		owner.react_every(seconds, entry.token)
		var/list/cost = continuous_cost[owner.type]
		if(!cost)
			if(length(continuous_cost) >= max_metric_types)
				cost = continuous_cost["other"] || (continuous_cost["other"] = list(0, 0))
			else
				cost = continuous_cost[owner.type] = list(0, 0)
		cost[1]++
		cost[2] += TICK_DELTA_TO_MS(TICK_USAGE_REAL - before)
		count_wake(owner.type, 0, REACT_CLASS_EVERY)
	last_continuous_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - start)

// --- Metrics (reactor.md §7) ----------------------------------------------------------------

/datum/controller/subsystem/reactor/proc/count_wake(type, reason, class)
	var/list/counts = wake_counts[type]
	if(!counts)
		if(length(wake_counts) >= max_metric_types)
			counts = wake_counts["other"] || (wake_counts["other"] = new /list(REACT_CLASS_COUNT))
		else
			counts = wake_counts[type] = new /list(REACT_CLASS_COUNT)
	total_wakes++
	if(class)
		counts[class]++
		return
	if(reason & REACT_REASON_CONDITION)
		counts[REACT_CLASS_CONDITION]++
	if(reason & REACT_REASON_TIMER)
		counts[REACT_CLASS_TIMER]++
	if(reason & REACT_REASON_KEY)
		counts[REACT_CLASS_KEY]++
	if(reason & REACT_REASON_RATE)
		counts[REACT_CLASS_RATE]++
	if(!(reason & (REACT_REASON_CONDITION|REACT_REASON_TIMER|REACT_REASON_KEY|REACT_REASON_RATE)))
		counts[REACT_CLASS_CHANGED]++

/// Rust-side counters (vg_react_stats) by name.
/datum/controller/subsystem/reactor/proc/rust_stats()
	var/list/v = vg_react_stats()
	var/static/list/names = list("timers_pending", "timers_fired", "crossings_fired", "publications", "models", "keys", "subscriptions", "wakes_received", "wakes_merged", "wakes_delivered", "wakes_deferred", "watch_wakes", "backlog_urgent", "backlog_normal", "backlog_background", "step_us")
	. = list()
	for(var/i in 1 to min(length(v), length(names)))
		.[names[i]] = v[i]

/// Wakes by type and reason class, continuous-lane cost and declarations, timer counts and
/// dispatch time: what the profiler and the benchmarks read.
/datum/controller/subsystem/reactor/proc/performance_diagnostics()
	var/static/list/class_names = list("changed", "condition", "timer", "key", "rate", "every")
	var/list/by_type = list()
	for(var/type in wake_counts)
		var/list/counts = wake_counts[type]
		var/list/named = list()
		for(var/i in 1 to REACT_CLASS_COUNT)
			if(counts[i])
				named[class_names[i]] = counts[i]
		by_type["[type]"] = named
	var/list/declared = list()
	for(var/key in continuous)
		var/datum/react_every/entry = continuous[key]
		var/list/cost = continuous_cost[entry.owner.type]
		declared += list(list("type" = "[entry.owner.type]", "period_ds" = entry.period, "why" = entry.why, "runs" = cost ? cost[1] : 0, "total_ms" = cost ? cost[2] : 0))
	var/list/continuous_by_type = list()
	for(var/type in continuous_cost)
		var/list/cost = continuous_cost[type]
		continuous_by_type["[type]"] = list("runs" = cost[1], "total_ms" = cost[2])
	return list(
		"subscribers" = length(subscribers) - length(free_ids) - length(released_ids),
		"total_wakes" = total_wakes,
		"last_wakes" = last_wakes,
		"dispatch_ms" = last_dispatch_ms,
		"continuous_ms" = last_continuous_ms,
		"wakes_by_type" = by_type,
		"continuous_declared" = declared,
		"continuous_by_type" = continuous_by_type,
		"rust" = rust_stats(),
	)

// --- Missed-wake audit and wake tests (reactor.md §7) ---------------------------------------------

/// Samples up to `sample` registered subscribers and asks each whether it is sleeping
/// through a change (/datum/proc/react_sleep_violation). Returns the findings as
/// "type: reason" strings; with `report`, logs them (a runtime under UNIT_TESTS/TESTING).
/datum/controller/subsystem/reactor/proc/audit(sample = audit_sample, report = FALSE)
	var/list/findings = list()
	var/count = length(subscribers)
	if(!count)
		return last_audit_findings = findings
	var/list/candidates = list()
	if(count <= sample)
		candidates = subscribers.Copy()
	else
		for(var/i in 1 to sample)
			candidates += subscribers[rand(1, count)]
	for(var/datum/D as anything in candidates)
		if(!D || QDELETED(D))
			continue
		var/violation = D.react_sleep_violation()
		if(!violation)
			continue
		findings += "[D.type]: [violation]"
		if(!report)
			continue
#if defined(UNIT_TESTS) || defined(TESTING)
		stack_trace("REACTOR_AUDIT missed wake: [D.type]: [violation]")
#else
		log_runtime("REACTOR_AUDIT [D.type]: [violation]")
#endif
	return last_audit_findings = findings

/// Starts counting on_react() calls for `D` (wake tests).
/datum/controller/subsystem/reactor/proc/trace(datum/D)
	LAZYINITLIST(traced)
	if(!traced[D])
		traced[D] = 1 // counts are stored +1 so a traced datum is always truthy

/datum/controller/subsystem/reactor/proc/traced_wakes(datum/D)
	if(!traced || !traced[D])
		return 0
	return traced[D] - 1

/datum/controller/subsystem/reactor/proc/untrace(datum/D)
	if(traced)
		traced -= D
		if(!length(traced))
			traced = null

// --- The subscriber side, on every datum ------------------------------------------------------

/datum
	/// SSreactor registry index (0: never subscribed). The only per-datum reactor state.
	var/tmp/reactor_id = 0

/// A subscription fired. `reason` is REACT_REASON_* class bits OR-ed with channel bits (a
/// change watch) or the key's mask (a key); merged wakes carry every reason. `source` is the
/// first reason's source: the cell, the timer's token, the key id (`source_kind` its kind) or
/// the rate model. Read the current state; never count wakes.
/datum/proc/on_react(reason, source, source_kind)
	SHOULD_NOT_SLEEP(TRUE)
	return

/// A continuous-lane run (REACT_EVERY). Scale every effect by `seconds`, the real time since
/// the last run. Cancel with REACT_CANCEL(src, token) once the sleep condition holds.
/datum/proc/react_every(seconds, token)
	SHOULD_NOT_SLEEP(TRUE)
	return

/// For the audit: null while this subscriber's sleep condition holds, or a short text saying
/// why it should be awake. Subscriber types that sleep override it.
/datum/proc/react_sleep_violation()
	SHOULD_NOT_SLEEP(TRUE)
	return null

// --- Mob life hook (reactor.md §6) -------------------------------------------------------------

/**
 * The one place a reactor wake reaches mob Life. A mob's on_react() (or a life system's watch)
 * calls this with the LIFE_SYS_* bits to wake and a short `what` ("gas", "timer", ...).
 * After the body rewrite's wave-4 merge this becomes `life_wake(bits, "reactor:[what]")`;
 * until then it uses the scheduler's current wake().
 */
/mob/living/proc/reactor_wake(bits, what)
	SHOULD_NOT_SLEEP(TRUE)
	wake(bits)
