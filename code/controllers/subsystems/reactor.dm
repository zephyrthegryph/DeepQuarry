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
	/// Bound continuous callbacks independently of pending Behaviours.
	var/continuous_budget = 32
	var/continuous_cursor = 0
	var/continuous_last_tick = -1
	/// DM-owned behaviour runtimes with pending work. Kept separate from Rust wakes.
	var/list/pending_behaviour_runtimes = list()
	/// Bound DM work per tick independently of native wake dispatch.
	var/scheduled_budget = 256
	/// Sparse audit set; registering here has no Rust subscription or FFI cost.
	var/list/scheduled_behaviour_runtimes = list()
	/// Behaviour type -> shared wall-clock cadence. One group slice replaces per-owner timers.
	var/list/shared_cadence_groups = list()
	/// Maximum shared-cadence owner callbacks per reactor tick; excess stays queued.
	var/shared_cadence_budget = 64
	var/shared_cadence_cursor = 0
	/// Inclusive scheduled behaviour cost: type -> list(calls, total ms, moving call ms).
	var/list/scheduled_behaviour_cost = list()
	var/scheduled_profile_phase = 0
	/// Bounded, cumulative scheduler diagnostics. A caller may omit elapsed_ms
	/// when timing is sampled; dispatch and deadline counters still include it.
	var/list/scheduler_systems = list()
	var/list/scheduler_totals = list()
	var/list/scheduler_slow_calls = list()
	var/list/scheduler_incidents = list()
	var/list/scheduler_deferrals_by_reason = list()
	var/scheduler_sequence = 0
	var/scheduler_slow_call_ms = 2
	var/scheduler_slow_limit = 32
	var/scheduler_incident_limit = 20
	/// Per-tick child costs are reported inside, never added to, MC subsystem costs.
	var/scheduler_tick_time = -1
	var/list/scheduler_tick_systems = list()
	var/list/scheduler_tick_slow_calls = list()
	var/list/scheduler_tick_deferrals = list()
	var/scheduler_tick_child_ms = 0
	var/pending_runtime_estimated_ms = 0.25
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

	/// Live REACT_KEY_MOB_CHUNK subscriptions made through sleep_on_keys(). Mob movement
	/// skips the turf lookup and the bind call while it is 0 (Q12).
	var/mob_chunk_subscriptions = 0

	/// Missed-wake audit (reactor.md §7), every `audit_interval` while audit_enabled(): always
	/// under UNIT_TESTS/TESTING (where a finding is a runtime, failing the run), and on servers
	/// only with the `reactor_audit` config flag (off by default; an admin can set it for a round).
	var/audit_interval = 30 SECONDS
	var/next_audit = 0
	var/audit_sample = 64
	var/list/last_audit_findings = list()

	/// Live player chunk subscriptions (REACT_KEY_MOB_CHUNK with REACT_CHUNK_PLAYER). A player's move publishes only while this is
	/// non-zero. A subscription dropped by REACT_CLEAR without unsubscribe_player_chunks()
	/// leaves it high, which only costs publishes.
	var/player_chunk_subscriptions = 0

/datum/controller/subsystem/reactor/stat_entry(msg)
	msg = "S:[length(subscribers) - length(free_ids) - length(released_ids)] W:[last_wakes] C:[length(continuous)] B:[length(pending_behaviour_runtimes)] [round(last_dispatch_ms, 0.01)]ms"
	return ..()

/datum/controller/subsystem/reactor/Recover()
	subscribers = SSreactor.subscribers
	free_ids = SSreactor.free_ids
	released_ids = SSreactor.released_ids
	continuous = SSreactor.continuous
	continuous_budget = SSreactor.continuous_budget
	continuous_cursor = SSreactor.continuous_cursor
	continuous_last_tick = SSreactor.continuous_last_tick
	pending_behaviour_runtimes = SSreactor.pending_behaviour_runtimes
	scheduled_behaviour_runtimes = SSreactor.scheduled_behaviour_runtimes
	shared_cadence_groups = SSreactor.shared_cadence_groups
	shared_cadence_budget = SSreactor.shared_cadence_budget
	shared_cadence_cursor = SSreactor.shared_cadence_cursor
	scheduled_behaviour_cost = SSreactor.scheduled_behaviour_cost
	scheduled_profile_phase = SSreactor.scheduled_profile_phase
	scheduler_systems = SSreactor.scheduler_systems
	scheduler_totals = SSreactor.scheduler_totals
	scheduler_slow_calls = SSreactor.scheduler_slow_calls
	scheduler_incidents = SSreactor.scheduler_incidents
	scheduler_deferrals_by_reason = SSreactor.scheduler_deferrals_by_reason
	scheduler_sequence = SSreactor.scheduler_sequence
	scheduler_tick_time = SSreactor.scheduler_tick_time
	scheduler_tick_systems = SSreactor.scheduler_tick_systems
	scheduler_tick_slow_calls = SSreactor.scheduler_tick_slow_calls
	scheduler_tick_deferrals = SSreactor.scheduler_tick_deferrals
	scheduler_tick_child_ms = SSreactor.scheduler_tick_child_ms
	pending_runtime_estimated_ms = SSreactor.pending_runtime_estimated_ms
	continuous_by_id = SSreactor.continuous_by_id
	next_continuous_token = SSreactor.next_continuous_token
	wake_counts = SSreactor.wake_counts
	continuous_cost = SSreactor.continuous_cost
	mob_chunk_subscriptions = SSreactor.mob_chunk_subscriptions
	player_chunk_subscriptions = SSreactor.player_chunk_subscriptions

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
	// The continuous lane has its own bound and cursor. Service it before the
	// potentially saturated shared/native/pending queues so it cannot starve.
	if(continuous_last_tick != world.time)
		continuous_last_tick = world.time
		run_continuous()
	// Shared cadence is bounded by one bucket per type per tick, independent of
	// the native wake queue's budget and resumptions.
	run_shared_cadences()
	if(!dispatch_pending())
		return
	if(!run_pending_behaviours())
		return
	if(audit_interval && world.time >= next_audit && audit_enabled())
		next_audit = world.time + audit_interval
		audit(audit_sample, TRUE)

/datum/controller/subsystem/reactor/proc/queue_behaviour_runtime(datum/object_model/behaviour_runtime/R)
	if(!R || QDELETED(R) || R.run_queued)
		return
	R.run_queued = TRUE
	pending_behaviour_runtimes += R

/datum/controller/subsystem/reactor/proc/register_scheduled_runtime(datum/object_model/behaviour_runtime/R)
	if(!(R in scheduled_behaviour_runtimes))
		scheduled_behaviour_runtimes += R

/datum/controller/subsystem/reactor/proc/unregister_scheduled_runtime(datum/object_model/behaviour_runtime/R)
	scheduled_behaviour_runtimes -= R

/datum/controller/subsystem/reactor/proc/register_shared_runtime(datum/object_model/behaviour_runtime/R, path)
	var/datum/reactor_shared_cadence/G = shared_cadence_groups[path]
	if(!G)
		var/datum/object_model/behaviour/B = om_behaviour(path)
		G = new(path, B.run_period)
		shared_cadence_groups[path] = G
	G.add(R)

/datum/controller/subsystem/reactor/proc/unregister_shared_runtime(datum/object_model/behaviour_runtime/R, path)
	var/datum/reactor_shared_cadence/G = shared_cadence_groups[path]
	G?.remove(R)

/datum/controller/subsystem/reactor/proc/run_shared_cadences()
	var/group_count = length(shared_cadence_groups)
	if(!group_count)
		return
	for(var/path in shared_cadence_groups)
		var/datum/reactor_shared_cadence/G = shared_cadence_groups[path]
		G.queue_slice(step_tick)
	var/remaining = shared_cadence_budget
	// The group count is small. Order once by declared urgency plus lateness;
	// age eventually promotes work even if a higher-priority group stays busy.
	var/list/ordered = list()
	var/list/scores = list()
	shared_cadence_cursor = (shared_cadence_cursor % group_count) + 1
	for(var/offset in 0 to group_count - 1)
		var/index = ((shared_cadence_cursor + offset - 1) % group_count) + 1
		var/path = shared_cadence_groups[index]
		var/datum/reactor_shared_cadence/G = shared_cadence_groups[path]
		if(!G.pending_count())
			continue
		var/waiting = max(world.time - G.last_served_at, 0)
		var/score = waiting >= 5 SECONDS ? 100000 + waiting : G.priority * 10 + max(world.time - G.oldest_due(), 0) / (1 SECONDS)
		var/insert_at = 1
		while(insert_at <= length(ordered) && scores[insert_at] >= score)
			insert_at++
		ordered.Insert(insert_at, path)
		scores.Insert(insert_at, score)
	for(var/path in ordered)
		if(remaining <= 0 || TICK_USAGE >= Master.current_ticklimit)
			break
		var/datum/reactor_shared_cadence/G = shared_cadence_groups[path]
		var/cost_ms = estimated_scheduled_cost(path, G.cost_hint_ms)
		var/available_ms = TICK_DELTA_TO_MS(max(Master.current_ticklimit - TICK_USAGE, 0))
		var/cost_quota = max(round((available_ms - 0.25) / max(cost_ms, 0.01)), 0)
		if(!cost_quota)
			if(remaining == shared_cadence_budget && available_ms > 0.25)
				cost_quota = 1 // preserve progress when the estimate exceeds one slice
			else
				break
		remaining -= G.drain(min(remaining, cost_quota))
	var/deferred = 0
	for(var/path in shared_cadence_groups)
		var/datum/reactor_shared_cadence/G = shared_cadence_groups[path]
		deferred += G.pending_count()
	if(deferred)
		record_scheduler_deferral(TICK_USAGE >= Master.current_ticklimit ? "tick_budget" : "shared_cadence_budget", deferred)

/datum/controller/subsystem/reactor/proc/estimated_scheduled_cost(path, hint = 0.1)
	// This is inclusive on_run cost. The generic telemetry row is exclusive of
	// nested Life calls and cannot predict how long the owner occupies the tick.
	var/list/cost = scheduled_behaviour_cost[path]
	return max(cost && cost[1] ? cost[3] : hint, 0.01)

/// One bucket is visited per reactor tick; all owners of a type share this cadence.
/datum/reactor_shared_cadence
	var/behaviour_path
	var/slot_count
	var/list/buckets
	var/list/member_slots = list()
	/// FIFO of bucket indices still due, with a resumable cursor for each bucket.
	var/list/due_slots = list()
	var/list/slot_queued
	var/list/slot_cursors
	var/list/slot_due
	var/next_join_slot = 1
	var/last_tick = -1
	var/priority = 0
	var/cost_hint_ms = 0.1
	var/last_served_at = 0

/datum/reactor_shared_cadence/New(path, period)
	..()
	behaviour_path = path
	slot_count = max(1, CEILING(period / world.tick_lag, 1))
	buckets = list()
	buckets.len = slot_count
	slot_queued = list()
	slot_queued.len = slot_count
	slot_cursors = list()
	slot_cursors.len = slot_count
	slot_due = list()
	slot_due.len = slot_count
	var/datum/object_model/behaviour/B = om_behaviour(path)
	priority = B?.run_priority || 0
	cost_hint_ms = B?.run_cost_hint_ms || 0.1
	last_served_at = world.time

/datum/reactor_shared_cadence/proc/add(datum/object_model/behaviour_runtime/R)
	if(R in member_slots)
		return
	var/slot = next_join_slot
	next_join_slot = (slot % slot_count) + 1
	if(!buckets[slot])
		buckets[slot] = list()
	var/list/bucket = buckets[slot]
	bucket += R
	member_slots[R] = slot

/datum/reactor_shared_cadence/proc/remove(datum/object_model/behaviour_runtime/R)
	var/slot = member_slots[R]
	if(!slot)
		return
	var/list/bucket = buckets[slot]
	var/index = bucket.Find(R)
	bucket -= R
	if(slot_queued[slot] && index && index < slot_cursors[slot])
		slot_cursors[slot]--
	member_slots -= R

/datum/reactor_shared_cadence/proc/queue_slice(tick)
	if(tick <= last_tick)
		return
	last_tick = tick
	var/slot = (tick % slot_count) + 1
	if(!length(buckets[slot]) || slot_queued[slot])
		return
	slot_queued[slot] = TRUE
	slot_cursors[slot] = 1
	slot_due[slot] = world.time
	due_slots += slot

/datum/reactor_shared_cadence/proc/pending_count()
	var/total = 0
	for(var/slot in due_slots)
		var/list/bucket = buckets[slot]
		total += max(length(bucket) - slot_cursors[slot] + 1, 0)
	return total

/datum/reactor_shared_cadence/proc/oldest_due()
	return length(due_slots) ? slot_due[due_slots[1]] : world.time

/datum/reactor_shared_cadence/proc/drain(quota)
	var/processed = 0
	while(processed < quota && length(due_slots))
		if(TICK_USAGE >= Master.current_ticklimit)
			break
		var/slot = due_slots[1]
		var/list/bucket = buckets[slot]
		var/index = slot_cursors[slot]
		if(index > length(bucket))
			due_slots.Cut(1, 2)
			slot_queued[slot] = FALSE
			slot_cursors[slot] = null
			slot_due[slot] = null
			continue
		var/datum/object_model/behaviour_runtime/R = bucket[index]
		slot_cursors[slot] = index + 1
		processed++
		if(!QDELETED(R))
			R.run_shared_frame(behaviour_path, slot_due[slot])
			last_served_at = world.time
	return processed

/datum/controller/subsystem/reactor/proc/record_scheduled_cost(behaviour_type, elapsed)
	var/list/cost = scheduled_behaviour_cost[behaviour_type]
	if(!cost)
		if(length(scheduled_behaviour_cost) >= max_metric_types)
			cost = scheduled_behaviour_cost["other"] || (scheduled_behaviour_cost["other"] = list(0, 0, 0))
		else
			cost = scheduled_behaviour_cost[behaviour_type] = list(0, 0, 0)
	var/ms = max(TICK_DELTA_TO_MS(elapsed), 0)
	cost[1]++
	cost[2] += ms
	cost[3] = cost[1] == 1 || isnull(cost[3]) ? ms : cost[3] * 0.875 + ms * 0.125

/// Reset the short-lived attribution data at the first observed dispatch in a tick.
/datum/controller/subsystem/reactor/proc/prepare_scheduler_tick()
	if(scheduler_tick_time == world.time)
		return
	scheduler_tick_time = world.time
	scheduler_tick_systems.Cut()
	scheduler_tick_slow_calls.Cut()
	scheduler_tick_deferrals.Cut()
	scheduler_tick_child_ms = 0

/// One callback observation. `scheduled_at` and `started_at` are world-time
/// deciseconds; null scheduled_at means event-driven work without a deadline.
/// Costs nested inside another callback are recorded by the child. Reactor
/// wrappers subtract observed child cost before calling here.
/datum/controller/subsystem/reactor/proc/observe_dispatch(kind, system_type, entity_type, scheduled_at, started_at, elapsed_ms, reason, work_units = 1, priority = 0)
	prepare_scheduler_tick()
	var/key = "[kind]|[system_type]"
	var/list/row = scheduler_systems[key]
	if(!row)
		if(length(scheduler_systems) >= max_metric_types)
			key = "other"
			row = scheduler_systems[key]
		if(!row)
			row = list("kind" = kind, "system_type" = "[system_type]", "calls" = 0, "sampled_calls" = 0, "sampled_total_ms" = 0, "max_call_ms" = 0, "slow_calls" = 0, "deadline_misses" = 0, "max_lateness_ds" = 0, "work_units" = 0, "estimated_ms" = 0, "max_lateness_limit_ds" = 0)
			if(kind == "behaviour")
				var/datum/object_model/behaviour/B = om_behaviour(system_type)
				row["max_lateness_limit_ds"] = B?.run_max_lateness || 0
				row["estimated_ms"] = B?.run_cost_hint_ms || 0
			else if(kind == "life")
				var/datum/life_system/S = get_life_system(system_type)
				row["system_path"] = system_type
				row["max_lateness_limit_ds"] = S?.run_max_lateness || 0
				row["estimated_ms"] = S?.run_cost_hint_ms || 0
			scheduler_systems[key] = row
	row["calls"]++
	row["work_units"] += max(work_units, 0)
	if(!scheduler_totals.len)
		scheduler_totals = list("calls" = 0, "sampled_calls" = 0, "sampled_total_ms" = 0, "slow_calls" = 0, "deadline_misses" = 0, "deferred_budget" = 0, "deferred_tick" = 0)
	scheduler_totals["calls"]++
	var/lateness = isnull(scheduled_at) ? 0 : max(started_at - scheduled_at, 0)
	row["max_lateness_ds"] = max(row["max_lateness_ds"], lateness)
	var/limit = row["max_lateness_limit_ds"]
	if(limit > 0 && lateness > limit)
		row["deadline_misses"]++
		scheduler_totals["deadline_misses"]++
	if(isnull(elapsed_ms))
		return
	elapsed_ms = max(elapsed_ms, 0)
	// A regular Life frame may legitimately cost several milliseconds. Compare
	// against its established inclusive cost before updating this sample, so
	// one ordinary expensive callback cannot flood the slow-call ring.
	var/expected_ms = row["estimated_ms"] || 0
	if(kind == "behaviour")
		var/datum/object_model/behaviour/B = om_behaviour(system_type)
		var/hint_ms = B?.run_cost_hint_ms || 0.1
		expected_ms = max(expected_ms, hint_ms, estimated_scheduled_cost(system_type, hint_ms))
	var/slow_limit_ms = max(scheduler_slow_call_ms, expected_ms * 3)
	row["sampled_calls"]++
	row["sampled_total_ms"] += elapsed_ms
	row["max_call_ms"] = max(row["max_call_ms"], elapsed_ms)
	row["estimated_ms"] = row["sampled_calls"] == 1 ? elapsed_ms : (row["estimated_ms"] * 0.875 + elapsed_ms * 0.125)
	scheduler_totals["sampled_calls"]++
	scheduler_totals["sampled_total_ms"] += elapsed_ms
	scheduler_tick_child_ms += elapsed_ms
	var/list/tick_row = scheduler_tick_systems[key]
	if(!tick_row)
		tick_row = list("kind" = kind, "system_type" = "[system_type]", "calls" = 0, "ms" = 0, "max_call_ms" = 0)
		scheduler_tick_systems[key] = tick_row
	tick_row["calls"]++
	tick_row["ms"] += elapsed_ms
	tick_row["max_call_ms"] = max(tick_row["max_call_ms"], elapsed_ms)
	if(elapsed_ms < slow_limit_ms)
		return
	row["slow_calls"]++
	scheduler_totals["slow_calls"]++
	var/list/slow = list("sequence" = ++scheduler_sequence, "world_time" = world.time, "kind" = kind, "system_type" = "[system_type]", "entity_type" = "[entity_type]", "elapsed_ms" = elapsed_ms, "slow_limit_ms" = slow_limit_ms, "expected_ms" = expected_ms, "lateness_ds" = lateness, "reason" = "[reason]", "priority" = priority)
	scheduler_slow_calls += list(slow)
	scheduler_tick_slow_calls += list(slow)
	if(length(scheduler_slow_calls) > scheduler_slow_limit)
		scheduler_slow_calls.Cut(1, length(scheduler_slow_calls) - scheduler_slow_limit + 1)
	if(length(scheduler_tick_slow_calls) > scheduler_slow_limit)
		scheduler_tick_slow_calls.Cut(1, length(scheduler_tick_slow_calls) - scheduler_slow_limit + 1)

/// Records a reason when due work remains after the current reactor pass.
/datum/controller/subsystem/reactor/proc/record_scheduler_deferral(reason, count)
	if(count <= 0)
		return
	prepare_scheduler_tick()
	if(!scheduler_totals.len)
		scheduler_totals = list("calls" = 0, "sampled_calls" = 0, "sampled_total_ms" = 0, "slow_calls" = 0, "deadline_misses" = 0, "deferred_budget" = 0, "deferred_tick" = 0)
	scheduler_deferrals_by_reason[reason] = (scheduler_deferrals_by_reason[reason] || 0) + count
	scheduler_tick_deferrals[reason] = (scheduler_tick_deferrals[reason] || 0) + count
	if(reason == "tick_budget")
		scheduler_totals["deferred_tick"] += count
	else
		scheduler_totals["deferred_budget"] += count

/// MC calls this only for an overrun. Scheduler rows sit under their parent
/// subsystem in the incident; they are not summed into MC's flat breakdown.
/datum/controller/subsystem/reactor/proc/record_scheduler_incident(usage, list/subsystems, unattributed_usage)
	var/list/top = list()
	if(scheduler_tick_time == world.time)
		for(var/key in scheduler_tick_systems)
			var/list/row = scheduler_tick_systems[key]
			var/index = 1
			while(index <= length(top))
				var/list/other = top[index]
				if(other["ms"] < row["ms"])
					break
				index++
			if(index > 12)
				continue
			top.Insert(index, list(row.Copy()))
			if(length(top) > 12)
				top.Cut(13)
	var/list/incident = list("sequence" = ++scheduler_sequence, "world_time" = world.time, "usage" = usage, "overrun" = max(usage - 100, 0), "subsystems" = subsystems.Copy(), "scheduler_systems" = top, "slow_calls" = scheduler_tick_slow_calls.Copy(), "deferrals" = scheduler_tick_deferrals.Copy(), "pending" = scheduler_pending_counts(), "unattributed_usage" = unattributed_usage)
	scheduler_incidents += list(incident)
	if(length(scheduler_incidents) > scheduler_incident_limit)
		scheduler_incidents.Cut(1, length(scheduler_incidents) - scheduler_incident_limit + 1)
	return incident

/datum/controller/subsystem/reactor/proc/scheduler_pending_counts()
	var/shared = 0
	var/oldest = world.time
	for(var/path in shared_cadence_groups)
		var/datum/reactor_shared_cadence/G = shared_cadence_groups[path]
		shared += G.pending_count()
		if(G.pending_count())
			oldest = min(oldest, G.oldest_due())
	for(var/datum/object_model/behaviour_runtime/R as anything in pending_behaviour_runtimes)
		if(!QDELETED(R))
			oldest = min(oldest, R.queue_oldest_at())
	return list("native_wakes" = max((length(pending) - pending_index + 1) / REACT_WAKE_STRIDE, 0), "behaviour_runtimes" = length(pending_behaviour_runtimes), "shared_cadence" = shared, "oldest_lateness_ds" = max(world.time - oldest, 0))

/// Snapshot for admin diagnostics, benchmark windows and external reports.
/datum/controller/subsystem/reactor/proc/performance_scheduler_diagnostics()
	var/list/systems = list()
	var/list/totals = scheduler_totals.Copy()
	for(var/key in scheduler_systems)
		var/list/row = scheduler_systems[key]
		var/list/snapshot = row.Copy()
		if(row["kind"] == "life" && key != "other")
			var/datum/life_system/S = get_life_system(row["system_path"])
			var/exact_calls = S?.telemetry_calls || 0
			totals["calls"] = (totals["calls"] || 0) + exact_calls - row["calls"]
			snapshot["calls"] = exact_calls
			snapshot["work_units"] = exact_calls
		snapshot -= "system_path" // keep the exported record JSON-friendly
		systems[key] = snapshot
	return list("sequence" = scheduler_sequence, "totals" = totals, "systems" = systems, "slow_calls" = scheduler_slow_calls.Copy(), "incidents" = scheduler_incidents.Copy(), "pending" = scheduler_pending_counts(), "deferrals_by_reason" = scheduler_deferrals_by_reason.Copy())

/// On-demand live view; sorting is deliberately kept out of the hot dispatch path.
ADMIN_VERB(debug_scheduler_performance, R_DEBUG, "Scheduler Diagnostics", "Shows slow systems, queue age, and recent tick overruns.", ADMIN_CATEGORY_DEBUG_INVESTIGATE)
	var/list/diagnostics = SSreactor.performance_scheduler_diagnostics()
	var/list/systems = diagnostics["systems"]
	var/list/top = list()
	for(var/key in systems)
		var/list/row = systems[key]
		if(!row["sampled_calls"])
			continue
		var/score = row["estimated_ms"]
		var/index = 1
		while(index <= length(top))
			var/list/other = systems[top[index]]
			if(other["estimated_ms"] < score)
				break
			index++
		if(index > 10)
			continue
		top.Insert(index, key)
		if(length(top) > 10)
			top.Cut(11)
	var/list/pending_counts = diagnostics["pending"]
	to_chat(user, span_notice("Scheduler: [pending_counts["native_wakes"]] native wakes, [pending_counts["behaviour_runtimes"]] behaviour runtimes, [pending_counts["shared_cadence"]] shared callbacks pending; oldest [round(pending_counts["oldest_lateness_ds"] / (1 SECONDS), 0.1)]s late."))
	to_chat(user, span_notice("Slow systems (moving ms/call | worst ms | calls | deadline misses):"))
	for(var/key in top)
		var/list/row = systems[key]
		to_chat(user, span_notice("[key]: [round(row["estimated_ms"], 0.01)] | [round(row["max_call_ms"], 0.01)] | [row["calls"]] | [row["deadline_misses"]]"))
	var/list/incidents = diagnostics["incidents"]
	to_chat(user, span_notice("Recent overruns: [length(incidents)] retained."))
	for(var/index = max(1, length(incidents) - 4); index <= length(incidents); index++)
		var/list/incident = incidents[index]
		var/list/contributors = incident["scheduler_systems"]
		var/list/lead = length(contributors) ? contributors[1] : null
		to_chat(user, span_notice("Tick [incident["world_time"]]: [round(incident["usage"], 0.1)]% used; leading measured scheduler work [lead ? "[lead["system_type"]] [round(lead["ms"], 0.01)]ms" : "none"]; outside subsystem accounting [round(incident["unattributed_usage"], 0.1)]%."))

/// Run once per queued owner; repeated writes before dispatch merge in its runtime.
/datum/controller/subsystem/reactor/proc/select_pending_behaviour_index(start_index, scan_limit = 32)
	var/end_index = min(length(pending_behaviour_runtimes), start_index + scan_limit - 1)
	var/best_index = start_index
	var/best_score = -1000000000
	for(var/index in start_index to end_index)
		var/datum/object_model/behaviour_runtime/R = pending_behaviour_runtimes[index]
		if(!R || QDELETED(R))
			continue
		var/waiting = max(world.time - R.queue_oldest_at(), 0)
		var/score = waiting >= 5 SECONDS ? 100000 + waiting : R.queue_priority() * 10 + waiting / (1 SECONDS)
		if(score > best_score)
			best_score = score
			best_index = index
	return best_index

/datum/controller/subsystem/reactor/proc/run_pending_behaviours()
	// Wakes raised by on_run() are handled on the next tick, not recursively.
	var/to_process = min(length(pending_behaviour_runtimes), scheduled_budget)
	var/processed = 0
	while(processed < to_process)
		var/available_ms = TICK_DELTA_TO_MS(max(Master.current_ticklimit - TICK_USAGE, 0))
		if(TICK_USAGE >= Master.current_ticklimit || (processed && available_ms < pending_runtime_estimated_ms + 0.25))
			break
		var/next_index = processed + 1
		var/chosen_index = select_pending_behaviour_index(next_index)
		if(chosen_index != next_index)
			pending_behaviour_runtimes.Swap(next_index, chosen_index)
		var/datum/object_model/behaviour_runtime/R = pending_behaviour_runtimes[++processed]
		if(!R || QDELETED(R))
			continue
		R.run_queued = FALSE
		var/before = TICK_USAGE_REAL
		R.run_ready()
		var/elapsed_ms = max(TICK_DELTA_TO_MS(TICK_USAGE_REAL - before), 0)
		pending_runtime_estimated_ms = pending_runtime_estimated_ms * 0.875 + elapsed_ms * 0.125
	if(processed)
		pending_behaviour_runtimes.Cut(1, processed + 1)
	if(length(pending_behaviour_runtimes))
		record_scheduler_deferral(TICK_USAGE >= Master.current_ticklimit ? "tick_budget" : "pending_behaviour_budget", length(pending_behaviour_runtimes))
	return processed == to_process

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
		prepare_scheduler_tick()
		var/child_before = scheduler_tick_child_ms
		var/wake_start = world.time
		var/wake_usage = TICK_USAGE_REAL
		subscriber.on_react(reason, source, source_kind)
		var/wake_ms = max(TICK_DELTA_TO_MS(TICK_USAGE_REAL - wake_usage) - (scheduler_tick_child_ms - child_before), 0)
		observe_dispatch("reactor_wake", subscriber.type, subscriber.type, null, wake_start, wake_ms, reason)
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

// --- Sleeping on keys (S2) -------------------------------------------------------------------

/// Subscribes `D` to every (kind, id, mask) triple in the flat list `keys`. Returns the flat
/// list (token, kind, ...) to hand back to cancel_keys() when `D` wakes.
/datum/controller/subsystem/reactor/proc/sleep_on_keys(datum/D, list/keys)
	. = list()
	for(var/i = 1; i <= length(keys); i += 3)
		var/kind = keys[i]
		. += on_key(D, kind, keys[i + 1], keys[i + 2])
		. += kind
		if(kind == REACT_KEY_MOB_CHUNK) // any-mob subscribers; players use subscribe_player_chunks()
			mob_chunk_subscriptions++

/// Drops the subscriptions sleep_on_keys() returned.
/datum/controller/subsystem/reactor/proc/cancel_keys(datum/D, list/tokens)
	for(var/i = 1; i <= length(tokens); i += 2)
		cancel(D, tokens[i])
		if(tokens[i + 1] == REACT_KEY_MOB_CHUNK)
			mob_chunk_subscriptions = max(mob_chunk_subscriptions - 1, 0)

/// The mob-chunk key for a location, or null off-map.
/datum/controller/subsystem/reactor/proc/mob_chunk_id(atom/location)
	var/turf/T = get_turf(location)
	if(!T)
		return
	return MOB_CHUNK_NUMERIC_KEY(T.z, MOB_CHUNK_COORD(T.x), MOB_CHUNK_COORD(T.y))

/// A mob appeared in or vanished from `location`'s chunk (Initialize, Destroy).
/datum/controller/subsystem/reactor/proc/publish_mob_chunk(atom/location)
	if(!mob_chunk_subscriptions)
		return
	var/id = mob_chunk_id(location)
	if(!isnull(id))
		REACT_PUBLISH(REACT_KEY_MOB_CHUNK, id, REACT_CHUNK_ANY_MOB)

// --- Player chunk keys (Q5) ---------------------------------------------------------------

/// Subscribes `D` to players (REACT_KEY_MOB_CHUNK, REACT_CHUNK_PLAYER) in every chunk within `radius` tiles of `center`.
/// Returns the tokens, for unsubscribe_player_chunks().
/datum/controller/subsystem/reactor/proc/subscribe_player_chunks(datum/D, turf/center, radius)
	. = list()
	if(!center)
		return
	var/min_x = MOB_CHUNK_COORD(max(center.x - radius, 1))
	var/max_x = MOB_CHUNK_COORD(min(center.x + radius, world.maxx))
	var/min_y = MOB_CHUNK_COORD(max(center.y - radius, 1))
	var/max_y = MOB_CHUNK_COORD(min(center.y + radius, world.maxy))
	for(var/chunk_x in min_x to max_x)
		for(var/chunk_y in min_y to max_y)
			. += on_key(D, REACT_KEY_MOB_CHUNK, MOB_CHUNK_NUMERIC_KEY(center.z, chunk_x, chunk_y), REACT_CHUNK_PLAYER)
	player_chunk_subscriptions += length(.)

/// Drops tokens from subscribe_player_chunks(). Returns null, for `tokens = unsubscribe_player_chunks(...)`.
/datum/controller/subsystem/reactor/proc/unsubscribe_player_chunks(datum/D, list/tokens)
	for(var/token in tokens)
		if(cancel(D, token))
			player_chunk_subscriptions = max(player_chunk_subscriptions - 1, 0)
	return null

/// A player is in `T`'s chunk. Callers check player_chunk_subscriptions first.
/datum/controller/subsystem/reactor/proc/publish_player_chunk(turf/T)
	if(T)
		REACT_PUBLISH(REACT_KEY_MOB_CHUNK, MOB_CHUNK_NUMERIC_KEY(T.z, MOB_CHUNK_COORD(T.x), MOB_CHUNK_COORD(T.y)), REACT_CHUNK_PLAYER)

/**
 * /mob/Moved()'s one publish. The new chunk hears REACT_CHUNK_ANY_MOB (while anything sleeps on
 * it) plus REACT_CHUNK_PLAYER for a player (while anything listens for players). The old chunk
 * hears REACT_CHUNK_ANY_MOB only when the step crossed a chunk edge: a step inside one chunk
 * needs one publish. Callers gate on the two counters first (Q12).
 */
/datum/controller/subsystem/reactor/proc/publish_mob_move(atom/old_loc, atom/movable/mover, player)
	var/mask = mob_chunk_subscriptions ? REACT_CHUNK_ANY_MOB : 0
	if(player && player_chunk_subscriptions)
		mask |= REACT_CHUNK_PLAYER
	if(!mask)
		return
	var/turf/old_turf = get_turf(old_loc)
	var/turf/new_turf = get_turf(mover)
	var/new_id = new_turf ? MOB_CHUNK_NUMERIC_KEY(new_turf.z, MOB_CHUNK_COORD(new_turf.x), MOB_CHUNK_COORD(new_turf.y)) : null
	if(!isnull(new_id))
		REACT_PUBLISH(REACT_KEY_MOB_CHUNK, new_id, mask)
	if(old_turf && (mask & REACT_CHUNK_ANY_MOB))
		var/old_id = MOB_CHUNK_NUMERIC_KEY(old_turf.z, MOB_CHUNK_COORD(old_turf.x), MOB_CHUNK_COORD(old_turf.y))
		if(old_id != new_id)
			REACT_PUBLISH(REACT_KEY_MOB_CHUNK, old_id, REACT_CHUNK_ANY_MOB)

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
	var/list/keys = list()
	for(var/key in continuous)
		keys += key
	var/key_count = length(keys)
	if(!key_count)
		last_continuous_ms = 0
		return
	var/start_index = (continuous_cursor % key_count) + 1
	var/processed = 0
	for(var/offset in 0 to key_count - 1)
		if(processed >= continuous_budget || TICK_USAGE >= Master.current_ticklimit)
			break
		var/index = ((start_index + offset - 1) % key_count) + 1
		continuous_cursor = index
		var/key = keys[index]
		var/datum/react_every/entry = continuous[key]
		if(!entry || entry.cancelled || world.time < entry.next_run)
			continue
		var/datum/owner = entry.owner
		if(QDELETED(owner))
			cancel(owner, entry.token)
			continue
		processed++
		var/seconds = (world.time - entry.last_run) / (1 SECONDS)
		entry.last_run = world.time
		entry.next_run = world.time + entry.period
		prepare_scheduler_tick()
		var/child_before = scheduler_tick_child_ms
		var/run_start = world.time
		var/before = TICK_USAGE_REAL
		owner.react_every(seconds, entry.token)
		var/exclusive_ms = max(TICK_DELTA_TO_MS(TICK_USAGE_REAL - before) - (scheduler_tick_child_ms - child_before), 0)
		observe_dispatch("reactor_every", owner.type, owner.type, null, run_start, exclusive_ms, entry.why)
		var/list/cost = continuous_cost[owner.type]
		if(!cost)
			if(length(continuous_cost) >= max_metric_types)
				cost = continuous_cost["other"] || (continuous_cost["other"] = list(0, 0))
			else
				cost = continuous_cost[owner.type] = list(0, 0)
		cost[1]++
		cost[2] += TICK_DELTA_TO_MS(TICK_USAGE_REAL - before)
		count_wake(owner.type, 0, REACT_CLASS_EVERY)
	var/deferred = 0
	for(var/key in continuous)
		var/datum/react_every/entry = continuous[key]
		if(entry && !entry.cancelled && world.time >= entry.next_run)
			deferred++
	if(deferred)
		record_scheduler_deferral(TICK_USAGE >= Master.current_ticklimit ? "tick_budget" : "continuous_budget", deferred)
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
	var/list/scheduled_by_type = list()
	for(var/type in scheduled_behaviour_cost)
		var/list/cost = scheduled_behaviour_cost[type]
		scheduled_by_type["[type]"] = list("estimated_runs" = cost[1], "estimated_ms" = cost[2], "moving_call_ms" = cost[3])
	return list(
		"subscribers" = length(subscribers) - length(free_ids) - length(released_ids),
		"total_wakes" = total_wakes,
		"last_wakes" = last_wakes,
		"dispatch_ms" = last_dispatch_ms,
		"continuous_ms" = last_continuous_ms,
		"wakes_by_type" = by_type,
		"continuous_declared" = declared,
		"continuous_by_type" = continuous_by_type,
		"scheduled_runtimes" = length(scheduled_behaviour_runtimes),
		"scheduled_pending" = length(pending_behaviour_runtimes),
		"scheduled_by_type" = scheduled_by_type,
		"rust" = rust_stats(),
	)

// --- Missed-wake audit and wake tests (reactor.md §7) ---------------------------------------------

/// Samples up to `sample` registered subscribers and asks each whether it is sleeping
/// through a change (/datum/proc/react_sleep_violation). Returns the findings as
/// "type: reason" strings; with `report`, logs them (a runtime under UNIT_TESTS/TESTING).
/datum/controller/subsystem/reactor/proc/audit(sample = audit_sample, report = FALSE)
	var/list/findings = list()
	var/count = length(subscribers)
	var/scheduled_count = length(scheduled_behaviour_runtimes)
	if(!count && !scheduled_count)
		return last_audit_findings = findings
	var/list/candidates = list()
	var/native_sample = scheduled_count && count ? max(1, round(sample / 2)) : sample
	if(count <= native_sample)
		candidates = subscribers.Copy()
	else
		for(var/i in 1 to native_sample)
			candidates += subscribers[rand(1, count)]
	var/behaviour_sample = count ? max(1, sample - native_sample) : sample
	if(scheduled_count <= behaviour_sample)
		candidates += scheduled_behaviour_runtimes
	else
		for(var/i in 1 to behaviour_sample)
			candidates += scheduled_behaviour_runtimes[rand(1, scheduled_count)]
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
 */
/mob/living/proc/reactor_wake(bits, what)
	SHOULD_NOT_SLEEP(TRUE)
	life_wake(bits, "reactor:[what]")
