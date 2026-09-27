// Deterministic checks for scheduler attribution and dispatch policy.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/datum/object_model/behaviour/test_scheduler_diagnostics
	run_max_lateness = 1 SECONDS

/datum/object_model/behaviour/test_scheduler_expected_heavy
	run_cost_hint_ms = 4

/datum/object_model/behaviour/test_scheduler_low_priority
	run_priority = 1
	run_period = 1 SECONDS

/datum/object_model/behaviour/test_scheduler_high_priority
	run_priority = 10
	run_period = 1 SECONDS

/datum/object_model/behaviour_runtime/test_scheduler_probe
	var/list/run_log

/datum/object_model/behaviour_runtime/test_scheduler_probe/run_shared_frame(path, scheduled_at = null)
	run_log += path

/datum/scheduler_test_work_actor
	var/runs = 0

/datum/scheduler_test_work_actor/om_declare(datum/object_model/archetype/A)
	..()
	A.add(/datum/object_model/behaviour/test_scheduler_work)

/datum/object_model/behaviour/test_scheduler_work
	run_priority = 5

/datum/object_model/behaviour/test_scheduler_work/on_run(datum/source, seconds, list/config)
	var/datum/scheduler_test_work_actor/actor = source
	actor.runs++
	om_behaviour_report_work(actor, type, 7)
	return 0

/// A producer wake retains its first reason, and integrated work reports completed units.
/datum/unit_test/dq_scheduler_queue_metadata_and_work
	needs_test_block = FALSE

/datum/unit_test/dq_scheduler_queue_metadata_and_work/Run()
	var/datum/scheduler_test_work_actor/actor = new
	var/datum/object_model/behaviour_runtime/R = om_behaviour_start(actor)
	TEST_ASSERT_NOTNULL(R, "test actor has a behaviour runtime")
	var/path = /datum/object_model/behaviour/test_scheduler_work
	var/key = "behaviour|[path]"
	var/list/previous = SSreactor.scheduler_systems[key]
	var/previous_units = previous?["work_units"] || 0
	var/previous_calls = previous?["calls"] || 0
	var/old_metric_limit = SSreactor.max_metric_types
	SSreactor.max_metric_types = max(old_metric_limit, length(SSreactor.scheduler_systems) + 1)
	var/first_wake = R.wake(path, "first producer")
	var/queued_at = R.run_pending_since?[path]
	R.wake(path, "second producer")
	var/retained_reason = R.run_pending_reason?[path]
	var/oldest_at = R.queue_oldest_at()
	var/priority = R.queue_priority()
	R.run_ready()
	SSreactor.pending_behaviour_runtimes -= R
	R.run_queued = FALSE
	SSreactor.max_metric_types = old_metric_limit
	var/list/row = SSreactor.scheduler_systems[key]
	var/runs = actor.runs
	qdel(actor)
	TEST_ASSERT(first_wake, "declared behaviour accepts a producer wake")
	TEST_ASSERT_EQUAL(retained_reason, "first producer", "coalesced wakes retain the original reason")
	TEST_ASSERT_EQUAL(oldest_at, queued_at, "the queue exposes its oldest wake time")
	TEST_ASSERT_EQUAL(priority, 5, "the runtime exposes its declared priority")
	TEST_ASSERT_EQUAL(runs, 1, "coalesced producer wakes run once")
	TEST_ASSERT_EQUAL(row["calls"], previous_calls + 1, "the callback is observed")
	TEST_ASSERT_EQUAL(row["work_units"], previous_units + 7, "the callback reports integrated work units")

/// Queue choice respects declared importance, then eventually promotes old work.
/datum/unit_test/dq_scheduler_pending_selection
	needs_test_block = FALSE

/datum/unit_test/dq_scheduler_pending_selection/Run()
	var/low_path = /datum/object_model/behaviour/test_scheduler_low_priority
	var/high_path = /datum/object_model/behaviour/test_scheduler_high_priority
	var/datum/object_model/behaviour_runtime/test_scheduler_probe/low = new
	var/datum/object_model/behaviour_runtime/test_scheduler_probe/high = new
	low.run_pending = list()
	low.run_pending[low_path] = TRUE
	low.run_pending_since = list()
	low.run_pending_since[low_path] = world.time
	high.run_pending = list()
	high.run_pending[high_path] = TRUE
	high.run_pending_since = list()
	high.run_pending_since[high_path] = world.time
	var/list/old_queue = SSreactor.pending_behaviour_runtimes
	SSreactor.pending_behaviour_runtimes = list(low, high)
	var/urgent_choice = SSreactor.select_pending_behaviour_index(1)
	low.run_pending_since[low_path] = world.time - 2 MINUTES
	var/aged_choice = SSreactor.select_pending_behaviour_index(1)
	SSreactor.pending_behaviour_runtimes = old_queue
	qdel(low)
	qdel(high)
	TEST_ASSERT_EQUAL(urgent_choice, 2, "a fresh urgent behaviour goes first")
	TEST_ASSERT_EQUAL(aged_choice, 1, "long-waiting lower-priority work is promoted")

/// One callback budget leaves the next shared-cadence owner queued and records why.
/datum/unit_test/dq_scheduler_shared_budget
	needs_test_block = FALSE

/datum/unit_test/dq_scheduler_shared_budget/Run()
	var/low_path = /datum/object_model/behaviour/test_scheduler_low_priority
	var/high_path = /datum/object_model/behaviour/test_scheduler_high_priority
	var/list/log = list()
	var/datum/object_model/behaviour_runtime/test_scheduler_probe/low = new
	var/datum/object_model/behaviour_runtime/test_scheduler_probe/high = new
	low.run_log = log
	high.run_log = log
	var/datum/reactor_shared_cadence/low_group = new(low_path, world.tick_lag)
	var/datum/reactor_shared_cadence/high_group = new(high_path, world.tick_lag)
	low_group.add(low)
	high_group.add(high)
	var/list/old_groups = SSreactor.shared_cadence_groups
	var/old_budget = SSreactor.shared_cadence_budget
	var/old_cursor = SSreactor.shared_cadence_cursor
	var/old_step_tick = SSreactor.step_tick
	var/old_ticklimit = Master.current_ticklimit
	var/old_deferred = SSreactor.scheduler_totals["deferred_budget"] || 0
	SSreactor.shared_cadence_groups = list()
	SSreactor.shared_cadence_groups[low_path] = low_group
	SSreactor.shared_cadence_groups[high_path] = high_group
	SSreactor.shared_cadence_budget = 1
	SSreactor.shared_cadence_cursor = 0
	SSreactor.step_tick = SSreactor.tick_of(world.time)
	Master.current_ticklimit = 1000
	SSreactor.run_shared_cadences()
	var/low_remaining = low_group.pending_count()
	var/high_remaining = high_group.pending_count()
	var/deferred = SSreactor.scheduler_totals["deferred_budget"] || 0
	SSreactor.shared_cadence_groups = old_groups
	SSreactor.shared_cadence_budget = old_budget
	SSreactor.shared_cadence_cursor = old_cursor
	SSreactor.step_tick = old_step_tick
	Master.current_ticklimit = old_ticklimit
	qdel(low_group)
	qdel(high_group)
	qdel(low)
	qdel(high)
	TEST_ASSERT_EQUAL(length(log), 1, "one shared callback fits a one-callback budget")
	TEST_ASSERT_EQUAL(log[1], high_path, "higher-priority shared work runs first")
	TEST_ASSERT_EQUAL(high_remaining, 0, "the urgent shared group completes")
	TEST_ASSERT_EQUAL(low_remaining, 1, "lower-priority work remains queued")
	TEST_ASSERT_EQUAL(deferred, old_deferred + 1, "budget deferral is recorded")

/// A slow callback and a missed deadline describe separate failures, even when they coincide.
/datum/unit_test/dq_scheduler_dispatch_observation
	needs_test_block = FALSE

/datum/unit_test/dq_scheduler_dispatch_observation/Run()
	var/system_type = /datum/object_model/behaviour/test_scheduler_diagnostics
	var/key = "behaviour|[system_type]"
	var/old_metric_limit = SSreactor.max_metric_types
	SSreactor.max_metric_types = max(old_metric_limit, length(SSreactor.scheduler_systems) + 1)
	var/list/before = SSreactor.performance_scheduler_diagnostics()
	var/list/previous = before["systems"]?[key]
	var/previous_calls = previous?["calls"] || 0
	var/previous_misses = previous?["deadline_misses"] || 0
	var/previous_slow = previous?["slow_calls"] || 0
	var/old_threshold = SSreactor.scheduler_slow_call_ms
	SSreactor.scheduler_slow_call_ms = 1
	SSreactor.observe_dispatch("behaviour", system_type, /datum/unit_test, world.time, world.time, 0.25, "test on time")
	SSreactor.observe_dispatch("behaviour", system_type, /datum/unit_test, world.time - 2 SECONDS, world.time, 3, "test late", 2, 5)
	SSreactor.scheduler_slow_call_ms = old_threshold
	SSreactor.max_metric_types = old_metric_limit
	var/list/diagnostics = SSreactor.performance_scheduler_diagnostics()
	var/list/row = diagnostics["systems"]?[key]
	TEST_ASSERT_NOTNULL(row, "observed work has a per-system diagnostic row")
	TEST_ASSERT_EQUAL(row["calls"], previous_calls + 2, "both dispatches are counted")
	TEST_ASSERT_EQUAL(row["deadline_misses"], previous_misses + 1, "only the late dispatch misses its deadline")
	TEST_ASSERT_EQUAL(row["slow_calls"], previous_slow + 1, "only the expensive dispatch is slow")
	TEST_ASSERT(row["max_lateness_ds"] >= 2 SECONDS, "lateness records the queue wait")
	TEST_ASSERT(row["max_call_ms"] >= 3, "the largest callback cost is retained")
	var/list/slow_calls = diagnostics["slow_calls"]
	var/list/latest = slow_calls[length(slow_calls)]
	TEST_ASSERT_EQUAL(latest["system_type"], "[system_type]", "slow-call detail identifies the system")
	TEST_ASSERT_EQUAL(latest["entity_type"], "[/datum/unit_test]", "slow-call detail identifies the owner")
	TEST_ASSERT_EQUAL(latest["reason"], "test late", "slow-call detail retains the wake reason")

/// A normally expensive frame must not evict real outliers from the slow ring.
/datum/unit_test/dq_scheduler_expected_cost_threshold
	needs_test_block = FALSE

/datum/unit_test/dq_scheduler_expected_cost_threshold/Run()
	var/path = /datum/object_model/behaviour/test_scheduler_expected_heavy
	var/key = "behaviour|[path]"
	var/old_metric_limit = SSreactor.max_metric_types
	SSreactor.max_metric_types = max(old_metric_limit, length(SSreactor.scheduler_systems) + 1)
	var/old_threshold = SSreactor.scheduler_slow_call_ms
	SSreactor.scheduler_slow_call_ms = 2
	var/list/previous = SSreactor.scheduler_systems[key]
	var/previous_slow = previous?["slow_calls"] || 0
	SSreactor.observe_dispatch("behaviour", path, /datum/unit_test, null, world.time, 4, "ordinary frame")
	var/ordinary_slow = SSreactor.scheduler_systems[key]["slow_calls"]
	for(var/i in 1 to 20)
		SSreactor.observe_dispatch("behaviour", path, /datum/unit_test, null, world.time, 0.5, "cheap frame")
	SSreactor.observe_dispatch("behaviour", path, /datum/unit_test, null, world.time, 3, "ordinary after cheap frames")
	var/after_cheap_slow = SSreactor.scheduler_systems[key]["slow_calls"]
	SSreactor.observe_dispatch("behaviour", path, /datum/unit_test, null, world.time, 14, "actual outlier")
	var/outlier_slow = SSreactor.scheduler_systems[key]["slow_calls"]
	SSreactor.scheduler_slow_call_ms = old_threshold
	SSreactor.max_metric_types = old_metric_limit
	TEST_ASSERT_EQUAL(ordinary_slow, previous_slow, "normal declared cost is not a slow-call outlier")
	TEST_ASSERT_EQUAL(after_cheap_slow, previous_slow, "cheap frames do not erase the declared normal-cost floor")
	TEST_ASSERT_EQUAL(outlier_slow, previous_slow + 1, "an unexpectedly costly callback is retained")

/// An overrun incident retains measured scheduler work and an explicit remainder.
/datum/unit_test/dq_scheduler_incident_attribution
	needs_test_block = FALSE

/datum/unit_test/dq_scheduler_incident_attribution/Run()
	var/list/old_incidents = SSreactor.scheduler_incidents
	var/list/old_tick_systems = SSreactor.scheduler_tick_systems
	var/list/old_tick_slow = SSreactor.scheduler_tick_slow_calls
	var/old_tick_time = SSreactor.scheduler_tick_time
	var/old_tick_child_ms = SSreactor.scheduler_tick_child_ms
	var/old_metric_limit = SSreactor.max_metric_types
	SSreactor.scheduler_incidents = list()
	SSreactor.scheduler_tick_systems = list()
	SSreactor.scheduler_tick_slow_calls = list()
	SSreactor.scheduler_tick_time = world.time
	SSreactor.max_metric_types = max(old_metric_limit, length(SSreactor.scheduler_systems) + 1)
	var/system_type = /datum/object_model/behaviour/test_scheduler_diagnostics
	SSreactor.observe_dispatch("behaviour", system_type, /datum/unit_test, null, world.time, 0.5, "incident probe")
	var/list/incident = SSreactor.record_scheduler_incident(130, list("air" = 8), 4)
	SSreactor.scheduler_incidents = old_incidents
	SSreactor.scheduler_tick_systems = old_tick_systems
	SSreactor.scheduler_tick_slow_calls = old_tick_slow
	SSreactor.scheduler_tick_time = old_tick_time
	SSreactor.scheduler_tick_child_ms = old_tick_child_ms
	SSreactor.max_metric_types = old_metric_limit
	TEST_ASSERT_EQUAL(incident["overrun"], 30, "incident records the tick overrun")
	TEST_ASSERT_EQUAL(incident["subsystems"]["air"], 8, "incident retains non-scheduler subsystem cost")
	TEST_ASSERT_EQUAL(incident["unattributed_usage"], 4, "incident labels work outside measured callbacks")
	var/list/contributors = incident["scheduler_systems"]
	TEST_ASSERT_EQUAL(length(contributors), 1, "incident retains its measured scheduler contributor")
	var/list/contributor = contributors[1]
	TEST_ASSERT_EQUAL(contributor["system_type"], "[system_type]", "incident identifies the expensive system")
	TEST_ASSERT_EQUAL(contributor["ms"], 0.5, "incident retains the measured callback cost")

/// Legacy continuous work rotates under a tight budget instead of waiting
/// behind an indefinitely busy pending-Behaviour lane.
/datum/unit_test/dq_scheduler_continuous_fairness
	needs_test_block = FALSE

/datum/unit_test/dq_scheduler_continuous_fairness/Run()
	var/list/old_continuous = SSreactor.continuous
	var/old_budget = SSreactor.continuous_budget
	var/old_cursor = SSreactor.continuous_cursor
	var/old_limit = Master.current_ticklimit
	var/datum/react_test_subscriber/first = new
	var/datum/react_test_subscriber/second = new
	var/datum/react_every/entry_a = new
	var/datum/react_every/entry_b = new
	entry_a.owner = first
	entry_a.last_run = world.time - 1 SECONDS
	entry_a.next_run = world.time
	entry_a.period = 1 SECONDS
	entry_a.why = "test continuous fairness A"
	entry_b.owner = second
	entry_b.last_run = world.time - 1 SECONDS
	entry_b.next_run = world.time
	entry_b.period = 1 SECONDS
	entry_b.why = "test continuous fairness B"
	SSreactor.continuous = list("a" = entry_a, "b" = entry_b)
	SSreactor.continuous_budget = 1
	SSreactor.continuous_cursor = 0
	Master.current_ticklimit = 1000
	SSreactor.run_continuous()
	var/first_pass = length(first.every_runs) + length(second.every_runs)
	SSreactor.run_continuous()
	var/first_runs = length(first.every_runs)
	var/second_runs = length(second.every_runs)
	SSreactor.continuous = old_continuous
	SSreactor.continuous_budget = old_budget
	SSreactor.continuous_cursor = old_cursor
	Master.current_ticklimit = old_limit
	qdel(entry_a)
	qdel(entry_b)
	qdel(first)
	qdel(second)
	TEST_ASSERT_EQUAL(first_pass, 1, "one due continuous callback fits the budget")
	TEST_ASSERT_EQUAL(first_runs, 1, "the first callback runs once")
	TEST_ASSERT_EQUAL(second_runs, 1, "the cursor services the other callback next")

#endif
