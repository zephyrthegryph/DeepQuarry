// Object-model dispatch cost against an SSprocessing-style loop
// (doc/rewrite/object_model_core.md, "Cost"). Both loops call one trivial
// proc per entity per second of simulated time; the object-model side also
// pays for its ring bookkeeping, budget checks and per-batch timing.
// A second pair compares a pipeline of 8 stages (§4.10) with a hand-written
// frame loop over 8 flyweights, all awake and then with 7 of 8 idle.
//   tools/build/build.sh bench --scenario=om_dispatch [--arg entities=20000]

/datum/om_bench_entity
	var/counter = 0
	/// Pipeline arm: every stage but the first idles.
	var/mostly_idle = FALSE

/datum/om_bench_entity/proc/process_like(seconds_per_tick)
	counter += seconds_per_tick

/datum/om/behaviour/bench_tick
	every = 1 SECONDS

/datum/om/behaviour/bench_tick/tick(datum/om_bench_entity/E, dt)
	E.counter += dt

/datum/om/pipeline/bench
	name = "bench pipeline"
	every = 1 SECONDS
	stages = list(/datum/om/stage/bench)
	park_after = 0

/datum/om/stage/bench
	category = /datum/om/stage/bench
	pipeline = /datum/om/pipeline/bench
	of = /datum/om_bench_entity

/datum/om/stage/bench/perform(datum/om_bench_entity/E, datum/om/frame/F)
	E.counter++

/datum/om/stage/bench/idle(datum/om_bench_entity/E)
	return E.mostly_idle && order > 1

/datum/om/stage/bench/s1
	order = 1
/datum/om/stage/bench/s2
	order = 2
/datum/om/stage/bench/s3
	order = 3
/datum/om/stage/bench/s4
	order = 4
/datum/om/stage/bench/s5
	order = 5
/datum/om/stage/bench/s6
	order = 6
/datum/om/stage/bench/s7
	order = 7
/datum/om/stage/bench/s8
	order = 8

/// The hand-written frame loop the pipeline replaced: flyweights in a list, a per-entity
/// asleep flag list, one call per awake flyweight and its idle rule (as life_frame() did).
/datum/om_bench_system
	var/order = 0

/datum/om_bench_system/proc/tick(datum/om_bench_entity/E)
	E.counter++

/datum/om_bench_system/proc/idle(datum/om_bench_entity/E)
	return E.mostly_idle && order > 1

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

	// Pipelines: 8 stages per entity, all awake, then 7 of 8 idle.
	var/pipe_n = param("pipeline_entities", 5000)
	for(var/mostly_idle in list(FALSE, TRUE))
		var/label = mostly_idle ? "idle7" : "awake"
		var/list/systems = list()
		for(var/i in 1 to 8)
			var/datum/om_bench_system/S = new
			S.order = i
			systems += S
		var/list/pipe_entities = list()
		var/list/asleep = list()
		for(var/i in 1 to pipe_n)
			var/datum/om_bench_entity/E = new
			E.mostly_idle = mostly_idle
			pipe_entities += E
			var/list/flags = new /list(8)
			for(var/j in 1 to 8)
				flags[j] = mostly_idle && j > 1
			asleep += list(flags)
		var/loop_ms = 0
		for(var/r in 1 to rounds)
			var/start = TICK_USAGE
			for(var/k in 1 to length(pipe_entities))
				var/datum/om_bench_entity/E = pipe_entities[k]
				var/list/flags = asleep[k]
				for(var/j in 1 to 8)
					if(flags[j])
						continue
					var/datum/om_bench_system/S = systems[j]
					S.tick(E)
					if(S.idle(E))
						flags[j] = TRUE
			loop_ms += TICK_USAGE_TO_MS(start)
		var/datum/om/scheduler/psched = om_test_begin()
		for(var/datum/om_bench_entity/E as anything in pipe_entities)
			om_attach(E, /datum/om/pipeline/bench)
		psched.advance(2)
		var/pipe_ms = 0
		for(var/r in 1 to rounds)
			var/start = TICK_USAGE
			psched.advance(1)
			pipe_ms += TICK_USAGE_TO_MS(start)
		// The runner alone, called directly (no ring, no scheduler pass).
		var/datum/om/pipeline/P = om_registry().behaviour(/datum/om/pipeline/bench)
		var/direct_ms = 0
		for(var/r in 1 to rounds)
			var/start = TICK_USAGE
			for(var/datum/om_bench_entity/E as anything in pipe_entities)
				P.run_frame(E, 1)
			direct_ms += TICK_USAGE_TO_MS(start)
		om_test_end()
		var/frames = pipe_n * rounds
		metric("om_dispatch_runner_[label]_ns_per_entity", direct_ms * 1e6 / frames, "ns")
		metric("om_dispatch_frameloop_[label]_ns_per_entity", loop_ms * 1e6 / frames, "ns")
		metric("om_dispatch_pipeline_[label]_ns_per_entity", pipe_ms * 1e6 / frames, "ns")
		metric("om_dispatch_pipeline_[label]_ratio", loop_ms ? pipe_ms / loop_ms : 0, "x")
		for(var/datum/om_bench_entity/E as anything in pipe_entities)
			qdel(E)
