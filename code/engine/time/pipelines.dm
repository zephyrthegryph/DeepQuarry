// Object-model core: pipelines (doc/rewrite/object_model_core.md section A.10).
//
// A pipeline is a behaviour whose work is a list of ordered stages sharing one frame. The ring
// (or a wake, for a reactive pipeline) makes one call per entity; the runner then walks the
// entity's plan, testing one bit per stage. Everything a hand-written frame loop used to do is
// here once:
//
//   - per-stage idle bits: a stage whose perform() returns STAGE_IDLE, or whose idle() holds after
//     it runs, is skipped until one of its wake_on channels changes or its rewake deadline fires
//   - parking: an entity whose stages are all idle for `park_after` frames in a row leaves the
//     ring (entity_park); any stage wake brings it back (entity_unpark)
//   - frame facts: lazily computed, cached per frame, read by run_if specs (FACT("alive"))
//   - variants: a family of stage types, one per entity type; the one whose `of` is deepest in
//     the entity's inheritance wins, resolved when the plan for that type is built
//   - F.abort(), rewake deadlines on the core wheel keyed by (entity, pipeline, stage), frame
//     pooling, catch-up (the behaviour's step accumulator), the missed-wake audit, and a stage
//     profiler.

GLOBAL_VAR_INIT(om_parking_enabled, TRUE)
/// Log every park and unpark (one line per transition; off by default).
GLOBAL_VAR_INIT(om_pipeline_trace, FALSE)

// ===================================================================== stages

/datum/work_stage
	parent_type = /datum/core_definition
	abstract_type = /datum/work_stage
	var/name
	/// Set to its own path on a grouping type (subtypes inherit a path that isn't theirs, as with
	/// abstract_type). A category's direct subtypes, and those of categories below it, are families.
	var/category
	/// Never taken from a category: listed by a decl's `stages` or added with pipeline_stage_add().
	var/extra = FALSE
	/// The pipeline type this stage belongs to. Expanding a category keeps only its own stages.
	var/pipeline
	/// The entity type this variant serves. Inside a family the variant whose `of` sits deepest
	/// in the entity's inheritance wins; a variant's ..() reaches its parent type's code.
	var/of = /datum
	/// Channels on the entity whose change wakes this stage once it is idle. The pipeline's
	/// `wake_all` channels wake every stage.
	var/wake_on = 0
	/// Check spec over frame facts (FACT("x"), NOT_OF(...), ALL_OF(...)) and ordinary checks
	/// (actor = the entity, target = the frame). The stage is skipped while it fails.
	var/run_if
	/// Families this stage runs after, or before.
	var/list/after
	var/list/before
	/// Position among stages that after/before don't order; lower runs first.
	var/order = 0
	/// Deciseconds: runs at most this often per entity.
	var/min_interval = 0
	/// What raises the wake_on channels (audit messages).
	var/woken_by
	/// Declared fields (fields.dm) of `of` that idle() and perform() read to decide there is work.
	/// The registry ORs their channels into wake_on at boot; list only the other channels there.
	var/list/reads

	// ---- compiled by the registry ----
	var/family
	/// Position in the pipeline's global order, and the depth of `of` in the type tree.
	var/pos = 0
	var/depth = 0
	var/datum/requirement_definition/compiled_run_if
	/// Fact bits run_if needs true / false. A general run_if (anything but facts under ALL_OF and
	/// NOT_OF) is evaluated through compiled_run_if instead.
	var/fact_req = 0
	var/fact_forbid = 0
	var/run_if_general = FALSE
	/// Channels that can flip run_if (the depends_on of its facts and checks).
	var/run_if_deps = 0
	/// TRUE when a failing general run_if idles the stage: every channel that can flip it wakes it.
	var/skip_idles = FALSE
	/// Fact bits whose depends_on channels all wake this stage: a skip blocked only by these idles.
	var/fact_covered = 0
	/// wake_on | the pipeline's wake_all.
	var/wake_mask = 0
	/// Has a run_if or a min_interval (one test on the fast path).
	var/gated = FALSE

/// Instance state (beyond its type and extras) that stage applies() reads, folded into the plan
/// key. An entity that changes it calls pipeline_pipe_replan() (see /mob/living/proc/recompose_life()).
/datum/proc/pipeline_plan_key()
	return null

/// Whether an entity (whose plan is being built) gets this stage at all. Evaluated once per plan,
/// so it may read only what the plan key covers: the type, its extras and pipeline_plan_key().
/datum/work_stage/proc/applies(datum/E)
	return TRUE

/// The work. Return STAGE_IDLE when nothing is left to do until woken.
/datum/work_stage/proc/perform(datum/E, datum/work_frame/F)
	SHOULD_NOT_SLEEP(TRUE)
	return

/// TRUE when this stage has nothing to do until one of its wake_on channels changes. Evaluated
/// after every run and by the missed-wake audit, so it must be cheap, read-only and right for an
/// entity that isn't running: the audit treats FALSE on an idle stage as a missed wake.
/datum/work_stage/proc/idle(datum/E)
	SHOULD_NOT_SLEEP(TRUE)
	return FALSE

/// For an idle stage that still drifts slowly: deciseconds until it wakes anyway, or 0.
/datum/work_stage/proc/rewake_delay(datum/E)
	SHOULD_NOT_SLEEP(TRUE)
	return 0

// ===================================================================== frames

/// One entity's state in one pipeline (rec.pipes[pipe_idx]), which is also the frame its stages
/// share: the facts of the frame in progress, and the idle bits, plan and parking state that
/// outlive it. Keeping both on one datum makes a frame one lookup. A stage run on demand
/// (pipeline_stage_run_now()) or audited gets a separate scratch frame of the same type.
/datum/work_frame
	parent_type = /datum/core_definition
	var/datum/entity
	var/datum/work_pipeline/pipeline
	var/datum/work_plan/plan
	/// Idle bits, one per plan position, OM_PIPE_WORD/OM_PIPE_BIT. All zero while all are awake.
	var/list/bits
	/// Stages whose idle bit is set.
	var/asleep = 0
	/// Frames in a row that ended with every stage idle (parking hysteresis).
	var/idle_frames = 0
	var/parked = FALSE
	/// Position in the scheduler's parked list for this pipeline, and when it parked.
	var/parked_index = 0
	EXPIRY_DECLARE(parked_at)
	/// Stage types added to this entity only (pipeline_stage_add()).
	var/list/extras
	/// Lazy: plan position -> time it last ran (min_interval stages).
	var/list/last_run
	var/frames = 0
	/// Seconds this frame covers: the step (step pipelines), the ring's dt, or the pipeline's
	/// nominal step for a stage run on demand.
	var/dt = 0
	/// Facts computed this frame (bit per fact) and their values.
	var/known = 0
	var/list/values
	/// OM_ABORT_* once a stage stopped the frame.
	var/aborted = 0
	/// Fact declarations: name = list(/datum/work_frame/<x>/proc/<compute>, depends_on channels).
	/// A fact's compute proc reads `entity`; depends_on lists the channels that can change it
	/// (0: none are raised for it, so a stage it skips never idles for that reason alone).
	var/list/facts

/// Called once at the start of every scheduled frame (not for audits or on-demand runs), for
/// per-frame state that must advance exactly once per frame.
/datum/work_frame/proc/begin()
	return

/// Called when the frame goes back to the pool: clear what begin() set.
/datum/work_frame/proc/reset()
	return

/// Value of fact `name` this frame (computed on first use).
/datum/work_frame/proc/fact(name)
	var/i = pipeline.fact_index[name]
	if(!i)
		CRASH("om: [pipeline.name] frame has no fact [name]")
	var/bit = 1 << (i - 1)
	if(!values)
		values = new /list(length(pipeline.fact_procs))
	if(known & bit)
		return values[i]
	known |= bit
	. = call(src, pipeline.fact_procs[i])()
	values[i] = .

/// Sets fact `name` for the rest of this frame (a stage whose result later stages gate on).
/datum/work_frame/proc/set_fact(name, value)
	var/i = pipeline.fact_index[name]
	if(!i)
		CRASH("om: [pipeline.name] frame has no fact [name]")
	known |= 1 << (i - 1)
	if(!values)
		values = new /list(length(pipeline.fact_procs))
	values[i] = value

/// Drops a cached fact: the next read computes it again (a stage that changed what it reads).
/datum/work_frame/proc/forget(name)
	var/i = pipeline.fact_index[name]
	if(i)
		known &= ~(1 << (i - 1))

/// Stops the frame after the current stage: `return F.abort()`. OM_ABORT_FRAME: nothing idles
/// this frame (the old early return before ..()); OM_ABORT_REST: the idles already decided stand.
/datum/work_frame/proc/abort(scope = OM_ABORT_FRAME)
	aborted = scope
	return STAGE_ABORT

/// TRUE when every fact in `req` is true and every one in `forbid` false.
/datum/work_frame/proc/facts_pass(req, forbid)
	return !facts_failed(req, forbid)

/// The facts (bits) of `req` that are false and of `forbid` that are true: 0 when all pass.
/datum/work_frame/proc/facts_failed(req, forbid)
	. = 0
	var/list/procs = pipeline.fact_procs
	var/list/V = values
	if(!V)
		V = new /list(length(procs))
		values = V
	var/need = req | forbid
	for(var/i in 1 to length(procs))
		var/bit = 1 << (i - 1)
		if(!(need & bit))
			continue
		if(!(known & bit))
			known |= bit
			V[i] = call(src, procs[i])()
		if((req & bit) ? !V[i] : V[i])
			. |= bit

/// A frame fact inside a check spec: FACT("alive"). The target is the frame.
/datum/requirement_definition/fact

/datum/requirement_definition/fact/why_not(datum/actor, datum/target)
	var/datum/work_frame/F = target
	if(!istype(F))
		return "no frame"
	return F.fact(arg) ? null : "not [arg]"

// ===================================================================== per entity

/// An ordered stage list shared by every entity with the same plan key (type and extras).
/datum/work_plan
	parent_type = /datum/core_definition
	var/key
	var/list/stages
	var/n = 0
	/// Stage pos (pipeline order) -> position in `stages`, 0 when absent.
	var/list/index_of
	/// Parallel to `stages`: TRUE where the stage has a run_if or a min_interval.
	var/list/gated

// ===================================================================== the pipeline

/datum/work_pipeline
	parent_type = /datum/scheduled_behaviour
	abstract_type = /datum/work_pipeline
	/// Stage types, or categories of them. A category contributes every family below it whose
	/// `pipeline` is this type. Decls add stages per entity type (their `stages` rows).
	var/list/stages
	var/frame_type = /datum/work_frame
	/// Frames in a row with every stage idle before the entity parks. 0: never parks.
	var/park_after = 2
	/// Channels that wake every stage (part of every stage's wake mask).
	var/wake_all = 0
	/// Reactive pipelines (no cadence): deciseconds before a stage that ran and still has work
	/// runs again. 0: it waits for its next wake.
	var/busy_retry = 0
	/// Time every Nth frame (all pipelines' frames counted together) per stage and entity type.
	var/profile_stride = 0

	// ---- compiled by the registry ----
	var/pipe_idx = 0
	/// No cadence: stages run when woken, then idle again.
	var/reactive = FALSE
	/// The frame type is a subtype (it may override begin() and reset()).
	var/frame_hooks = FALSE
	/// OM_PIPE_MODE_* bits for run_frame(): one read instead of several.
	var/run_mode = 0
	/// Every stage def this pipeline can run, by pos.
	var/list/stage_defs
	/// Family roots from `stages`, in order.
	var/list/roots
	/// Family root -> its variants, deepest `of` first (ties: the least derived stage type).
	var/list/variants
	/// Fact name -> index; index -> compute proc; index -> depends_on.
	var/list/fact_index
	var/list/fact_procs
	var/list/fact_deps
	/// Plan key -> /datum/work_plan (built on first use per key).
	var/list/plans

/datum/work_pipeline/on_start(datum/E)
	var/datum/work_frame/S = pipeline_pipe_state(E, src, TRUE)
	if(!S)
		return
	if(reactive)
		pipeline_pipe_set_all(S, TRUE)
		entity_wake_id(E, id, CHANGE_EXPLICIT)
	else
		pipeline_pipe_set_all(S, FALSE)
		S.idle_frames = 0

/datum/work_pipeline/on_stop(datum/E)
	var/datum/work_frame/S = pipeline_pipe_state(E, src)
	if(S?.parked)
		unlist_parked(E.om_rec.sched, S)
		S.parked = FALSE
	deadline_cancel_all_after(E, src)

/datum/work_pipeline/on_step(datum/E)
	run_frame(E, step_interval)

/datum/work_pipeline/tick(datum/E, dt)
	run_frame(E, dt)

/datum/work_pipeline/on_wake(datum/E, changes)
	var/datum/work_frame/S = pipeline_pipe_state(E, src)
	if(!S)
		return
	if(S.parked)
		pipeline_pipe_set_all(S, FALSE)
		unpark(E, S, changes)
		return
	if(!S.asleep)
		return
	var/woke = FALSE
	var/list/stages = S.plan.stages
	var/list/bits = S.bits
	for(var/w in 1 to length(bits))
		var/word = bits[w]
		if(!word)
			continue
		var/base = (w - 1) << 4
		for(var/b in 0 to 15)
			if(!(word & (1 << b)))
				continue
			var/datum/work_stage/T = stages[base + b + 1]
			if(T.wake_mask & changes)
				bits[w] &= ~(1 << b)
				S.asleep--
				woke = TRUE
	if(woke)
		S.idle_frames = 0
		if(reactive)
			run_frame(E, 0)

/// A stage's rewake deadline: wakes that stage only. A parked entity comes back for it and parks
/// again as soon as the stage idles (it counts as one idle frame already).
/datum/work_pipeline/on_keyed_deadline(datum/E, sub)
	var/datum/work_frame/S = pipeline_pipe_state(E, src)
	if(!S)
		return
	var/i = S.plan.index_of[sub - OM_DL_STAGE + 1]
	if(!i)
		return
	var/w = OM_PIPE_WORD(i)
	var/bit = OM_PIPE_BIT(i)
	if(!(S.bits[w] & bit))
		return
	S.bits[w] &= ~bit
	S.asleep--
	if(S.parked)
		unpark(E, S, 0)
		S.idle_frames = max(park_after - 1, 0)
	else if(reactive)
		run_frame(E, 0)

/// Runs stage `T` (plan position `_i`, word `_w`, bit `_bit`) inside a frame. A macro so the awake
/// fast path, the word walk and the profiled frame share one body without a proc call per stage.
/// `_PERFORM` is the call (timed or not). Locals are few on purpose: every local costs on entry.
#define OM_RUN_STAGE(_i, _w, _bit, _PERFORM) \
	T = stages[_i]; \
	if(gated[_i]) { \
		result = gate(E, F, T, _i); \
		if(result) { \
			if(result > 1) { bits[_w] |= _bit; asleep++; if(result == 2) { LAZYADD(idled, _i); } } \
			continue; \
		} \
	} \
	result = _PERFORM; \
	if(result == STAGE_ABORT || E.gc_destroyed) { stop = TRUE; break; } \
	if(result == STAGE_IDLE || T.idle(E)) { \
		bits[_w] |= _bit; \
		asleep++; \
		LAZYADD(idled, _i); \
		result = T.rewake_delay(E); \
		if(result > 0) { deadline_deadline(E, result, src, OM_DL_STAGE - 1 + T.pos); } \
	} else if(mode & OM_PIPE_MODE_REACTIVE) { \
		bits[_w] |= _bit; \
		asleep++; \
		LAZYADD(idled, _i); \
		if(busy_retry > 0) { deadline_deadline(E, busy_retry, src, OM_DL_STAGE - 1 + T.pos); } \
	}

/// The whole frame loop, parameterised by how a stage is performed.
#define OM_RUN_FRAME(_PERFORM) \
	if(!asleep) { \
		for(var/i in 1 to n) { \
			OM_RUN_STAGE(i, (((i - 1) >> 4) + 1), (1 << ((i - 1) & 15)), _PERFORM) \
		} \
	} else { \
		for(var/w in 1 to length(bits)) { \
			var/base = (w - 1) << 4; \
			var/awake = ~bits[w] & ((1 << min(16, n - base)) - 1); \
			var/b = -1; \
			while(awake) { \
				b++; \
				if(!(awake & 1)) { awake >>= 1; continue; } \
				awake >>= 1; \
				OM_RUN_STAGE(base + b + 1, w, (1 << b), _PERFORM) \
			} \
			if(stop) { break; } \
		} \
	}

/// Runs one frame of `E` now: every awake stage of its plan, in order.
/datum/work_pipeline/proc/run_frame(datum/E, dt)
	var/datum/scheduler_record/rec = E.om_rec
	if(!rec)
		return
	var/datum/work_frame/F = length(rec.pipes) >= pipe_idx ? rec.pipes[pipe_idx] : null
	if(!F)
		return
	var/mode = run_mode
	if(mode & OM_PIPE_MODE_PROFILING)
		var/datum/time_scheduler/sched = rec.sched
		if(!(++sched.pipe_frames % profile_stride))
			return run_frame_profiled(E, dt, rec, F)
	F.dt = dt
	if(mode & OM_PIPE_MODE_FACTS)
		F.known = 0
	if(mode & OM_PIPE_MODE_HOOKS)
		F.begin()
	F.frames++
	var/datum/work_plan/plan = F.plan
	var/list/stages = plan.stages
	var/list/gated = plan.gated
	var/list/bits = F.bits
	var/asleep = F.asleep
	var/n = plan.n
	var/list/idled
	var/stop = FALSE
	var/datum/work_stage/T
	var/result
	OM_RUN_FRAME(T.perform(E, F))
	F.asleep = asleep
	if(stop || F.plan != plan || rec.torn_down)
		frame_stopped(rec, F, plan, idled)
		return
	if(mode & OM_PIPE_MODE_PARKS)
		if(asleep >= n)
			if(++F.idle_frames >= park_after)
				park(E, F)
		else if(F.idle_frames)
			F.idle_frames = 0

/// run_frame() for a frame the profiler samples: each stage and the whole frame are timed.
/datum/work_pipeline/proc/run_frame_profiled(datum/E, dt, datum/scheduler_record/rec, datum/work_frame/F)
	var/mode = run_mode
	var/datum/time_scheduler/sched = rec.sched
	var/frame_start = TICK_USAGE
	F.dt = dt
	if(mode & OM_PIPE_MODE_FACTS)
		F.known = 0
	if(mode & OM_PIPE_MODE_HOOKS)
		F.begin()
	F.frames++
	var/datum/work_plan/plan = F.plan
	var/list/stages = plan.stages
	var/list/gated = plan.gated
	var/list/bits = F.bits
	var/asleep = F.asleep
	var/n = plan.n
	var/list/idled
	var/stop = FALSE
	var/datum/work_stage/T
	var/result
	OM_RUN_FRAME(pipeline_stage_timed(T, E, F, sched, profile_stride))
	var/key = "type:[E.type]"
	sched.stage_cost[key] += TICK_DELTA_TO_MS(TICK_USAGE - frame_start) * profile_stride
	sched.stage_calls[key] += profile_stride
	F.asleep = asleep
	if(stop || F.plan != plan || rec.torn_down)
		frame_stopped(rec, F, plan, idled)
		return
	if(mode & OM_PIPE_MODE_PARKS)
		if(asleep >= n)
			if(++F.idle_frames >= park_after)
				park(E, F)
		else if(F.idle_frames)
			F.idle_frames = 0

#undef OM_RUN_FRAME
#undef OM_RUN_STAGE

/// One timed stage run (profiled frames only).
/proc/pipeline_stage_timed(datum/work_stage/T, datum/E, datum/work_frame/F, datum/time_scheduler/sched, stride)
	var/t0 = TICK_USAGE
	. = T.perform(E, F)
	var/key = "[T.type]"
	sched.stage_cost[key] += TICK_DELTA_TO_MS(TICK_USAGE - t0) * stride
	sched.stage_calls[key] += stride

/// A frame that a stage stopped: it deleted the entity, aborted the frame, or changed the plan
/// (the rest of the frame ran the old plan; nothing is booked against the new one).
/datum/work_pipeline/proc/frame_stopped(datum/scheduler_record/rec, datum/work_frame/F, datum/work_plan/plan, list/idled)
	if(rec.torn_down || QDELETED(F.entity))
		return
	var/aborted = F.aborted
	F.aborted = 0
	if(F.plan != plan || aborted != OM_ABORT_FRAME)
		return
	for(var/i in idled)
		F.bits[OM_PIPE_WORD(i)] &= ~OM_PIPE_BIT(i)
		F.asleep--

/// A gated stage (run_if or min_interval): 0 runs it; 1 skips it; 2 skips and idles it (a fact
/// its wake mask reports blocked it, or its idle() holds); 3 skips and idles it until its
/// min_interval ends (a rewake).
/datum/work_pipeline/proc/gate(datum/E, datum/work_frame/F, datum/work_stage/T, i)
	if(T.fact_req || T.fact_forbid)
		var/failed = F.facts_failed(T.fact_req, T.fact_forbid)
		if(failed)
			return (reactive || !(failed & ~T.fact_covered) || T.idle(E)) ? 2 : 1
	else if(T.run_if_general && !isnull(T.compiled_run_if.why_not(E, F)))
		return (reactive || T.skip_idles || T.idle(E)) ? 2 : 1
	if(T.min_interval)
		var/wait = pipeline_stage_throttle(F, i, T, E.om_rec.sched.now())
		if(wait > 0)
			deadline_deadline(E, wait, src, OM_DL_STAGE - 1 + T.pos)
			return 3
	return 0

/// Deciseconds before stage `T` (plan position `i`) may run again, 0 when it may run now (and
/// then it is recorded as running now).
/proc/pipeline_stage_throttle(datum/work_frame/S, i, datum/work_stage/T, now)
	if(!S.last_run)
		S.last_run = new /list(S.plan.n)
	var/last = S.last_run[i]
	if(!isnull(last) && now < last + T.min_interval)
		return last + T.min_interval - now
	S.last_run[i] = now
	return 0

/// A scratch frame for a run outside the entity's own frames (on demand, the audit). The scheduler
/// keeps one free per pipeline; a nested run makes another.
/datum/work_pipeline/proc/frame_acquire(datum/time_scheduler/sched, datum/E, dt)
	var/list/free = sched.free_frames
	if(length(free) < pipe_idx)
		free.len = pipe_idx
	var/datum/work_frame/F = free[pipe_idx]
	if(F)
		free[pipe_idx] = null
	else
		F = new frame_type
		F.pipeline = src
	F.entity = E
	F.dt = dt
	F.known = 0
	F.aborted = 0
	return F

/// Back to the free slot, cleared. A nested run's extra frame is dropped if the slot is taken.
/datum/work_pipeline/proc/frame_release(datum/time_scheduler/sched, datum/work_frame/F)
	if(frame_hooks)
		F.reset()
	F.entity = null
	F.values = null
	var/list/free = sched.free_frames
	if(!free[pipe_idx])
		free[pipe_idx] = F

// ---------------------------------------------------------------- parking

/datum/work_pipeline/proc/park(datum/E, datum/work_frame/S)
	if(S.parked || !GLOB.om_parking_enabled)
		return
	var/datum/time_scheduler/sched = E.om_rec.sched
	S.parked = TRUE
	S.idle_frames = 0
	EXPIRY_STAMP(S, parked_at, CLOCK_WORLD)
	if(length(sched.parked) < pipe_idx)
		sched.parked.len = pipe_idx
	var/list/L = sched.parked[pipe_idx]
	if(!L)
		L = list()
		sched.parked[pipe_idx] = L
	L += E
	S.parked_index = length(L)
	sched.stat_inc(id, OM_STAT_PARKS)
	entity_park(E, src)
	if(GLOB.om_pipeline_trace)
		log_runtime("OM_PARK: [name] [E] ([E.type]) parked; [length(L)] parked")

/// Back on the ring. `changes` (0 for a rewake) is only for the trace.
/datum/work_pipeline/proc/unpark(datum/E, datum/work_frame/S, changes)
	if(!S.parked)
		return
	var/datum/time_scheduler/sched = E.om_rec.sched
	S.parked = FALSE
	unlist_parked(sched, S)
	sched.stat_inc(id, OM_STAT_UNPARKS)
	entity_unpark(E, src)
	if(GLOB.om_pipeline_trace)
		log_runtime("OM_PARK: [name] [E] ([E.type]) unparked by [changes ? "channels [changes]" : "a stage rewake"] after [DisplayTimeText(world.time - S.parked_at)]")

/// Removes an entity from the parked list in O(1): the last entry takes its place.
/datum/work_pipeline/proc/unlist_parked(datum/time_scheduler/sched, datum/work_frame/S)
	var/list/L = length(sched.parked) >= pipe_idx ? sched.parked[pipe_idx] : null
	var/i = S.parked_index
	S.parked_index = 0
	var/n = length(L)
	if(!i || i > n)
		return
	if(i != n)
		var/datum/last = L[n]
		L[i] = last
		var/datum/work_frame/LS = pipeline_pipe_state(last, src)
		if(LS)
			LS.parked_index = i
	L.len = n - 1

/// Entities of this pipeline parked on `sched`.
/datum/work_pipeline/proc/parked_on(datum/time_scheduler/sched)
	return length(sched.parked) >= pipe_idx ? sched.parked[pipe_idx] : null

// ---------------------------------------------------------------- plans and variants

/// The variant of family `root` serving entity type `path`, or null.
/datum/work_pipeline/proc/resolve(root, path)
	for(var/datum/work_stage/V as anything in variants[root])
		if(ispath(path, V.of))
			return V
	return null

/// The plan for `E` (its type plus `extras`), built once per key.
/datum/work_pipeline/proc/plan_for(datum/E, list/extras)
	var/key = "[E.type]"
	var/state_key = E.pipeline_plan_key()
	if(state_key)
		key += "#[state_key]"
	if(length(extras))
		var/list/names = list()
		for(var/path in extras)
			names += "[path]"
		sortTim(names, GLOBAL_PROC_REF(cmp_text_asc))
		key += "|[jointext(names, ",")]"
	var/datum/work_plan/plan = plans[key]
	if(plan)
		return plan
	var/datum/definition_registry/reg = definition_registry()
	var/list/chosen = list()
	for(var/root in roots)
		var/datum/work_stage/V = resolve(root, E.type)
		if(V && V.applies(E))
			chosen |= V
	var/list/more = list()
	for(var/path in reg.type_table(E.type).stages)
		more |= path
	for(var/path in extras)
		more |= path
	for(var/path in more)
		var/datum/work_stage/listed = reg.stage_by_type[path]
		if(!listed || listed.pipeline != type)
			continue
		var/datum/work_stage/V = resolve(listed.family, E.type) || listed
		if(V.applies(E))
			chosen |= V
	chosen = sortTim(chosen, GLOBAL_PROC_REF(cmp_om_stage_pos))
	plan = new
	plan.key = key
	plan.stages = chosen
	plan.n = length(chosen)
	plan.index_of = new /list(length(stage_defs))
	plan.gated = new /list(plan.n)
	for(var/i in 1 to plan.n)
		var/datum/work_stage/T = chosen[i]
		plan.index_of[T.pos] = i
		plan.gated[i] = T.gated
	plans[key] = plan
	return plan

/proc/cmp_om_stage_pos(datum/work_stage/a, datum/work_stage/b)
	return a.pos - b.pos

// ---------------------------------------------------------------- entity API

/// `E`'s state in pipeline `P` (type or def). `create`: allocate it and its plan if missing.
/proc/pipeline_pipe_state(datum/E, P, create = FALSE)
	var/datum/scheduler_record/rec = create ? scheduler_record_of(E) : E?.om_rec
	if(!rec)
		return null
	var/datum/work_pipeline/def = istype(P, /datum/work_pipeline) ? P : definition_registry().behaviour(P)
	var/idx = def.pipe_idx
	if(length(rec.pipes) >= idx && rec.pipes[idx])
		return rec.pipes[idx]
	if(!create)
		return null
	if(length(rec.pipes) < idx)
		if(!rec.pipes)
			rec.pipes = list()
		rec.pipes.len = idx
	var/datum/work_frame/S = new def.frame_type
	S.pipeline = def
	S.entity = E
	S.plan = def.plan_for(E, null)
	S.bits = pipeline_pipe_words(S.plan.n)
	rec.pipes[idx] = S
	return S

/proc/pipeline_pipe_words(n)
	. = new /list(OM_PIPE_WORD(max(n, 1)))
	var/list/L = .
	for(var/w in 1 to length(L))
		L[w] = 0

/// Sets every stage of `S` idle (TRUE) or awake (FALSE).
/proc/pipeline_pipe_set_all(datum/work_frame/S, asleep, idle_frames = null)
	var/list/bits = S.bits
	var/n = S.plan.n
	for(var/w in 1 to length(bits))
		bits[w] = 0
	S.asleep = 0
	if(asleep)
		for(var/i in 1 to n)
			bits[OM_PIPE_WORD(i)] |= OM_PIPE_BIT(i)
		S.asleep = n
	if(!isnull(idle_frames))
		S.idle_frames = idle_frames

/// TRUE while stage `stage_type` (a family root or variant) is idle on `E`.
/proc/pipeline_stage_idle(datum/E, P, stage_type)
	var/datum/work_frame/S = pipeline_pipe_state(E, P)
	if(!S)
		return FALSE
	var/i = pipeline_plan_position(S, stage_type)
	return i && (S.bits[OM_PIPE_WORD(i)] & OM_PIPE_BIT(i))

/// Plan position of the variant of `stage_type`'s family on `E`'s plan, or 0.
/proc/pipeline_plan_position(datum/work_frame/S, stage_type)
	var/datum/work_stage/listed = definition_registry().stage_by_type[stage_type]
	if(!listed)
		return 0
	for(var/i in 1 to S.plan.n)
		var/datum/work_stage/T = S.plan.stages[i]
		if(T.family == listed.family)
			return i
	return 0

/// TRUE while `E` is parked in pipeline `P`.
/proc/pipeline_pipe_parked(datum/E, P)
	var/datum/work_frame/S = pipeline_pipe_state(E, P)
	return S?.parked

/// Adds (or removes) a stage for this entity only: its plan is rebuilt and every stage wakes.
/// Nothing happens for an entity that doesn't run the stage's pipeline.
/proc/pipeline_stage_add(datum/E, stage_type)
	var/datum/work_stage/T = definition_registry().stage_by_type[stage_type]
	if(!T)
		CRASH("om: [stage_type] is not a stage")
	if(!E?.om_rec || !entity_attached(E, T.pipeline))
		return
	var/datum/work_frame/S = pipeline_pipe_state(E, T.pipeline, TRUE)
	if(!S || (stage_type in S.extras))
		return
	LAZYADD(S.extras, stage_type)
	pipeline_pipe_replan(E, T.pipeline, S)

/proc/pipeline_pipe_replan(datum/E, P, datum/work_frame/S)
	var/datum/work_pipeline/def = definition_registry().behaviour(P)
	var/datum/work_plan/plan = def.plan_for(E, S.extras)
	if(plan == S.plan)
		return
	deadline_cancel_all_after(E, def)
	S.plan = plan
	S.bits = pipeline_pipe_words(plan.n)
	S.asleep = 0
	S.idle_frames = 0
	S.last_run = null
	if(def.reactive)
		pipeline_pipe_set_all(S, TRUE)
	if(S.parked)
		def.unpark(E, S, CHANGE_EXPLICIT)
	entity_wake_id(E, def.id, CHANGE_EXPLICIT)

/// Runs `E`'s variant of family `stage_type` now, outside the schedule, with its own frame (facts
/// work; dt is the pipeline's nominal step). Its idle bit is unchanged. Returns perform()'s result.
/proc/pipeline_stage_run_now(datum/E, stage_type)
	var/datum/definition_registry/reg = definition_registry()
	var/datum/work_stage/listed = reg.stage_by_type[stage_type]
	if(!listed)
		CRASH("om: [stage_type] is not a stage")
	var/datum/work_pipeline/P = reg.behaviour(listed.pipeline)
	var/datum/work_stage/T = P.resolve(listed.family, E.type)
	if(!T)
		return null
	var/datum/time_scheduler/sched = E.om_rec?.sched || time_scheduler()
	var/datum/work_frame/F = P.frame_acquire(sched, E, P.step_interval || P.every / 10)
	. = T.perform(E, F)
	P.frame_release(sched, F)

/// Runs one whole frame of pipeline `P` on `E` now (content that must see a frame at once, and
/// tests). It is a real frame: idles, rewakes and parking follow from it.
/proc/pipeline_run_frame_now(datum/E, P)
	var/datum/work_pipeline/def = definition_registry().behaviour(P)
	if(!pipeline_pipe_state(E, def) && entity_attached(E, def))
		pipeline_pipe_state(E, def, TRUE)
	// A real pass drains the wake queue before it runs frames: deliver the wakes already raised
	// for this pipeline on E (a setter called just before), so the frame sees them instead of
	// running against stages still idle from before the change. The queue entry left behind
	// finds nothing pending and is skipped.
	var/datum/scheduler_record/rec = E.om_rec
	var/att_i = rec?.att.Find(def)
	if(att_i && rec.att_pend[att_i] && (rec.att_state[att_i] & OM_ATT_STARTED))
		var/bits = rec.att_pend[att_i]
		rec.att_pend[att_i] = 0
		rec.pend_union &= ~bits
		rec.sched.call_hook(rec, def, OM_HOOK_WAKE, bits)
		if(rec.torn_down)
			return
	def.run_frame(E, def.step_interval || def.every / 10)

/// Entities parked in `P` on the live scheduler (or `sched`).
/proc/pipeline_pipeline_parked_count(P, datum/time_scheduler/sched)
	sched = sched || GLOB.om_live_sched || time_scheduler()
	var/datum/work_pipeline/def = definition_registry().behaviour(P)
	return length(def.parked_on(sched))

// ---------------------------------------------------------------- missed-wake audit

/// The first idle stage of `E` whose idle() no longer holds although its run_if passes and no
/// rewake is pending: a producer changed `E` without raising a channel in its wake_on.
/datum/work_pipeline/proc/missed_wake(datum/E)
	var/datum/work_frame/S = pipeline_pipe_state(E, src)
	if(!S || !S.asleep)
		return null
	var/datum/scheduler_record/rec = E.om_rec
	var/datum/time_scheduler/sched = rec.sched
	// Channels raised for this pipeline but not yet delivered (the wake queue drains at the
	// start of the lane, so a change raised by a frame later in the same pass waits for the
	// next one): a stage they wake is not a miss, its wake is on its way.
	var/att_i = rec.att.Find(src)
	var/pending = att_i ? rec.att_pend[att_i] : 0
	var/datum/work_frame/F = frame_acquire(sched, E, 0)
	. = null
	for(var/i in 1 to S.plan.n)
		if(!(S.bits[OM_PIPE_WORD(i)] & OM_PIPE_BIT(i)))
			continue
		var/datum/work_stage/T = S.plan.stages[i]
		if(pending & T.wake_mask)
			continue
		if(deadline_deadline_pending(E, src, OM_DL_STAGE - 1 + T.pos))
			continue
		if(T.fact_req || T.fact_forbid)
			if(!F.facts_pass(T.fact_req, T.fact_forbid))
				continue
		else if(T.run_if_general && !isnull(T.compiled_run_if.why_not(E, F)))
			continue
		if(reactive && !T.idle(E))
			// Reactive stages idle between wakes by design; only a lost rewake is a miss.
			continue
		if(!T.idle(E))
			. = T
			break
	frame_release(sched, F)

/// Audits a sample of parked entities and of awake ones with idle stages, for every pipeline.
/// A miss is logged, fails the unit test run, and wakes the entity.
/proc/pipeline_pipeline_audit(datum/time_scheduler/sched, parked_sample = 400, awake_sample = 100, expected = FALSE)
	sched = sched || GLOB.om_live_sched || time_scheduler()
	. = list()
	for(var/datum/work_pipeline/P as anything in definition_registry().pipelines)
		if(P.reactive)
			continue
		var/list/sample = list()
		var/list/L = P.parked_on(sched)
		var/count = length(L)
		if(length(sched.audit_cursor) < P.pipe_idx)
			sched.audit_cursor.len = P.pipe_idx
		var/cursor = sched.audit_cursor[P.pipe_idx] || 0
		for(var/i in 1 to min(count, parked_sample))
			cursor = (cursor % count) + 1
			sample += L[cursor]
		sched.audit_cursor[P.pipe_idx] = cursor
		var/taken = 0
		for(var/datum/cadence_ring/R as anything in (length(sched.rings) >= P.id ? sched.rings[P.id] : null))
			for(var/list/slot as anything in R.slots)
				for(var/datum/E as anything in slot)
					if(taken >= awake_sample)
						break
					if(E && E.om_rec)
						var/datum/work_frame/S = pipeline_pipe_state(E, P)
						if(S?.asleep)
							sample += E
							taken++
		for(var/datum/E as anything in sample)
			if(QDELETED(E) || !E.om_rec)
				continue
			// An extension may still have its initial wake queued: it has not been woken
			// yet, so nothing can have been missed.
			if(P.first_wake_pending(E))
				GLOB.om_audit_first_wake_skips++
				continue
			var/datum/work_stage/T = P.missed_wake(E)
			if(!T)
				continue
			. += T
			P.report_missed(E, T, expected)

/// Audit skips of entities whose first wake was still queued (diagnostics; see pipeline_pipeline_audit()).
GLOBAL_VAR_INIT(om_audit_first_wake_skips, 0)

/// TRUE while `E`'s declared first wake is scheduled but has not run yet. Until it runs, `E`
/// has armed none of its wake producers, so a parked stage with work is not a lost wake.
/datum/work_pipeline/proc/first_wake_pending(datum/E)
	return FALSE

/datum/work_pipeline/proc/report_missed(datum/E, datum/work_stage/T, expected)
	var/datum/work_frame/S = pipeline_pipe_state(E, src)
	var/datum/time_scheduler/sched = E.om_rec.sched
	sched.stat_inc(id, OM_STAT_MISSED)
	var/message = "OM_AUDIT: MISSED WAKE [E] ([E.type]) in [name], [S.parked ? "parked since [DisplayTimeText(world.time - S.parked_at)] ago" : "awake, some stages idle"]: stage [T.type] ([T.name], wake_on [T.wake_mask]) has work but was idle. Woken by: [T.woken_by || "undeclared"]. A producer changed it without raising its channel (changed)."
	log_runtime(message)
	log_world(message)
#if defined(UNIT_TESTS)
	if(!expected)
		stack_trace(message)
		if(GLOB.current_test)
			GLOB.current_test.Fail(message, __FILE__, __LINE__)
		else
			GLOB.failed_any_test = TRUE
#endif
	on_wake(E, T.wake_mask)

// ---------------------------------------------------------------- sleepers

/// A reactive behaviour for an entity that sleeps between wakes it armed itself: entity_watch()es on
/// other entities' channels (CHANGE_RELATED arrives here) and om_after() timers. Subtypes do the
/// work in on_wake(). Entities carrying one are sampled by the missed-wake audit, which asks the
/// entity's pipeline_sleep_violation() whether it sleeps through work.
/datum/scheduled_behaviour/sleeper
	abstract_type = /datum/scheduled_behaviour/sleeper
	wake_on = CHANGE_RELATED

/datum/scheduled_behaviour/sleeper/on_start(datum/E)
	GLOB.om_sleepers[E] = TRUE

/datum/scheduled_behaviour/sleeper/on_stop(datum/E)
	GLOB.om_sleepers -= E

/// Entities with a sleeper behaviour attached (the audit's sample space).
GLOBAL_LIST_EMPTY(om_sleepers)

/// For the audit: null while this entity's sleep holds, else why it should be awake.
/datum/proc/pipeline_sleep_violation()
	SHOULD_NOT_SLEEP(TRUE)
	return null

/// Samples sleepers and asks each whether it sleeps through work. Returns the findings; with
/// `report`, a test failure in unit tests and a log line on servers.
/proc/pipeline_sleeper_audit(sample = 64, report = FALSE)
	var/list/findings = list()
	var/list/pool = GLOB.om_sleepers
	var/count = length(pool)
	if(!count)
		return findings
	var/list/candidates = list()
	if(count <= sample)
		for(var/datum/D as anything in pool)
			candidates += D
	else
		for(var/i in 1 to sample)
			candidates += pool[rand(1, count)]
	for(var/datum/D as anything in candidates)
		if(!D || QDELETED(D))
			continue
		var/violation = D.pipeline_sleep_violation()
		if(!violation)
			continue
		findings += "[D.type]: [violation]"
		if(!report)
			continue
		var/message = "OM_AUDIT: MISSED WAKE [D] ([D.type]) sleeping: [violation]"
		log_runtime(message)
#if defined(UNIT_TESTS)
		if(GLOB.current_test)
			GLOB.current_test.Fail(message, __FILE__, __LINE__)
#endif
	return findings

/// A sleeper that waits only on its own om_after() timers: attached so the audit samples it.
/datum/scheduled_behaviour/sleeper/timed
	name = "timed sleeper"
	wake_on = 0

// ---------------------------------------------------------------- wake tracing (tests)

/// Tests: entity -> behaviour wakes and timer calls delivered to it, + 1 (a traced entity is truthy).
GLOBAL_LIST_EMPTY(om_traced)
/// Tests: entity -> union of the change bits its traced wakes arrived with.
GLOBAL_LIST_EMPTY(om_traced_bits)

/// Counts behaviour wakes (on_wake) and om_after() calls delivered to `E` from now on.
/proc/pipeline_trace(datum/E)
	if(!GLOB.om_traced[E])
		GLOB.om_traced[E] = 1

/proc/pipeline_traced_count(datum/E)
	var/n = GLOB.om_traced[E]
	return n ? n - 1 : 0

/proc/pipeline_untrace(datum/E)
	GLOB.om_traced -= E
	GLOB.om_traced_bits -= E
