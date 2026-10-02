// A Life-shaped kernel sequence against the object-model pipeline runner it replaces
// (doc/rewrite/life_sequences.md, "Measured"). Both run the same 30 steps over five bands, gated like Life's
// (placed; placed and alive; placed and the status step's result), with a frame begin() hook, a fixed 1 s step and
// no parking (so every frame is paid for). Three shapes:
//   awake   every step has work every frame (a human: the body never settles)
//   mixed   one step in three has work; the rest sleep (the word walk)
//   idle    every step sleeps (the frame is only its loop)
// For each, the runner alone (one frame per mob, called directly) and the scheduled path (the pipeline's ring on a
// test scheduler; the sequence's spread sweep on a test kernel), in ns per mob-frame, best of `rounds`. The gate is
// sequence <= 1.05 x pipeline.
//   tools/build/build.sh bench --scenario=life_sequence [--arg=mobs=2000] [--arg=rounds=7]

#define LB_INPUT "LB_INPUT"
#define LB_BODY "LB_BODY"
#define LB_MIND "LB_MIND"
#define LB_OUTPUT "LB_OUTPUT"
#define LB_TAIL "LB_TAIL"
#define LB_STEPS 30
#define LB_GATE 1.05
#define LB_RUN_IF_P FACT("placed")
#define LB_RUN_IF_PA ALL_OF(FACT("placed"), FACT("alive"))
#define LB_RUN_IF_PS ALL_OF(FACT("placed"), FACT("status_ok"))

/// A mob-shaped entity: what the gates read, and which steps have work.
/datum/life_bench_mob
	var/placed = TRUE
	var/alive = TRUE
	var/stasis = FALSE
	var/counter = 0
	/// Step index -> TRUE while that step has work.
	var/list/busy

/datum/life_bench_mob/New(list/busy)
	..()
	src.busy = busy

// ---------------------------------------------------------------- the pipeline arm

/datum/om/pipeline/bench_life
	name = "bench life pipeline"
	every = 1 SECONDS
	step_interval = 1
	max_catchup = 2
	stages = list(/datum/om/stage/bench_life)
	frame_type = /datum/om/frame/bench_life
	park_after = 0

/datum/om/frame/bench_life
	facts = list(
		"placed" = list(/datum/om/frame/bench_life/proc/fact_placed, 0),
		"alive" = list(/datum/om/frame/bench_life/proc/fact_alive, CHANGE_DATUM_A),
		"status_ok" = list(/datum/om/frame/bench_life/proc/fact_alive, CHANGE_DATUM_A),
	)
	var/stasis = FALSE

/datum/om/frame/bench_life/begin()
	var/datum/life_bench_mob/M = entity
	stasis = M.stasis

/datum/om/frame/bench_life/reset()
	stasis = FALSE

/datum/om/frame/bench_life/proc/fact_placed()
	var/datum/life_bench_mob/M = entity
	return M.placed

/datum/om/frame/bench_life/proc/fact_alive()
	var/datum/life_bench_mob/M = entity
	return M.alive

/datum/om/stage/bench_life
	category = /datum/om/stage/bench_life
	pipeline = /datum/om/pipeline/bench_life
	of = /datum/life_bench_mob
	var/idx = 0

/datum/om/stage/bench_life/perform(datum/life_bench_mob/E, datum/om/frame/F)
	E.counter++

/datum/om/stage/bench_life/idle(datum/life_bench_mob/E)
	return !E.busy[idx]

/// The status step: the steps gated on its result read it.
/datum/om/stage/bench_life/s18/perform(datum/life_bench_mob/E, datum/om/frame/F)
	F.set_fact("status_ok", TRUE)
	F.forget("alive")
	E.counter++

/datum/om/stage/bench_life/s1
	idx = 1
	order = 1001

/datum/om/stage/bench_life/s2
	idx = 2
	order = 1002

/datum/om/stage/bench_life/s3
	idx = 3
	order = 1003

/datum/om/stage/bench_life/s4
	idx = 4
	order = 1004
	run_if = LB_RUN_IF_PA

/datum/om/stage/bench_life/s5
	idx = 5
	order = 1005
	run_if = LB_RUN_IF_PA

/datum/om/stage/bench_life/s6
	idx = 6
	order = 1006
	run_if = LB_RUN_IF_PA

/datum/om/stage/bench_life/s7
	idx = 7
	order = 1007
	run_if = LB_RUN_IF_PA

/datum/om/stage/bench_life/s8
	idx = 8
	order = 1008
	run_if = LB_RUN_IF_PA

/datum/om/stage/bench_life/s9
	idx = 9
	order = 2009
	run_if = LB_RUN_IF_P

/datum/om/stage/bench_life/s10
	idx = 10
	order = 2010
	run_if = LB_RUN_IF_P

/datum/om/stage/bench_life/s11
	idx = 11
	order = 2011
	run_if = LB_RUN_IF_P

/datum/om/stage/bench_life/s12
	idx = 12
	order = 2012
	run_if = LB_RUN_IF_P

/datum/om/stage/bench_life/s13
	idx = 13
	order = 2013
	run_if = LB_RUN_IF_P

/datum/om/stage/bench_life/s14
	idx = 14
	order = 2014
	run_if = LB_RUN_IF_P

/datum/om/stage/bench_life/s15
	idx = 15
	order = 2015
	run_if = LB_RUN_IF_P

/datum/om/stage/bench_life/s16
	idx = 16
	order = 2016
	run_if = LB_RUN_IF_P

/datum/om/stage/bench_life/s17
	idx = 17
	order = 2017
	run_if = LB_RUN_IF_P

/datum/om/stage/bench_life/s18
	idx = 18
	order = 2018
	run_if = LB_RUN_IF_P

/datum/om/stage/bench_life/s19
	idx = 19
	order = 3019
	run_if = LB_RUN_IF_PS

/datum/om/stage/bench_life/s20
	idx = 20
	order = 3020
	run_if = LB_RUN_IF_PS

/datum/om/stage/bench_life/s21
	idx = 21
	order = 4021
	run_if = LB_RUN_IF_P

/datum/om/stage/bench_life/s22
	idx = 22
	order = 4022
	run_if = LB_RUN_IF_P

/datum/om/stage/bench_life/s23
	idx = 23
	order = 5023
	run_if = LB_RUN_IF_PA

/datum/om/stage/bench_life/s24
	idx = 24
	order = 5024

/datum/om/stage/bench_life/s25
	idx = 25
	order = 5025
	run_if = LB_RUN_IF_PA

/datum/om/stage/bench_life/s26
	idx = 26
	order = 5026

/datum/om/stage/bench_life/s27
	idx = 27
	order = 5027
	run_if = LB_RUN_IF_PA

/datum/om/stage/bench_life/s28
	idx = 28
	order = 5028

/datum/om/stage/bench_life/s29
	idx = 29
	order = 5029
	run_if = LB_RUN_IF_PA

/datum/om/stage/bench_life/s30
	idx = 30
	order = 5030

// ---------------------------------------------------------------- the sequence arm

/datum/sequence/bench_life
	name = "bench life sequence"
	interval = 1 SECONDS
	step = 1
	max_catchup = 2
	park_after = 0
	table_proc = TYPE_PROC_REF(/datum/life_bench_mob, bench_steps)
	frame_type = /datum/seq_frame/bench_life
	autoregister = FALSE

/datum/sequence/bench_life/anchors()
	return list(
		seq_anchor(LB_INPUT),
		seq_anchor(LB_BODY, after = LB_INPUT),
		seq_anchor(LB_MIND, after = LB_BODY),
		seq_anchor(LB_OUTPUT, after = LB_MIND),
		seq_anchor(LB_TAIL, after = LB_OUTPUT),
	)

/datum/sequence/bench_life/conditions()
	return list(
		seq_condition("placed", TYPE_PROC_REF(/datum/seq_frame/bench_life, placed)),
		seq_condition("alive", TYPE_PROC_REF(/datum/seq_frame/bench_life, alive), CHANGE_DATUM_A),
		seq_condition("status_ok", TYPE_PROC_REF(/datum/seq_frame/bench_life, status_passed), CHANGE_DATUM_A),
	)

/datum/seq_frame/bench_life
	var/stasis = FALSE
	var/status_ok

/datum/seq_frame/bench_life/begin()
	var/datum/life_bench_mob/M = entity
	stasis = M.stasis
	status_ok = null

/datum/seq_frame/bench_life/reset()
	. = ..()
	stasis = FALSE
	status_ok = null

/datum/seq_frame/bench_life/proc/placed()
	var/datum/life_bench_mob/M = entity
	return M.placed

/datum/seq_frame/bench_life/proc/alive()
	var/datum/life_bench_mob/M = entity
	return M.alive

/datum/seq_frame/bench_life/proc/status_passed()
	return isnull(status_ok) ? alive() : status_ok

/datum/life_bench_mob/proc/bench_steps()
	return list(
		seq_step(PROC_REF(bl_1), after = LB_INPUT, should_run = PROC_REF(bl_1_due)),
		seq_step(PROC_REF(bl_2), after = LB_INPUT, should_run = PROC_REF(bl_2_due)),
		seq_step(PROC_REF(bl_3), after = LB_INPUT, should_run = PROC_REF(bl_3_due)),
		seq_step(PROC_REF(bl_4), after = LB_INPUT, when = list("placed", "alive"), should_run = PROC_REF(bl_4_due)),
		seq_step(PROC_REF(bl_5), after = LB_INPUT, when = list("placed", "alive"), should_run = PROC_REF(bl_5_due)),
		seq_step(PROC_REF(bl_6), after = LB_INPUT, when = list("placed", "alive"), should_run = PROC_REF(bl_6_due)),
		seq_step(PROC_REF(bl_7), after = LB_INPUT, when = list("placed", "alive"), should_run = PROC_REF(bl_7_due)),
		seq_step(PROC_REF(bl_8), after = LB_INPUT, when = list("placed", "alive"), should_run = PROC_REF(bl_8_due)),
		seq_step(PROC_REF(bl_9), after = LB_BODY, when = "placed", should_run = PROC_REF(bl_9_due)),
		seq_step(PROC_REF(bl_10), after = LB_BODY, when = "placed", should_run = PROC_REF(bl_10_due)),
		seq_step(PROC_REF(bl_11), after = LB_BODY, when = "placed", should_run = PROC_REF(bl_11_due)),
		seq_step(PROC_REF(bl_12), after = LB_BODY, when = "placed", should_run = PROC_REF(bl_12_due)),
		seq_step(PROC_REF(bl_13), after = LB_BODY, when = "placed", should_run = PROC_REF(bl_13_due)),
		seq_step(PROC_REF(bl_14), after = LB_BODY, when = "placed", should_run = PROC_REF(bl_14_due)),
		seq_step(PROC_REF(bl_15), after = LB_BODY, when = "placed", should_run = PROC_REF(bl_15_due)),
		seq_step(PROC_REF(bl_16), after = LB_BODY, when = "placed", should_run = PROC_REF(bl_16_due)),
		seq_step(PROC_REF(bl_17), after = LB_BODY, when = "placed", should_run = PROC_REF(bl_17_due)),
		seq_step(PROC_REF(bl_18), after = LB_BODY, when = "placed", should_run = PROC_REF(bl_18_due)),
		seq_step(PROC_REF(bl_19), after = LB_MIND, when = list("placed", "status_ok"), should_run = PROC_REF(bl_19_due)),
		seq_step(PROC_REF(bl_20), after = LB_MIND, when = list("placed", "status_ok"), should_run = PROC_REF(bl_20_due)),
		seq_step(PROC_REF(bl_21), after = LB_OUTPUT, when = "placed", should_run = PROC_REF(bl_21_due)),
		seq_step(PROC_REF(bl_22), after = LB_OUTPUT, when = "placed", should_run = PROC_REF(bl_22_due)),
		seq_step(PROC_REF(bl_23), after = LB_TAIL, when = list("placed", "alive"), should_run = PROC_REF(bl_23_due)),
		seq_step(PROC_REF(bl_24), after = LB_TAIL, should_run = PROC_REF(bl_24_due)),
		seq_step(PROC_REF(bl_25), after = LB_TAIL, when = list("placed", "alive"), should_run = PROC_REF(bl_25_due)),
		seq_step(PROC_REF(bl_26), after = LB_TAIL, should_run = PROC_REF(bl_26_due)),
		seq_step(PROC_REF(bl_27), after = LB_TAIL, when = list("placed", "alive"), should_run = PROC_REF(bl_27_due)),
		seq_step(PROC_REF(bl_28), after = LB_TAIL, should_run = PROC_REF(bl_28_due)),
		seq_step(PROC_REF(bl_29), after = LB_TAIL, when = list("placed", "alive"), should_run = PROC_REF(bl_29_due)),
		seq_step(PROC_REF(bl_30), after = LB_TAIL, should_run = PROC_REF(bl_30_due)),
	)

#define LB_STEP(N) /datum/life_bench_mob/proc/bl_##N(datum/seq_frame/bench_life/F) { counter++ }; /datum/life_bench_mob/proc/bl_##N##_due() { return busy[N] }
LB_STEP(1)
LB_STEP(2)
LB_STEP(3)
LB_STEP(4)
LB_STEP(5)
LB_STEP(6)
LB_STEP(7)
LB_STEP(8)
LB_STEP(9)
LB_STEP(10)
LB_STEP(11)
LB_STEP(12)
LB_STEP(13)
LB_STEP(14)
LB_STEP(15)
LB_STEP(16)
LB_STEP(17)
LB_STEP(19)
LB_STEP(20)
LB_STEP(21)
LB_STEP(22)
LB_STEP(23)
LB_STEP(24)
LB_STEP(25)
LB_STEP(26)
LB_STEP(27)
LB_STEP(28)
LB_STEP(29)
LB_STEP(30)
#undef LB_STEP

/// The status step.
/datum/life_bench_mob/proc/bl_18(datum/seq_frame/bench_life/F)
	F.status_ok = TRUE
	F.forget("alive")
	counter++

/datum/life_bench_mob/proc/bl_18_due()
	return busy[18]

// ---------------------------------------------------------------- the scenario

/datum/benchmark/life_sequence
	id = "life_sequence"
	description = "A Life-shaped kernel sequence vs the object-model pipeline runner: ns per mob-frame"

/datum/benchmark/life_sequence/Run()
	var/n = param("mobs", 2000)
	var/rounds = param("rounds", 7)
	var/failures = 0
	var/list/table = list()
	for(var/shape in list("awake", "mixed", "idle"))
		var/list/result = measure(shape, n, rounds)
		table[shape] = result
		for(var/path in list("runner", "scheduled"))
			var/pipe_ns = result["[path]_pipeline_ns"]
			var/seq_ns = result["[path]_sequence_ns"]
			var/ratio = pipe_ns ? seq_ns / pipe_ns : 0
			metric("life_sequence_[shape]_[path]_pipeline_ns", pipe_ns, "ns")
			metric("life_sequence_[shape]_[path]_sequence_ns", seq_ns, "ns")
			metric("life_sequence_[shape]_[path]_ratio", ratio, "x")
			if(ratio > LB_GATE)
				failures++
		count_metric("life_sequence_[shape]_frames_per_mob_round", result["frames_per_mob_round"], "frames", "none")
	count_metric("life_sequence_gate_failures", failures, "ratios", "lower")
	detail("life_sequence", table)

/// One shape: `n` mobs on each engine, `rounds` timed rounds (runner, then scheduled), alternating the engines.
/datum/benchmark/life_sequence/proc/measure(shape, n, rounds)
	var/datum/om/pipeline/P = om_registry().behaviour(/datum/om/pipeline/bench_life)
	var/datum/sequence/SQ = sequence_def(/datum/sequence/bench_life)
	var/datum/om/scheduler/sched = om_test_begin()
	var/list/pipe_mobs = list()
	var/list/seq_mobs = list()
	for(var/i in 1 to n)
		pipe_mobs += new /datum/life_bench_mob(busy_list(shape))
		seq_mobs += new /datum/life_bench_mob(busy_list(shape))
	for(var/datum/life_bench_mob/E as anything in pipe_mobs)
		om_attach(E, P)
	for(var/datum/life_bench_mob/E as anything in seq_mobs)
		seq_start(E, /datum/sequence/bench_life)
	var/datum/controller/kernel/K = new
	var/datum/work_item/sequence/W = new(SQ)
	W.test_runlevel = RUNLEVEL_GAME
	SQ.work = W
	K.register_work(/datum/sequence/bench_life, W)
	var/datum/seq_frame/F = take(SQ.frame_type)
	F.seq = SQ
	var/idx = SQ.idx
	// Settle: the steps without work fall asleep.
	for(var/warm in 1 to 2)
		for(var/datum/life_bench_mob/E as anything in pipe_mobs)
			P.run_frame(E, 1)
		for(var/datum/life_bench_mob/E as anything in seq_mobs)
			SQ.run_frame(E, SEQ_STATE_OF(E, idx), F, 1)
	sched.advance(2)
	var/lag = max(world.tick_lag, 0.1)
	var/passes = max(round((1 SECONDS) / lag), 1)
	var/now = 1000
	for(var/k in 1 to passes)
		K.run_item(W, WORK_TEST_LIMIT, now)
		now += lag
	var/best_runner_pipe = INFINITY
	var/best_runner_seq = INFINITY
	var/best_sched_pipe = INFINITY
	var/best_sched_seq = INFINITY
	var/seq_frames_before = seq_frames(seq_mobs, /datum/sequence/bench_life)
	for(var/r in 1 to rounds)
		var/start = TICK_USAGE
		for(var/datum/life_bench_mob/E as anything in pipe_mobs)
			P.run_frame(E, 1)
		best_runner_pipe = min(best_runner_pipe, TICK_USAGE_TO_MS(start))
		start = TICK_USAGE
		for(var/datum/life_bench_mob/E as anything in seq_mobs)
			SQ.run_frame(E, SEQ_STATE_OF(E, idx), F, 1)
		best_runner_seq = min(best_runner_seq, TICK_USAGE_TO_MS(start))
		start = TICK_USAGE
		sched.advance(1)
		best_sched_pipe = min(best_sched_pipe, TICK_USAGE_TO_MS(start))
		start = TICK_USAGE
		for(var/k in 1 to passes)
			K.run_item(W, WORK_TEST_LIMIT, now)
			now += lag
		best_sched_seq = min(best_sched_seq, TICK_USAGE_TO_MS(start))
	var/sched_frames = seq_frames(seq_mobs, /datum/sequence/bench_life) - seq_frames_before - n * rounds
	F.release()
	. = list(
		"runner_pipeline_ns" = best_runner_pipe * 1e6 / n,
		"runner_sequence_ns" = best_runner_seq * 1e6 / n,
		"scheduled_pipeline_ns" = best_sched_pipe * 1e6 / n,
		"scheduled_sequence_ns" = best_sched_seq * 1e6 / n,
		"frames_per_mob_round" = sched_frames / (n * rounds),
	)
	for(var/datum/life_bench_mob/E as anything in seq_mobs)
		seq_stop(E, /datum/sequence/bench_life)
		qdel(E)
	for(var/datum/life_bench_mob/E as anything in pipe_mobs)
		qdel(E)
	SQ.work = null
	om_test_end()

/// Which steps have work in `shape`: all, one in three, none.
/datum/benchmark/life_sequence/proc/busy_list(shape)
	. = new /list(LB_STEPS)
	var/list/L = .
	for(var/i in 1 to LB_STEPS)
		switch(shape)
			if("awake")
				L[i] = TRUE
			if("mixed")
				L[i] = !(i % 3)
			else
				L[i] = FALSE

#undef LB_RUN_IF_PS
#undef LB_RUN_IF_PA
#undef LB_RUN_IF_P
#undef LB_GATE
#undef LB_STEPS
#undef LB_TAIL
#undef LB_OUTPUT
#undef LB_MIND
#undef LB_BODY
#undef LB_INPUT
