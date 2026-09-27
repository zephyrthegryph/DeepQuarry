# Scheduler diagnostics and dispatch policy

`SSreactor` records scheduled Behaviour, nested Life-system, native wake, and
continuous callback costs by type. Scheduled Behaviour and reactor callback
costs are measured per dispatch. The high-volume nested Life systems retain
exact call counts and check elapsed time on every call. They add timing to
aggregate reports every 16th Life frame, or when a call crosses the slow
threshold or occurs on a busy tick. This preserves outlier detection, but the
per-call timing check still has a cost in the measured Life benchmark.
Scheduled callbacks record work units and, when they have a deadline, queue
lateness. The Master Controller captures a bounded
incident when a tick exceeds its budget. Benchmark windows save the same
diagnostics and the report shows slow systems and incidents.

## Declaring scheduled work

```dm
/datum/object_model/behaviour/example
	run_period = 2 SECONDS
	run_clock = /datum/object_model/clock_domain/biology
	run_priority = 10
	run_max_lateness = 0.5 SECONDS
	run_cost_hint_ms = 0.5

/datum/object_model/behaviour/example/on_run(datum/source, seconds, list/config)
	// Integrate `seconds` of local time, rather than assume one call is one step.
	// If work is batched, call om_behaviour_report_work(source, type, count).
	return null
```

`run_period` is the target interval. `run_clock` selects local time; without it,
`seconds` uses real time. A stopped clock retains its virtual deadline without
polling. `run_priority` is larger for more urgent work. Selection uses bounded
priority and age promotion; inside one entity, declared Behaviour order still
applies. `run_cost_hint_ms` seeds the budget estimate until real calls are
measured. A slow call cannot be preempted: expensive work must be divided into
bounded callbacks or integrated analytically. Content that mixes simulation
with presentation must separate those effects before accelerating its clock.

Legacy `REACT_EVERY` callbacks have a separate callback quota and rotating
cursor. They run before the shared and pending Behaviour queues each reactor
tick, so a saturated pending queue cannot prevent all continuous work. Their
`seconds` argument still measures elapsed real time after a deferred call.

Life remains one scheduled Behaviour per living mob. Its ordered Life systems
are nested diagnostic spans. Faster biology replays only audited
`tick_biology()` hooks; ordinary presentation runs once per real frame.

## Reading a report

- **Slow call:** main-thread callback cost exceeds both the configured minimum
  and three times the system's prior expected cost. Behaviour expectations use
  inclusive measured cost, so an ordinary Life frame is not an outlier merely
  because it contains several Life systems.
- **Deadline miss:** a callback starts after its declared lateness limit.
- **Deferral:** due work remained because of a callback quota or tick budget.
- **Overrun incident:** subsystem breakdown, top scheduler callbacks, pending
  counts, and explicitly unattributed tick use.

Callback rows are exclusive of observed nested scheduler work; subsystem rows
include their descendants and must not be added to callback rows. The generic
`BYOND / pre-MC / external` category and profiler overhead cannot always be
assigned to an individual callback. A report identifies the measured
contributors and remaining cost, rather than claiming a precise cause for
every engine-level overrun. Aggregates are bounded by type and recent examples
are held in fixed-size rings, so long rounds do not accumulate per-call logs.

Use `SSreactor.performance_scheduler_diagnostics()` for a live snapshot.
`begin_window()` and `end_window()` include deltas in benchmark output and
the generated HTML report.
