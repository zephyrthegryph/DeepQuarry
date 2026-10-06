// A Life-shaped kernel sequence against a fixed reference runner (doc/rewrite/life_sequences.md, "Measured";
// doc/rewrite/om_retirement.md L2). The sequence runs 30 steps over five bands, gated like Life's (placed; placed and
// alive; placed and the status step's result), with a frame begin() hook, a fixed 1 s step and no parking (so every frame
// is paid for). Three shapes:
//   awake   every step has work every frame (a human: the body never settles)
//   mixed   one step in three has work; the rest sleep (the word walk)
//   idle    every step sleeps (the frame is only its loop)
// For each, the runner alone (one frame per mob, called directly) and the scheduled path (the sequence's spread sweep on
// a test kernel), in ns per mob-frame, best of `rounds`.
//
// The gate. It was `sequence <= 1.05 x the object-model pipeline runner`, measured side by side. The pipeline is gone, so
// the bench keeps a reference runner (the pipeline's shape with nothing around it) and the pipeline's cost relative to it,
// measured on both while both existed (October 2026, two runs averaged): LB_PIPE_OVER_REF_*. The gate is
// `sequence <= LB_GATE x pinned ratio x reference`, the same bound expressed without the pipeline. The idle shape
// missed the old gate too (doc/rewrite/life_sequences.md: a member whose steps all sleep parks in service).
//   tools/build/build.sh bench --scenario=life_sequence [--arg=mobs=2000] [--arg=rounds=7]

#define LB_INPUT "LB_INPUT"
#define LB_BODY "LB_BODY"
#define LB_MIND "LB_MIND"
#define LB_OUTPUT "LB_OUTPUT"
#define LB_TAIL "LB_TAIL"
#define LB_STEPS 30
#define LB_GATE 1.05
/// The pipeline runner's cost / the reference runner's, per shape (runner path), and the pipeline's scheduled ring / the
/// reference runner (scheduled path), pinned from the last side-by-side runs.
#define LB_PIPE_OVER_REF_RUNNER list("awake" = 2.99, "mixed" = 2.82, "idle" = 0.65)
#define LB_PIPE_OVER_REF_SCHEDULED list("awake" = 3.30, "mixed" = 3.16, "idle" = 1.01)

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

// ---------------------------------------------------------------- the reference arm
// The pipeline runner's shape with nothing around it: one flyweight per step with a virtual perform() and idle(), the
// frame's facts cached per frame, a sleep flag per step. The yardstick the gate is pinned against (see the top).

/datum/life_bench_ref_step
	var/idx = 0
	/// 0: ungated. 1: placed. 2: placed and alive. 3: placed and the status step's result.
	var/gate = 0

/datum/life_bench_ref_step/proc/perform(datum/life_bench_mob/E, datum/life_bench_ref_frame/F)
	E.counter++

/datum/life_bench_ref_step/proc/idle(datum/life_bench_mob/E)
	return !E.busy[idx]

/datum/life_bench_ref_step/status/perform(datum/life_bench_mob/E, datum/life_bench_ref_frame/F)
	F.status_ok = TRUE
	F.alive_known = FALSE
	E.counter++

/datum/life_bench_ref_frame
	var/datum/life_bench_mob/entity
	var/placed
	var/alive
	var/alive_known = FALSE
	var/status_ok

/// The reference runner's steps, in the same order and with the same gates as the sequence's table.
/proc/life_bench_ref_steps()
	var/static/list/steps
	if(steps)
		return steps
	steps = list()
	var/list/gates = list(0, 0, 0, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 3, 3, 1, 1, 2, 0, 2, 0, 2, 0, 2, 0)
	for(var/i in 1 to LB_STEPS)
		var/datum/life_bench_ref_step/S = i == 18 ? new /datum/life_bench_ref_step/status : new /datum/life_bench_ref_step
		S.idx = i
		S.gate = gates[i]
		steps += S
	return steps

/// One reference frame of `E`: every awake step, gated, put to sleep by its idle().
/proc/life_bench_ref_frame(datum/life_bench_mob/E, list/asleep, datum/life_bench_ref_frame/F)
	F.entity = E
	F.placed = E.placed
	F.alive_known = FALSE
	F.status_ok = null
	for(var/datum/life_bench_ref_step/S as anything in life_bench_ref_steps())
		var/i = S.idx
		if(asleep[i])
			continue
		switch(S.gate)
			if(1)
				if(!F.placed)
					continue
			if(2, 3)
				if(!F.placed)
					continue
				if(!F.alive_known)
					F.alive = E.alive
					F.alive_known = TRUE
				if(!(S.gate == 3 && !isnull(F.status_ok) ? F.status_ok : F.alive))
					continue
		S.perform(E, F)
		if(S.idle(E))
			asleep[i] = TRUE

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
	description = "A Life-shaped kernel sequence vs a pinned reference runner: ns per mob-frame"

/datum/benchmark/life_sequence/Run()
	var/n = param("mobs", 2000)
	var/rounds = param("rounds", 7)
	var/failures = 0
	var/list/table = list()
	var/list/pins = list("runner" = LB_PIPE_OVER_REF_RUNNER, "scheduled" = LB_PIPE_OVER_REF_SCHEDULED)
	for(var/shape in list("awake", "mixed", "idle"))
		var/list/result = measure(shape, n, rounds)
		table[shape] = result
		var/ref_ns = result["runner_reference_ns"]
		metric("life_sequence_[shape]_runner_reference_ns", ref_ns, "ns")
		for(var/path in list("runner", "scheduled"))
			var/seq_ns = result["[path]_sequence_ns"]
			var/list/pin = pins[path]
			var/bound_ns = ref_ns * pin[shape]
			var/ratio = bound_ns ? seq_ns / bound_ns : 0
			metric("life_sequence_[shape]_[path]_sequence_ns", seq_ns, "ns")
			metric("life_sequence_[shape]_[path]_pipeline_equivalent_ns", bound_ns, "ns")
			metric("life_sequence_[shape]_[path]_ratio", ratio, "x")
			if(ratio > LB_GATE)
				failures++
		count_metric("life_sequence_[shape]_frames_per_mob_round", result["frames_per_mob_round"], "frames", "none")
	count_metric("life_sequence_gate_failures", failures, "ratios", "lower")
	detail("life_sequence", table)

/// One shape: `n` mobs on the sequence and on the reference runner, `rounds` timed rounds (runner, then scheduled).
/datum/benchmark/life_sequence/proc/measure(shape, n, rounds)
	var/datum/sequence/SQ = sequence_def(/datum/sequence/bench_life)
	var/list/seq_mobs = list()
	var/list/ref_mobs = list()
	var/list/ref_sleep = list()
	for(var/i in 1 to n)
		seq_mobs += new /datum/life_bench_mob(busy_list(shape))
		ref_mobs += new /datum/life_bench_mob(busy_list(shape))
		ref_sleep += list(new /list(LB_STEPS))
	var/datum/life_bench_ref_frame/RF = new
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
		for(var/datum/life_bench_mob/E as anything in seq_mobs)
			SQ.run_frame(E, SEQ_STATE_OF(E, idx), F, 1)
		for(var/i in 1 to n)
			life_bench_ref_frame(ref_mobs[i], ref_sleep[i], RF)
	var/lag = max(world.tick_lag, 0.1)
	var/passes = max(round((1 SECONDS) / lag), 1)
	var/now = 1000
	for(var/k in 1 to passes)
		K.run_item(W, WORK_TEST_LIMIT, now)
		now += lag
	var/best_runner_seq = INFINITY
	var/best_runner_ref = INFINITY
	var/best_sched_seq = INFINITY
	var/seq_frames_before = seq_frames(seq_mobs, /datum/sequence/bench_life)
	for(var/r in 1 to rounds)
		var/start = TICK_USAGE
		for(var/datum/life_bench_mob/E as anything in seq_mobs)
			SQ.run_frame(E, SEQ_STATE_OF(E, idx), F, 1)
		best_runner_seq = min(best_runner_seq, TICK_USAGE_TO_MS(start))
		start = TICK_USAGE
		for(var/i in 1 to n)
			life_bench_ref_frame(ref_mobs[i], ref_sleep[i], RF)
		best_runner_ref = min(best_runner_ref, TICK_USAGE_TO_MS(start))
		start = TICK_USAGE
		for(var/k in 1 to passes)
			K.run_item(W, WORK_TEST_LIMIT, now)
			now += lag
		best_sched_seq = min(best_sched_seq, TICK_USAGE_TO_MS(start))
	var/sched_frames = seq_frames(seq_mobs, /datum/sequence/bench_life) - seq_frames_before - n * rounds
	F.release()
	. = list(
		"runner_sequence_ns" = best_runner_seq * 1e6 / n,
		"runner_reference_ns" = best_runner_ref * 1e6 / n,
		"scheduled_sequence_ns" = best_sched_seq * 1e6 / n,
		"frames_per_mob_round" = sched_frames / (n * rounds),
	)
	for(var/datum/life_bench_mob/E as anything in seq_mobs)
		seq_stop(E, /datum/sequence/bench_life)
		qdel(E)
	for(var/datum/life_bench_mob/E as anything in ref_mobs)
		qdel(E)
	SQ.work = null

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

#undef LB_GATE
#undef LB_PIPE_OVER_REF_RUNNER
#undef LB_PIPE_OVER_REF_SCHEDULED
#undef LB_STEPS
#undef LB_TAIL
#undef LB_OUTPUT
#undef LB_MIND
#undef LB_BODY
#undef LB_INPUT
