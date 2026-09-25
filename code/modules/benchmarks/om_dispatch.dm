// Object-model dispatch cost against an SSprocessing-style loop
// (doc/rewrite/object_model_core.md, "Cost"). Both loops call one trivial
// proc per entity per second of simulated time; the object-model side also
// pays for its ring bookkeeping, budget checks and per-batch timing.
//   tools/build/build.sh bench --scenario=om_dispatch [--arg entities=20000]

/datum/om_bench_entity
	var/counter = 0

/datum/om_bench_entity/proc/process_like(seconds_per_tick)
	counter += seconds_per_tick

/datum/om/behaviour/bench_tick
	every = 1 SECONDS

/datum/om/behaviour/bench_tick/tick(datum/om_bench_entity/E, dt)
	E.counter += dt

/datum/benchmark/om_dispatch
	id = "om_dispatch"
	description = "Object-model cadence dispatch vs an SSprocessing-style loop"

/datum/benchmark/om_dispatch/Run()
	var/n = param("entities", 20000)
	var/rounds = param("rounds", 5)
	var/list/entities = list()
	for(var/i in 1 to n)
		entities += new /datum/om_bench_entity

	// Baseline: the SSprocessing shape (copy the run list, call, tick check).
	var/baseline_ms = 0
	for(var/r in 1 to rounds)
		var/start = TICK_USAGE
		var/list/current_run = entities.Copy()
		while(length(current_run))
			var/datum/om_bench_entity/E = current_run[length(current_run)]
			current_run.len--
			E.process_like(1)
			if(TICK_USAGE > 1e9)
				break
		baseline_ms += TICK_USAGE_TO_MS(start)

	// Object model: one simulated second = every slot of the ring, once.
	var/datum/om/scheduler/sched = om_test_begin()
	for(var/datum/om_bench_entity/E as anything in entities)
		om_attach(E, /datum/om/behaviour/bench_tick)
	sched.advance(1)
	var/om_ms = 0
	for(var/r in 1 to rounds)
		var/start = TICK_USAGE
		sched.advance(1)
		om_ms += TICK_USAGE_TO_MS(start)
	om_test_end()

	var/calls = n * rounds
	metric("om_dispatch_process_ns_per_call", baseline_ms * 1e6 / calls, "ns")
	metric("om_dispatch_om_ns_per_call", om_ms * 1e6 / calls, "ns")
	metric("om_dispatch_ratio", baseline_ms ? om_ms / baseline_ms : 0, "x")
	for(var/datum/om_bench_entity/E as anything in entities)
		qdel(E)
